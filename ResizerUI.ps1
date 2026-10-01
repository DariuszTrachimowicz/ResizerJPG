. (Join-Path $PSScriptRoot 'ResizerUpdates.ps1')

function Invoke-ResizerUiEvents {
    $frame = New-Object Windows.Threading.DispatcherFrame
    [void][Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{ $frame.Continue = $false })
    [Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Show-ResizerWindow {
    param([string[]]$InitialFolders = @(), [scriptblock]$OnShown)

    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
    $appInfo = Get-ResizerAppInfo
    [xml]$xaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ResizerWindow.xaml') -Raw
    $reader = New-Object Xml.XmlNodeReader($xaml)
    try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
    $ui = @{}
    # Find names using their namespace directly, without relying on XML prefix bindings.
    foreach ($node in $xaml.SelectNodes('//*')) {
        $name = $node.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')
        if ($name) { $ui[$name] = $window.FindName($name) }
    }
    $window.Tag = $ui
    $window.Title = 'Resizer JPG ' + $appInfo.version + ' | Digital Xperts'
    $ui.VersionFooter.Text = 'Wersja ' + $appInfo.version
    $ui.InstalledVersion.Text = 'Wersja zainstalowana: ' + $appInfo.version
    $ui.RepositoryLink.Content = $appInfo.repository
    $state = @{ Busy=$false; Cancel=$false; Updating=$false; Paths=(New-Object 'Collections.Generic.List[string]'); Photos=@(); PhotoIndex=0; Outputs=@(); CustomOutput=$false; Candidate=$null; Tasks=(New-Object 'Collections.Generic.List[object]'); NetworkBusy=$false; Downloading=$false; Installing=$false; Ready=$false }
    $configDirectory = Join-Path $env:LOCALAPPDATA 'DigitalXperts\ResizerJPG'
    $configFile = Join-Path $configDirectory 'settings.json'
    if (Test-Path -LiteralPath $configFile) {
        try { $settings = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json; $ui.AutoUpdate.IsChecked = [bool]$settings.CheckOnStartup } catch { }
    }

    function New-WpfBitmap([string]$Path) {
        $bitmap = New-Object Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource = New-Object Uri([IO.Path]::GetFullPath($Path))
        $bitmap.EndInit()
        $bitmap.Freeze()
        return $bitmap
    }

    $ui.BrandLogo.Source = New-WpfBitmap (Join-Path $PSScriptRoot 'digital-xperts-logo.png')
    $window.Icon = New-WpfBitmap (Join-Path $PSScriptRoot 'resizer-jpg.ico')
    $icons = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'lucide-paths.json') -Raw | ConvertFrom-Json
    $iconMap = @{
        FolderPlusIcon='folder-plus';ImagesIcon='images';TrashIcon='trash-2';PrevIcon='chevron-left';NextIcon='chevron-right';
        EmptyImageIcon='image';OutputFolderIcon='folder-open';ResetIcon='refresh-cw';PlayIcon='play';StopIcon='square';
        UpdatesIcon='refresh-cw';CloseUpdatesIcon='x';CloseLogIcon='x'
    }
    foreach ($key in $iconMap.Keys) {
        $canvas = New-Object Windows.Controls.Canvas
        $canvas.Width = 24; $canvas.Height = 24
        $path = New-Object Windows.Shapes.Path
        $path.Data = [Windows.Media.Geometry]::Parse([string]$icons.($iconMap[$key]))
        $path.StrokeThickness = 1.7
        $path.StrokeStartLineCap = 'Round'; $path.StrokeEndLineCap = 'Round'; $path.StrokeLineJoin = 'Round'
        $binding = New-Object Windows.Data.Binding('Foreground')
        $binding.Source = $ui[$key]
        [void]$path.SetBinding([Windows.Shapes.Shape]::StrokeProperty,$binding)
        [void]$canvas.Children.Add($path)
        $view = New-Object Windows.Controls.Viewbox
        $view.Child = $canvas
        $ui[$key].Content = $view
    }

    $editables = @($ui.Settings,$ui.Sources,$ui.AddFolder,$ui.AddFiles,$ui.RemoveSource,$ui.ClearSources,$ui.Output,$ui.ChooseOutput,$ui.DefaultOutput,$ui.UpdatesButton)
    function Get-Ratio { return [string]$ui.Ratio.SelectedItem.Tag }
    function Set-Custom { if (-not $state.Updating) { $ui.Profile.SelectedIndex = 1 } }

    function Get-ExportOptions {
        $values = @{}
        foreach ($entry in @(@('Width',$ui.WidthBox,20000),@('Height',$ui.HeightBox,20000),@('Dpi',$ui.DpiBox,600),@('Quality',$ui.QualityNumber,100))) {
            $number = 0
            if (-not [int]::TryParse($entry[1].Text,[ref]$number) -or $number -lt 1 -or $number -gt $entry[2]) { throw ('Niepoprawna wartosc: {0} (1-{1}).' -f $entry[0],$entry[2]) }
            $values[$entry[0]] = $number
        }
        $values.Ratio = Get-Ratio
        $values.Mode = if ($ui.Mode.SelectedIndex -eq 0) { 'Pad' } else { 'Crop' }
        Assert-TargetAspectRatio $values.Ratio $values.Width $values.Height
        return $values
    }

    function Update-DefaultOutput {
        if ($state.CustomOutput) { return }
        $ui.Output.IsReadOnly = $true
        if ($state.Paths.Count -eq 1) {
            $source = Get-Item -LiteralPath $state.Paths[0]
            $parent = if ($source.PSIsContainer) { $source.FullName } else { $source.DirectoryName }
            $ui.Output.Text = Join-Path $parent 'resize'
        } else { $ui.Output.Text = 'resize (przy kazdym zrodle)' }
    }

    function Get-OriginalBitmap([string]$Path) {
        $image = [Drawing.Image]::FromFile($Path)
        $stream = New-Object IO.MemoryStream
        try {
            Apply-ExifOrientation $image
            $image.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
            $stream.Position = 0
            $bitmap = New-Object Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit(); $bitmap.CacheOption = 'OnLoad'; $bitmap.StreamSource = $stream; $bitmap.EndInit(); $bitmap.Freeze()
            return $bitmap
        } finally { $image.Dispose(); $stream.Dispose() }
    }

    function Update-Preview {
        if ($state.Updating -or $state.Busy) { return }
        $widthValue = 0; $heightValue = 0
        if ([int]::TryParse($ui.WidthBox.Text,[ref]$widthValue) -and [int]::TryParse($ui.HeightBox.Text,[ref]$heightValue)) {
            $long = [Math]::Max($widthValue,$heightValue); $short = [Math]::Min($widthValue,$heightValue)
            $ui.PortraitSize.Text = "$short x $long"
            $ui.LandscapeSize.Text = "$long x $short"
        }
        $ui.PhotoCounter.Text = '{0} / {1}' -f $(if ($state.Photos.Count) { $state.PhotoIndex+1 } else { 0 }),$state.Photos.Count
        $ui.PrevPhoto.IsEnabled = $state.PhotoIndex -gt 0
        $ui.NextPhoto.IsEnabled = $state.PhotoIndex -lt ($state.Photos.Count-1)
        if ($state.Photos.Count -eq 0) {
            $ui.Preview.Source = $null
            $ui.EmptyPreview.Visibility = 'Visible'
            $ui.PhotoName.Text = ''; $ui.PhotoDimensions.Text = ''; $ui.PreviewTitle.Text = 'Podglad'
            return
        }
        $source = $state.Photos[$state.PhotoIndex]
        $temp = Join-Path ([IO.Path]::GetTempPath()) ('resizer-preview-'+[guid]::NewGuid()+'.jpg')
        try {
            $original = Get-OriginalBitmap $source
            $ui.PhotoName.Text = [IO.Path]::GetFileName($source)
            $ui.EmptyPreview.Visibility = 'Collapsed'
            if ($ui.Before.IsChecked) {
                $ui.Preview.Source = $original
                $ui.PreviewTitle.Text = 'Oryginal'
                $ui.PhotoDimensions.Text = '{0} x {1} px' -f $original.PixelWidth,$original.PixelHeight
            } else {
                $options = Get-ExportOptions
                $orientation = if ($original.PixelHeight -gt $original.PixelWidth) { 'Portrait' } else { 'Landscape' }
                $target = Get-TargetSizeForRatio $options.Ratio $options.Width $options.Height $orientation
                $scale = [Math]::Min(1.0,1000.0/[Math]::Max($target.Width,$target.Height))
                Resize-Jpeg $source $temp ([Math]::Max(1,[int]($target.Width*$scale))) ([Math]::Max(1,[int]($target.Height*$scale))) $options.Mode $options.Quality $options.Dpi
                $ui.Preview.Source = New-WpfBitmap $temp
                $ui.PreviewTitle.Text = 'Wynik'
                $ui.PhotoDimensions.Text = '{0} x {1} px | JPG {2} | {3} DPI' -f $target.Width,$target.Height,$options.Quality,$options.Dpi
            }
        } catch {
            $ui.Status.Text = $_.Exception.Message
            $ui.Preview.Source = $null
            $ui.EmptyText.Text = 'Podglad niedostepny'
            $ui.EmptyPreview.Visibility = 'Visible'
        } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
    }

    function Select-PreviewSource {
        if ($state.Updating) { return }
        $state.Photos = @()
        $state.PhotoIndex = 0
        if ($ui.Sources.SelectedIndex -ge 0) {
            $source = [string]$ui.Sources.SelectedItem.FullPath
            if (Test-Path -LiteralPath $source -PathType Leaf) { $state.Photos = @($source) }
            else {
                $state.Photos = @(Get-ChildItem -LiteralPath $source -File -Recurse:([bool]$ui.Recursive.IsChecked) -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -match '^\.(jpg|jpeg)$' -and (Get-RelativePathCompat $source $_.FullName) -notmatch '(^|[\\/])resize[\\/]' } |
                    Sort-Object Name | Select-Object -ExpandProperty FullName)
            }
        }
        $ui.EmptyText.Text = if ($state.Paths.Count) { 'Brak zdjec JPG' } else { 'Brak zdjec' }
        Update-Preview
    }

    function Add-Sources([string[]]$Paths) {
        if ($state.Busy -or $state.Downloading) { return }
        foreach ($path in $Paths) {
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $item = Get-Item -LiteralPath $path
            if (-not $item.PSIsContainer -and $item.Extension -notmatch '^\.(jpg|jpeg)$') { continue }
            $covered = $state.Paths.Contains($item.FullName)
            foreach ($parent in $state.Paths) {
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) { continue }
                if ((-not $item.PSIsContainer -and $item.DirectoryName -eq $parent) -or ($ui.Recursive.IsChecked -and $item.FullName.StartsWith($parent.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase))) { $covered = $true }
            }
            if (-not $covered) {
                $state.Paths.Add($item.FullName)
                $name = if ($item.Name) { $item.Name } else { $item.FullName }
                [void]$ui.Sources.Items.Add([pscustomobject]@{FullPath=$item.FullName;Name=$name;Detail=$(if ($item.PSIsContainer) { 'Folder | '+$item.FullName } else { 'JPG | '+$item.DirectoryName })})
            }
        }
        if ($ui.Sources.Items.Count -gt 0 -and $ui.Sources.SelectedIndex -lt 0) { $ui.Sources.SelectedIndex = 0 }
        $ui.SourceCount.Text = [string]$state.Paths.Count
        Update-DefaultOutput
        Select-PreviewSource
        $ui.Status.Text = if ($state.Paths.Count) { 'Dodane zrodla: '+$state.Paths.Count } else { 'Gotowe do pracy' }
    }
    $ui.AddSources = { param([string[]]$paths) Add-Sources $paths }

    function Set-Presets {
        $wasUpdating = $state.Updating
        $state.Updating = $true
        try {
            $ui.Preset.Items.Clear()
            $sizes = switch (Get-Ratio) {
                '9:16' { @('1080 x 1920','900 x 1600','720 x 1280','1440 x 2560','Wlasny') }
                '16:9' { @('1920 x 1080','1600 x 900','1280 x 720','2560 x 1440','Wlasny') }
                default { @('2880 x 1920','1619 x 1080','1920 x 1080','1280 x 720','Wlasny') }
            }
            foreach ($size in $sizes) { [void]$ui.Preset.Items.Add($size) }
            $ui.Preset.SelectedIndex = 0
            if ($ui.Preset.SelectedItem -match '^(\d+) x (\d+)$') { $ui.WidthBox.Text=$Matches[1]; $ui.HeightBox.Text=$Matches[2] }
        } finally { $state.Updating = $wasUpdating }
        Update-Preview
    }

    $ui.Profile.Add_SelectionChanged({
        if ($state.Updating -or $ui.Profile.SelectedIndex -ne 0) { return }
        $state.Updating = $true
        try {
            $ui.Ratio.SelectedIndex=0; Set-Presets
            $ui.Mode.SelectedIndex=0; $ui.Quality.Value=85; $ui.QualityNumber.Text='85'; $ui.DpiBox.Text='72'
        } finally { $state.Updating = $false }
        Update-Preview
    })
    $ui.Ratio.Add_SelectionChanged({ if (-not $state.Updating) { Set-Custom; Set-Presets } })
    $ui.Preset.Add_SelectionChanged({
        if ($state.Updating) { return }
        Set-Custom
        if ($ui.Preset.SelectedItem -match '^(\d+) x (\d+)$') {
            $state.Updating=$true; $ui.WidthBox.Text=$Matches[1]; $ui.HeightBox.Text=$Matches[2]; $state.Updating=$false
        }
        Update-Preview
    })
    foreach ($box in @($ui.WidthBox,$ui.HeightBox)) {
        $box.Add_LostFocus({ if ($state.Updating) { return }; Set-Custom; $state.Updating=$true; $ui.Preset.SelectedItem='Wlasny'; $state.Updating=$false; Update-Preview })
    }
    $ui.Quality.Add_ValueChanged({ if ($state.Updating) { return }; Set-Custom; $ui.QualityNumber.Text=[string][int]$ui.Quality.Value })
    $ui.Quality.Add_PreviewMouseLeftButtonUp({ Update-Preview })
    $ui.Quality.Add_PreviewKeyUp({ Update-Preview })
    $ui.QualityNumber.Add_LostFocus({
        $value=0
        if ([int]::TryParse($ui.QualityNumber.Text,[ref]$value) -and $value -ge 1 -and $value -le 100) { $ui.Quality.Value=$value; Update-Preview }
        else { $ui.QualityNumber.Text=[string][int]$ui.Quality.Value }
    })
    $ui.DpiBox.Add_LostFocus({ Set-Custom; Update-Preview })
    $ui.Mode.Add_SelectionChanged({ Set-Custom; Update-Preview })
    $ui.Before.Add_Checked({ if ($state.Ready) { Update-Preview } })
    $ui.After.Add_Checked({ if ($state.Ready) { Update-Preview } })
    $ui.PrevPhoto.Add_Click({ if ($state.PhotoIndex -gt 0) { $state.PhotoIndex--; Update-Preview } })
    $ui.NextPhoto.Add_Click({ if ($state.PhotoIndex -lt $state.Photos.Count-1) { $state.PhotoIndex++; Update-Preview } })
    $ui.Sources.Add_SelectionChanged({ Select-PreviewSource })
    $ui.Recursive.Add_Click({ Select-PreviewSource })

    $ui.AddFolder.Add_Click({
        $dialog=New-Object Windows.Forms.FolderBrowserDialog
        try { if ($dialog.ShowDialog() -eq 'OK') { Add-Sources @($dialog.SelectedPath) } } finally { $dialog.Dispose() }
    })
    $ui.AddFiles.Add_Click({
        $dialog=New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Filter='Zdjecia JPG|*.jpg;*.jpeg'; $dialog.Multiselect=$true
        if ($dialog.ShowDialog($window)) { Add-Sources $dialog.FileNames }
    })
    $ui.RemoveSource.Add_Click({
        $selected=@($ui.Sources.SelectedItems)
        $state.Updating=$true
        foreach ($item in $selected) { [void]$state.Paths.Remove($item.FullPath); $ui.Sources.Items.Remove($item) }
        $state.Updating=$false
        if ($ui.Sources.Items.Count) { $ui.Sources.SelectedIndex=0 }
        $ui.SourceCount.Text=[string]$state.Paths.Count; Update-DefaultOutput; Select-PreviewSource
    })
    $ui.ClearSources.Add_Click({
        $state.Updating=$true; $state.Paths.Clear(); $ui.Sources.Items.Clear(); $state.Updating=$false
        $ui.SourceCount.Text='0'; Update-DefaultOutput; Select-PreviewSource; $ui.Status.Text='Gotowe do pracy'
    })
    $ui.ChooseOutput.Add_Click({
        $dialog=New-Object Windows.Forms.FolderBrowserDialog
        try { if ($dialog.ShowDialog() -eq 'OK') { $state.CustomOutput=$true; $ui.Output.IsReadOnly=$false; $ui.Output.Text=$dialog.SelectedPath } } finally { $dialog.Dispose() }
    })
    $ui.DefaultOutput.Add_Click({ $state.CustomOutput=$false; Update-DefaultOutput })
    $ui.BrandLink.Add_Click({ Start-Process $appInfo.website })
    $ui.RepositoryLink.Add_Click({ Start-Process ('https://github.com/'+$appInfo.repository) })
    $ui.LogButton.Add_Click({ $ui.LogOverlay.Visibility='Visible'; $ui.Log.ScrollToEnd() })
    $ui.CloseLog.Add_Click({ $ui.LogOverlay.Visibility='Collapsed' })

    $window.AllowDrop=$true
    $window.Add_PreviewDragOver({
        param($sender,$eventArgs)
        $eventArgs.Effects=[Windows.DragDropEffects]::None
        if (-not $state.Busy -and -not $state.Downloading -and $eventArgs.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) {
            $valid=@($eventArgs.Data.GetData([Windows.DataFormats]::FileDrop) | Where-Object { (Test-Path -LiteralPath $_ -PathType Container) -or ((Test-Path -LiteralPath $_ -PathType Leaf) -and [IO.Path]::GetExtension($_) -match '^\.(jpg|jpeg)$') })
            if ($valid.Count) { $eventArgs.Effects=[Windows.DragDropEffects]::Copy; $ui.DropHighlight.Visibility='Visible' }
        }
        $eventArgs.Handled=$true
    })
    $window.Add_PreviewDragLeave({ $ui.DropHighlight.Visibility='Collapsed' })
    $window.Add_PreviewDrop({
        param($sender,$eventArgs)
        $ui.DropHighlight.Visibility='Collapsed'
        if ($eventArgs.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { Add-Sources @($eventArgs.Data.GetData([Windows.DataFormats]::FileDrop)) }
        $eventArgs.Handled=$true
    })

    $ui.Cancel.Add_Click({ $state.Cancel=$true; $ui.Cancel.IsEnabled=$false; $ui.Status.Text='Zatrzymywanie po biezacym zdjeciu...' })
    $ui.Start.Add_Click({
        if ($state.Busy -or $state.Downloading) { return }
        if ($state.Paths.Count -eq 0) { $ui.Status.Text='Wybierz pliki lub folder'; return }
        try { $options=Get-ExportOptions } catch { $ui.Status.Text=$_.Exception.Message; return }
        $state.Busy=$true; $state.Cancel=$false; $state.Outputs=@()
        foreach ($control in $editables) { $control.IsEnabled=$false }
        $ui.Start.IsEnabled=$false; $ui.Cancel.IsEnabled=$true; $ui.OpenOutput.IsEnabled=$false
        $ui.PrevPhoto.IsEnabled=$false; $ui.NextPhoto.IsEnabled=$false; $ui.Before.IsEnabled=$false; $ui.After.IsEnabled=$false
        $ui.Progress.Value=0; $ui.Log.Clear()
        $doneTotal=0; $failedTotal=0
        $stopwatch=[Diagnostics.Stopwatch]::StartNew()
        $paths=@($state.Paths | Where-Object {
            $candidate=$_
            $covered=$false
            foreach ($parent in $state.Paths) {
                if ($parent -eq $candidate -or -not (Test-Path -LiteralPath $parent -PathType Container)) { continue }
                if (((Test-Path -LiteralPath $candidate -PathType Leaf) -and (Split-Path -Parent $candidate) -eq $parent) -or ($ui.Recursive.IsChecked -and $candidate.StartsWith($parent.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase))) { $covered=$true }
            }
            -not $covered
        })
        try {
            for ($sourceIndex=0;$sourceIndex -lt $paths.Count;$sourceIndex++) {
                if ($state.Cancel) { break }
                $destination=if ($state.CustomOutput) { $ui.Output.Text.Trim() } else { '' }
                $ui.Log.AppendText('Zrodlo: '+$paths[$sourceIndex]+[Environment]::NewLine)
                try {
                    $result=Invoke-BatchResize -SourceFolder $paths[$sourceIndex] -DestinationFolder $destination -Ratio $options.Ratio -ResizeMode $options.Mode -TargetWidth $options.Width -TargetHeight $options.Height -JpegQuality $options.Quality -OutputDpi $options.Dpi -IncludeSubfolders:([bool]$ui.Recursive.IsChecked) -ShouldCancel { $state.Cancel } -OnMessage {
                        param($message) $ui.Log.AppendText($message+[Environment]::NewLine)
                    } -OnProgress {
                        param($done,$total,$name)
                        $ui.Progress.Value=[Math]::Min(1000.0,1000.0*($sourceIndex+$done/[double]$total)/$paths.Count)
                        $ui.Status.Text='Zrodlo {0}/{1} | {2}/{3} | {4}' -f ($sourceIndex+1),$paths.Count,$done,$total,$name
                        Invoke-ResizerUiEvents
                    }
                    $doneTotal+=$result.Done; $failedTotal+=$result.Failed; $state.Outputs+=$result.OutputFolder
                } catch { $failedTotal++; $ui.Log.AppendText('BLAD: '+$_.Exception.Message+[Environment]::NewLine) }
            }
            if (-not $state.Cancel) { $ui.Progress.Value=1000 }
            $prefix=if ($state.Cancel) { 'Zatrzymano' } else { 'Gotowe' }
            $ui.Status.Text='{0} | zapisano: {1} | bledy: {2} | {3:N1} s' -f $prefix,$doneTotal,$failedTotal,$stopwatch.Elapsed.TotalSeconds
            if ($failedTotal) { $ui.LogOverlay.Visibility='Visible' }
        } finally {
            $stopwatch.Stop(); $state.Busy=$false
            foreach ($control in $editables) { $control.IsEnabled=$true }
            $ui.Start.IsEnabled=$true; $ui.Cancel.IsEnabled=$false; $ui.OpenOutput.IsEnabled=$state.Outputs.Count -gt 0
            $ui.Before.IsEnabled=$true; $ui.After.IsEnabled=$true
            $ui.PrevPhoto.IsEnabled=$state.PhotoIndex -gt 0; $ui.NextPhoto.IsEnabled=$state.PhotoIndex -lt $state.Photos.Count-1
        }
    })
    $ui.OpenOutput.Add_Click({ foreach ($path in @($state.Outputs | Select-Object -Unique)) { if (Test-Path -LiteralPath $path -PathType Container) { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $path) } } })

    function Start-UpdateTask([string]$Kind,[scriptblock]$Completed) {
        if ($state.NetworkBusy) { return }
        $state.NetworkBusy=$true
        $state.Downloading=$Kind -eq 'Download'
        $ui.CheckUpdate.IsEnabled=$false; $ui.InstallUpdate.IsEnabled=$false
        $ui.UpdateProgress.Visibility='Visible'
        if ($Kind -eq 'Download') { $ui.Start.IsEnabled=$false; $ui.UpdateStatus.Text='Pobieranie i sprawdzanie paczki...' }
        else { $ui.UpdateStatus.Text='Sprawdzanie GitHub Releases...' }
        $ps=[PowerShell]::Create()
        [void]$ps.AddScript('param($root,$kind,$candidate) $ErrorActionPreference="Stop"; . (Join-Path $root "ResizerUpdates.ps1"); if ($kind -eq "Check") { Get-ResizerRelease -Metadata (Get-ResizerAppInfo -Directory $root) } else { Save-ResizerUpdate -Candidate $candidate }').AddArgument($PSScriptRoot).AddArgument($Kind).AddArgument($state.Candidate)
        $handle=$ps.BeginInvoke()
        $state.Tasks.Add([pscustomobject]@{PowerShell=$ps;Handle=$handle;Completed=$Completed})
    }

    $networkTimer=New-Object Windows.Threading.DispatcherTimer
    $networkTimer.Interval=[TimeSpan]::FromMilliseconds(160)
    $networkTimer.Add_Tick({
        foreach ($task in $state.Tasks.ToArray()) {
            if (-not $task.Handle.IsCompleted) { continue }
            [void]$state.Tasks.Remove($task)
            $state.NetworkBusy=$false
            $state.Downloading=$false
            $ui.UpdateProgress.Visibility='Collapsed'; $ui.CheckUpdate.IsEnabled=$true
            $ui.Start.IsEnabled=-not $state.Busy
            try {
                $result=$task.PowerShell.EndInvoke($task.Handle)
                if ($task.PowerShell.Streams.Error.Count) { throw $task.PowerShell.Streams.Error[0].ToString() }
                & $task.Completed $result[0]
            } catch { $state.Installing=$false; $ui.UpdateStatus.Text=$_.Exception.Message; $ui.InstallUpdate.IsEnabled=$false }
            finally { $task.PowerShell.Dispose() }
        }
    })
    $networkTimer.Start()

    $checkCompleted={
        param($candidate)
        $state.Candidate=$candidate
        if ($candidate.Available) {
            $ui.UpdateStatus.Text='Dostepna wersja {0} ({1:N1} MB).' -f $candidate.Version,($candidate.Size/1MB)
            $ui.InstallUpdate.IsEnabled=$true
            $ui.UpdatesCaption.Text='Nowa wersja '+$candidate.Version
        } elseif ($candidate.Status -eq 'NoRelease') { $ui.UpdateStatus.Text='Repozytorium nie ma jeszcze opublikowanych wydan.' }
        else { $ui.UpdateStatus.Text='Masz aktualna wersje programu.' }
    }
    $ui.UpdatesButton.Add_Click({ $ui.UpdateOverlay.Visibility='Visible' })
    $ui.CloseUpdates.Add_Click({ if (-not $state.Installing) { $ui.UpdateOverlay.Visibility='Collapsed' } })
    $ui.CheckUpdate.Add_Click({ Start-UpdateTask 'Check' $checkCompleted })
    $ui.InstallUpdate.Add_Click({
        if ($state.Busy -or $state.NetworkBusy -or $null -eq $state.Candidate -or -not $state.Candidate.Available) { return }
        $state.Installing=$true
        Start-UpdateTask 'Download' {
            param($stage)
            $ui.UpdateStatus.Text='Instalowanie aktualizacji...'
            $installer=Join-Path $stage 'Install-Update.ps1'
            $psPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $command='"{0}" -Sta -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" -AppDirectory "{2}" -StageDirectory "{3}" -ExpectedVersion "{4}" -ParentProcessId {5}' -f $psPath,$installer,$PSScriptRoot,$stage,$state.Candidate.Version,$PID
            $shell=New-Object -ComObject WScript.Shell
            [void]$shell.Run($command,0,$false)
            $state.Installing=$false
            $window.Close()
        }
    })
    $ui.AutoUpdate.Add_Click({
        [void](New-Item -ItemType Directory -Path $configDirectory -Force)
        [IO.File]::WriteAllText($configFile,(@{CheckOnStartup=[bool]$ui.AutoUpdate.IsChecked}|ConvertTo-Json))
    })
    $window.Add_Closing({
        param($sender,$eventArgs)
        if ($state.Busy) { $state.Cancel=$true; $eventArgs.Cancel=$true; $ui.Status.Text='Zatrzymywanie po biezacym zdjeciu...' }
        elseif ($state.Installing -and $state.NetworkBusy) { $eventArgs.Cancel=$true; $ui.UpdateStatus.Text='Poczekaj na zakonczenie pobierania.' }
    })
    $window.Add_ContentRendered({
        if ($null -ne $OnShown) { & $OnShown $window }
        elseif ($ui.AutoUpdate.IsChecked) { Start-UpdateTask 'Check' $checkCompleted }
    })

    Set-Presets
    $state.Ready=$true
    Add-Sources $InitialFolders
    $area=[Windows.SystemParameters]::WorkArea
    $window.Width=[Math]::Min(1240.0,$area.Width-40)
    $window.Height=[Math]::Min(840.0,$area.Height-40)
    try { [void]$window.ShowDialog() } finally {
        $networkTimer.Stop()
        foreach ($task in $state.Tasks.ToArray()) { [void]$task.PowerShell.BeginStop($null,$null) }
    }
}
