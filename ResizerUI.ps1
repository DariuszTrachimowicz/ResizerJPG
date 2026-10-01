. (Join-Path $PSScriptRoot 'ResizerUpdates.ps1')
# Portable builds prepend these modules to retain the 2.0 package allowlist.
foreach ($module in @('ResizerUIModels.ps1','ResizerQueue.ps1')) {
    $modulePath = Join-Path $PSScriptRoot $module
    if (Test-Path -LiteralPath $modulePath) { . $modulePath }
}

function Invoke-ResizerUiEvents {
    $frame = New-Object Windows.Threading.DispatcherFrame
    [void][Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{ $frame.Continue = $false })
    [Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Show-ResizerWindow {
    param([string[]]$InitialFolders = @(), [scriptblock]$OnShown)
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
    $root=$PSScriptRoot
    $appInfo=Get-ResizerAppInfo
    [xml]$xaml=Get-Content -LiteralPath (Join-Path $root 'ResizerWindow.xaml') -Raw
    $reader=New-Object Xml.XmlNodeReader($xaml)
    try { $window=[Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
    $ui=@{}
    foreach ($node in $xaml.SelectNodes('//*')) {
        $name=$node.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')
        if ($name) { $ui[$name]=$window.FindName($name) }
    }
    $ui.Start=$ui.StartButton
    $window.Tag=$ui
    $window.Title='Resizer JPG '+$appInfo.version+' | Digital Xperts'
    $ui.VersionFooter.Text='Wersja '+$appInfo.version
    $ui.InstalledVersion.Text='Wersja zainstalowana: '+$appInfo.version
    $ui.RepositoryLink.Content=$appInfo.repository
    $photos=New-Object 'Collections.ObjectModel.ObservableCollection[ResizerPhoto]'
    $view=[Windows.Data.ListCollectionView]::new($photos)
    [void]$view.GroupDescriptions.Add([Windows.Data.PropertyGroupDescription]::new('SourceRoot'))
    $ui.Sources.ItemsSource=$view; $ui.Filmstrip.ItemsSource=$photos
    $state=@{
        Busy=$false; Scanning=$false; PreviewBusy=$false; Updating=$false; Closed=$false; Ready=$false
        Downloading=$false; Installing=$false; NetworkBusy=$false; CloseRequested=$false; Cancelling=$false; InvalidControl=$null
        Paths=(New-Object 'Collections.Generic.List[string]'); QueueItems=$photos; ItemByPath=@{}
        Inclusion=@{}; Removed=@{}; Outputs=@(); CustomOutput=$false; Candidate=$null
        Tasks=(New-Object 'Collections.Generic.List[object]'); NetworkTasks=(New-Object 'Collections.Generic.List[object]')
        ScanSequence=0; PreviewSequence=0; PreviewRequest=$null; PendingSelection=''; ExportWatch=$null; DimensionKey=''
    }
    $ui.State=$state; $ui.QueueItems=$photos
    function T([string]$Text) { return [Text.RegularExpressions.Regex]::Unescape($Text) }
    function Photo-Word([int]$Count) {
        if ($Count -eq 1) { return (T 'zdj\u0119cie') }
        if ($Count % 10 -in @(2,3,4) -and $Count % 100 -notin @(12,13,14)) { return (T 'zdj\u0119cia') }
        return (T 'zdj\u0119\u0107')
    }
    function Announce-Status {
        $peer=[Windows.Automation.Peers.UIElementAutomationPeer]::FromElement($ui.Status)
        if ($null -eq $peer) { $peer=[Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($ui.Status) }
        if ($null -ne $peer) { $peer.RaiseAutomationEvent([Windows.Automation.Peers.AutomationEvents]::LiveRegionChanged) }
    }
    function Bitmap-Bytes([byte[]]$Bytes) {
        if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return $null }
        $stream=[IO.MemoryStream]::new($Bytes)
        try {
            $bitmap=New-Object Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit(); $bitmap.CacheOption='OnLoad'; $bitmap.StreamSource=$stream; $bitmap.EndInit(); $bitmap.Freeze()
            return $bitmap
        } finally { $stream.Dispose() }
    }
    function Bitmap-File([string]$Path) { return (Bitmap-Bytes ([IO.File]::ReadAllBytes($Path))) }
    $ui.BrandLogo.Source=Bitmap-File (Join-Path $root 'digital-xperts-logo.png')
    $window.Icon=Bitmap-File (Join-Path $root 'resizer-jpg.ico')
    $icons=Get-Content -LiteralPath (Join-Path $root 'lucide-paths.json') -Raw | ConvertFrom-Json
    $iconMap=@{
        FolderPlusIcon='folder-plus'; ImagesIcon='images'; TrashIcon='trash-2'; PrevIcon='chevron-left'; NextIcon='chevron-right'
        EmptyImageIcon='image'; OutputFolderIcon='folder-open'; ResetIcon='refresh-cw'; PlayIcon='play'; StopIcon='square'
        UpdatesIcon='refresh-cw'; CloseUpdatesIcon='x'; CloseLogIcon='x'; SettingsIcon='settings-2'
        ZoomInIcon='zoom-in'; ZoomOutIcon='zoom-out'; FitIcon='scan'; PadIcon='scan'; CropIcon='crop'
    }
    foreach ($key in $iconMap.Keys) {
        if (-not $ui.ContainsKey($key)) { continue }
        $geometry=$icons.PSObject.Properties[$iconMap[$key]]
        if ($null -eq $geometry) { throw "Brak ikony: $($iconMap[$key])" }
        $canvas=New-Object Windows.Controls.Canvas; $canvas.Width=24; $canvas.Height=24
        $path=New-Object Windows.Shapes.Path; $path.Data=[Windows.Media.Geometry]::Parse([string]$geometry.Value)
        $path.StrokeThickness=1.7; $path.StrokeStartLineCap='Round'; $path.StrokeEndLineCap='Round'; $path.StrokeLineJoin='Round'
        $binding=[Windows.Data.Binding]::new('Foreground'); $binding.Source=$ui[$key]
        [void]$path.SetBinding([Windows.Shapes.Shape]::StrokeProperty,$binding)
        [void]$canvas.Children.Add($path)
        $box=New-Object Windows.Controls.Viewbox; $box.Child=$canvas; $ui[$key].Content=$box
    }
    $configDirectory=Join-Path $env:LOCALAPPDATA 'DigitalXperts\ResizerJPG'
    $configFile=Join-Path $configDirectory 'settings.json'
    if (Test-Path -LiteralPath $configFile) {
        try { $settings=Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json; $ui.AutoUpdate.IsChecked=[bool]$settings.CheckOnStartup } catch { }
    }

    function Get-ExportOptions {
        $state.InvalidControl=$null
        $options=@{}
        foreach ($entry in @(@('Width',$ui.WidthBox,20000),@('Height',$ui.HeightBox,20000),@('Dpi',$ui.DpiBox,600),@('Quality',$ui.QualityNumber,100))) {
            $number=0
            if (-not [int]::TryParse($entry[1].Text,[ref]$number) -or $number -lt 1 -or $number -gt $entry[2]) { $state.InvalidControl=$entry[1]; throw ('Niepoprawna wartosc: {0} (1-{1}).' -f $entry[0],$entry[2]) }
            $options[$entry[0]]=$number
        }
        $options.Ratio=[string]$ui.Ratio.SelectedItem.Tag
        $options.Mode=if ($ui.Mode.SelectedIndex -eq 0) { 'Pad' } else { 'Crop' }
        try { Assert-TargetAspectRatio $options.Ratio $options.Width $options.Height } catch { $state.InvalidControl=$ui.WidthBox; throw }
        return $options
    }
    function Set-ControlState {
        $editable=-not ($state.Busy -or $state.Downloading -or $state.Installing)
        foreach ($control in @($ui.Settings,$ui.Sources,$ui.Filmstrip,$ui.AddFolder,$ui.AddFiles,$ui.RemoveSource,$ui.ClearSources,$ui.Recursive,$ui.SelectAll,$ui.ChooseOutput,$ui.DefaultOutput,$ui.Before,$ui.After)) { $control.IsEnabled=$editable }
        $included=@($photos | Where-Object IsIncluded)
        $ui.Start.IsEnabled=$editable -and -not $state.Scanning -and $included.Count -gt 0
        $ui.Cancel.Visibility=if ($state.Busy -or $state.Scanning) { 'Visible' } else { 'Collapsed' }
        $ui.Cancel.IsEnabled=($state.Busy -or $state.Scanning) -and -not ($state.Downloading -or $state.Cancelling)
        $ui.OpenOutput.IsEnabled=$state.Outputs.Count -gt 0 -and -not $state.Busy
        $ui.InstallUpdate.IsEnabled=-not ($state.Busy -or $state.Scanning -or $state.NetworkBusy) -and $null -ne $state.Candidate -and $state.Candidate.Available
        $ui.PrevPhoto.IsEnabled=$editable -and $ui.Sources.SelectedIndex -gt 0
        $ui.NextPhoto.IsEnabled=$editable -and $ui.Sources.SelectedIndex -ge 0 -and $ui.Sources.SelectedIndex -lt ($photos.Count-1)
    }
    function Update-Output {
        if (-not $state.CustomOutput) { $ui.Output.Text=T 'resize przy ka\u017cdym folderze' }
        $ui.Output.IsReadOnly=$true
        $selected=$ui.Sources.SelectedItem
        $ui.OutputExample.Text=''; $ui.OutputFilename.Text=''
        if ($null -eq $selected) { return }
        try {
            $destination=if ($state.CustomOutput) { $ui.Output.Text.Trim() } else { '' }
            $candidate=Get-ResizerQueueTargetPath -Item $selected -DestinationFolder $destination
            if ($selected.LastOutputPath) { $candidate=$selected.LastOutputPath }
            $ui.OutputExample.Text=$candidate; $ui.OutputExample.ToolTip=$candidate
            $ui.OutputFilename.Text=[IO.Path]::GetFileName($candidate)
        } catch { $ui.OutputExample.Text=$_.Exception.Message }
    }
    function Update-Counts {
        if ($state.Closed) { return }
        $included=@($photos | Where-Object IsIncluded).Count
        $groups=@($photos | Select-Object -ExpandProperty SourceRoot -Unique).Count
        $ui.SourceCount.Text='{0} {1} {2} {3} {4}' -f $photos.Count,(Photo-Word $photos.Count),[char]0x2022,$groups,$(if ($groups -eq 1) { 'folder' } else { 'foldery' })
        $ui.SelectionCount.Text=T ('{0} z {1} zdj\u0119\u0107' -f $included,$photos.Count)
        $ui.StartCaption.Text='Eksportuj {0} {1}' -f $included,(Photo-Word $included)
        [Windows.Automation.AutomationProperties]::SetName($ui.Start,$ui.StartCaption.Text)
        $wasUpdating=$state.Updating; $state.Updating=$true
        try { $ui.SelectAll.IsChecked=if ($photos.Count -eq 0 -or $included -eq 0) { $false } elseif ($included -eq $photos.Count) { $true } else { $null } } finally { $state.Updating=$wasUpdating }
        $ui.PhotoCounter.Text='{0} / {1}' -f $(if ($ui.Sources.SelectedIndex -ge 0) { $ui.Sources.SelectedIndex+1 } else { 0 }),$photos.Count
        Set-ControlState
    }
    function Update-Zoom {
        if ($null -eq $ui.Preview.Source) { return }
        # The parent has the new size before ScrollViewer updates its old viewport.
        $width=[Math]::Max(1,$ui.PreviewSurface.ActualWidth-40)
        $height=[Math]::Max(1,$ui.PreviewSurface.ActualHeight-40)
        $fit=[Math]::Min($width/$ui.Preview.Source.PixelWidth,$height/$ui.Preview.Source.PixelHeight)
        $scale=$fit*$ui.Zoom.Value/100.0
        $ui.Preview.Width=[Math]::Max(1,$ui.Preview.Source.PixelWidth*$scale)
        $ui.Preview.Height=[Math]::Max(1,$ui.Preview.Source.PixelHeight*$scale)
        $ui.ZoomCaption.Text=if ($ui.Zoom.Value -eq 100) { 'Dopasuj' } else { '{0}%' -f [int]$ui.Zoom.Value }
    }

    # Workers communicate plain data; only the dispatcher touches WPF.
    $workerCode=@'
param($root,$kind,$data,$control,$events)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ResizerJPG.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($statement in $ast.EndBlock.Statements) { if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) { . ([scriptblock]::Create($statement.Extent.Text)) } }
$queueFile=Join-Path $root 'ResizerQueue.ps1'
if (Test-Path -LiteralPath $queueFile) { . $queueFile } else {
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ResizerUI.ps1'),[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    foreach ($statement in $ast.EndBlock.Statements) { if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) { . ([scriptblock]::Create($statement.Extent.Text)) } }
}
switch ($kind) {
    'Scan' {
        $items=@(Get-ResizerQueueItems -Paths $data.Paths -IncludeSubfolders:([bool]$data.Recursive) -ExcludedFolder $data.ExcludedFolder -ShouldCancel { $control.Cancel } -OnItem {
            param($item) $events.Enqueue([pscustomobject]@{Kind='Item';Item=$item})
        } -OnProgress { param($count,$name) $events.Enqueue([pscustomobject]@{Kind='ScanProgress';Count=$count;Name=$name}) })
        [pscustomobject]@{Count=$items.Count;Cancelled=[bool]$control.Cancel}
    }
    'Preview' { Get-ResizerPreviewData -Path $data.Path -Options $data.Options -Original:([bool]$data.Original) }
    'Export' {
        Invoke-ResizerQueueExport -Items $data.Items -DestinationFolder $data.Destination -Ratio $data.Options.Ratio -ResizeMode $data.Options.Mode -TargetWidth $data.Options.Width -TargetHeight $data.Options.Height -JpegQuality $data.Options.Quality -OutputDpi $data.Options.Dpi -ShouldCancel { $control.Cancel } -OnMessage {
            param($message) $events.Enqueue([pscustomobject]@{Kind='Log';Text=$message})
        } -OnProgress {
            param($done,$total,$item,$success,$outputPath,$errorMessage)
            $events.Enqueue([pscustomobject]@{Kind='ExportProgress';Done=$done;Total=$total;FullPath=$item.FullPath;Success=$success;OutputPath=$outputPath;Error=$errorMessage})
        }
    }
}
'@
    function Start-Work([string]$Kind,$Data,[int]$Token) {
        $ps=[PowerShell]::Create()
        $control=[hashtable]::Synchronized(@{Cancel=$false})
        $events=New-Object 'Collections.Concurrent.ConcurrentQueue[object]'
        [void]$ps.AddScript($workerCode).AddArgument($root).AddArgument($Kind).AddArgument($Data).AddArgument($control).AddArgument($events)
        $task=[pscustomobject]@{Kind=$Kind;Data=$Data;Token=$Token;PowerShell=$ps;Control=$control;Events=$events;Handle=$ps.BeginInvoke()}
        $state.Tasks.Add($task)
    }
    function Request-Preview {
        if ($state.Updating -or $state.Closed) { return }
        $state.PreviewSequence++
        $selected=$ui.Sources.SelectedItem; $state.PreviewRequest=$null
        if ($null -eq $selected) {
            $state.PreviewBusy=$false; $ui.Preview.Source=$null; $ui.EmptyPreview.Visibility='Visible'
            $ui.EmptyText.Text=if ($state.Scanning) { 'Skanowanie...' } else { T 'Brak zdj\u0119\u0107' }
            $ui.PhotoName.Text=''; $ui.PhotoDimensions.Text=''; $ui.PreviewTitle.Text='Podglad'
            if ($ui.ContainsKey('SourcePath')) { $ui.SourcePath.Text='' }
            Update-Output; Update-Counts; return
        }
        $ui.PhotoName.Text=$selected.Name; $ui.PhotoName.ToolTip=$selected.FullPath
        $ui.SourcePath.Text=$selected.FullPath
        [Windows.Automation.AutomationProperties]::SetHelpText($ui.PhotoName,$selected.FullPath)
        $ui.PreviewTitle.Text=if ($selected.Orientation -eq 'Portrait') { 'Pion' } else { 'Poziom' }
        try {
            $options=Get-ExportOptions
            $long=[Math]::Max($options.Width,$options.Height); $short=[Math]::Min($options.Width,$options.Height)
            $ui.PortraitSize.Text="$short x $long px"; $ui.LandscapeSize.Text="$long x $short px"
            $key='{0}|{1}|{2}' -f $options.Ratio,$options.Width,$options.Height
            if ($state.DimensionKey -ne $key) {
                foreach ($photo in $photos) { Set-PhotoDetails $photo $options }
                $state.DimensionKey=$key
            }
            $state.PreviewRequest=@{Path=$selected.FullPath;Options=$options;Original=[bool]$ui.Before.IsChecked;Token=$state.PreviewSequence}
            $state.PreviewBusy=$true; $previewTimer.Stop(); $previewTimer.Start()
        } catch { $state.PreviewBusy=$false; $ui.Status.Text=$_.Exception.Message }
        Update-Output; Update-Counts
    }
    function Set-PhotoDetails($Photo,$Options) {
        if ($Photo.Error) { $Photo.Details=T 'B\u0142\u0105d odczytu'; return }
        $target=Get-TargetSizeForRatio $Options.Ratio $Options.Width $Options.Height $Photo.Orientation
        $Photo.Details='{0} x {1} px | {2}' -f $target.Width,$target.Height,$(if ($Photo.Orientation -eq 'Portrait') { 'Pion' } else { 'Poziom' })
    }
    function Add-QueueItem($Item) {
        if ($state.Removed.ContainsKey($Item.FullPath) -or $state.ItemByPath.ContainsKey($Item.FullPath)) { return }
        $photo=New-Object ResizerPhoto
        foreach ($property in @('FullPath','SourceRoot','SourcePath','SourceName','RelativePath','Name','Orientation','Error')) { $photo.$property=[string]$Item.$property }
        $photo.OriginalWidth=$Item.Width; $photo.OriginalHeight=$Item.Height
        try { Set-PhotoDetails $photo (Get-ExportOptions) } catch { $photo.Details='{0} x {1} px' -f $Item.Width,$Item.Height }
        $photo.Thumbnail=Bitmap-Bytes $Item.ThumbnailBytes
        if ($state.Inclusion.ContainsKey($photo.FullPath)) { $photo.IsIncluded=$state.Inclusion[$photo.FullPath] }
        $photo.add_PropertyChanged({
            param($sender,$eventArgs)
            if ($state.Closed) { return }
            if ($eventArgs.PropertyName -eq 'IsIncluded') { $state.Inclusion[$sender.FullPath]=$sender.IsIncluded; if (-not $state.Updating) { Update-Counts } }
        })
        $state.ItemByPath[$photo.FullPath]=$photo; $photos.Add($photo)
        if ($ui.Sources.SelectedIndex -lt 0 -or $photo.FullPath -eq $state.PendingSelection) { $ui.Sources.SelectedItem=$photo }
    }
    function Start-Scan {
        if ($state.Busy -or $state.Downloading -or $state.Closed) { return }
        foreach ($task in $state.Tasks.ToArray()) { if ($task.Kind -eq 'Scan') { $task.Control.Cancel=$true } }
        $state.ScanSequence++; $state.Scanning=$true; $state.Cancelling=$false
        $state.PendingSelection=if ($null -ne $ui.Sources.SelectedItem) { $ui.Sources.SelectedItem.FullPath } else { '' }
        foreach ($photo in $photos) { $state.Inclusion[$photo.FullPath]=$photo.IsIncluded }
        $state.Updating=$true; $photos.Clear(); $state.ItemByPath.Clear(); $state.Updating=$false
        $ui.Status.Text=T 'Skanowanie zdj\u0119\u0107...'; $ui.Progress.IsIndeterminate=$true
        Start-Work 'Scan' @{Paths=$state.Paths.ToArray();Recursive=[bool]$ui.Recursive.IsChecked;ExcludedFolder=$(if ($state.CustomOutput) { $ui.Output.Text.Trim() } else { '' })} $state.ScanSequence
        Update-Counts
    }
    function Add-Sources([string[]]$Paths) {
        if ($state.Busy -or $state.Downloading) { return }
        $changed=$false
        foreach ($path in $Paths) {
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $item=Get-Item -LiteralPath $path
            if (-not $item.PSIsContainer -and $item.Extension -notmatch '^\.(jpg|jpeg)$') { continue }
            foreach ($removedPath in @($state.Removed.Keys)) {
                if ($removedPath -eq $item.FullName -or ($item.PSIsContainer -and (Test-ResizerQueueDescendant -Path $removedPath -Folder $item.FullName))) {
                    $state.Removed.Remove($removedPath); $changed=$true
                }
            }
            if ($item.FullName -notin $state.Paths) { $state.Paths.Add($item.FullName); $changed=$true }
        }
        if ($changed) { Start-Scan }
    }
    $ui.AddSources={ param([string[]]$paths) Add-Sources $paths }

    $previewTimer=New-Object Windows.Threading.DispatcherTimer
    $previewTimer.Interval=[TimeSpan]::FromMilliseconds(120)
    $previewTimer.Add_Tick({
        $previewTimer.Stop()
        if ($null -eq $state.PreviewRequest -or $state.Closed) { return }
        if (@($state.Tasks | Where-Object Kind -eq 'Preview').Count) { return }
        $request=$state.PreviewRequest; $state.PreviewRequest=$null
        Start-Work 'Preview' $request $request.Token
    })
    $workTimer=New-Object Windows.Threading.DispatcherTimer
    $workTimer.Interval=[TimeSpan]::FromMilliseconds(40)
    $workTimer.Add_Tick({
        foreach ($task in $state.Tasks.ToArray()) {
            $budget=[Diagnostics.Stopwatch]::StartNew(); $message=$null; $handled=0
            while ($handled -lt 64 -and $budget.ElapsedMilliseconds -lt 12 -and $task.Events.TryDequeue([ref]$message)) {
                $handled++
                if ($task.Kind -eq 'Scan' -and $task.Token -ne $state.ScanSequence) { continue }
                switch ($message.Kind) {
                    'Item' { Add-QueueItem $message.Item }
                    'ScanProgress' { if ($state.Scanning -and -not $state.Cancelling) { $ui.Status.Text=T ('Skanowanie: {0} zdj\u0119\u0107 | {1}' -f $message.Count,$message.Name) } }
                    'Log' { $ui.Log.AppendText($message.Text+[Environment]::NewLine) }
                    'ExportProgress' {
                        if ($message.Total -gt 0) { $ui.Progress.Value=1000.0*$message.Done/$message.Total }
                        if (-not $state.Cancelling) { $ui.Status.Text='Eksport {0}/{1} | {2}' -f $message.Done,$message.Total,[IO.Path]::GetFileName($message.FullPath) }
                        if ($state.ItemByPath.ContainsKey($message.FullPath)) {
                            $photo=$state.ItemByPath[$message.FullPath]
                            $photo.Status=if ($message.Success) { 'Zapisano' } else { T 'B\u0142\u0105d' }
                            if ($message.OutputPath) { $photo.LastOutputPath=$message.OutputPath }
                        }
                    }
                }
            }
            if ($handled -gt 0 -and $task.Kind -eq 'Scan' -and $task.Token -eq $state.ScanSequence) { Update-Counts }
            if (-not $task.Handle.IsCompleted -or -not $task.Events.IsEmpty) { continue }
            [void]$state.Tasks.Remove($task)
            try {
                $result=$task.PowerShell.EndInvoke($task.Handle)
                if ($task.PowerShell.Streams.Error.Count) { throw $task.PowerShell.Streams.Error[0].ToString() }
                switch ($task.Kind) {
                    'Scan' {
                        if ($task.Token -ne $state.ScanSequence) { break }
                        $state.Scanning=$false; $state.Cancelling=$false; $ui.Progress.IsIndeterminate=$false; $ui.Progress.Value=0
                        $ui.Status.Text=if ($task.Control.Cancel) { 'Skanowanie zatrzymane' } elseif ($photos.Count) { T ('Gotowe do eksportu: {0} zdj\u0119\u0107' -f $photos.Count) } else { T 'Brak zdj\u0119\u0107 JPG w dodanych folderach' }
                        if ($ui.Sources.SelectedIndex -lt 0) { Request-Preview }
                        Update-Counts; Announce-Status
                    }
                    'Preview' {
                        if ($task.Token -ne $state.PreviewSequence) { break }
                        $data=$result[0]
                        $ui.Preview.Source=Bitmap-Bytes $data.Bytes; $ui.EmptyPreview.Visibility='Collapsed'
                        $ui.PhotoDimensions.Text=if ($task.Data.Original) { '{0} x {1} px | Oryginal' -f $data.SourceWidth,$data.SourceHeight } else { '{0} x {1} px | JPG {2} | {3} DPI' -f $data.TargetWidth,$data.TargetHeight,$task.Data.Options.Quality,$task.Data.Options.Dpi }
                        $state.PreviewBusy=$false; Update-Zoom
                    }
                    'Export' {
                        $data=$result[0]; $state.Busy=$false; $state.Cancelling=$false; $state.Outputs=@($data.OutputFolders)
                        $state.ExportWatch.Stop(); $ui.Progress.Value=if ($data.Cancelled) { $ui.Progress.Value } else { 1000 }
                        $prefix=if ($data.Cancelled) { 'Zatrzymano' } else { 'Gotowe' }
                        $ui.Status.Text='{0} | zapisano: {1} | bledy: {2} | {3:N1} s' -f $prefix,$data.Done,$data.Failed,$state.ExportWatch.Elapsed.TotalSeconds
                        if ($data.Failed) { Open-Overlay 'Log' }
                        Update-Output; Update-Counts; Announce-Status
                    }
                }
            } catch {
                if ($task.Kind -eq 'Scan' -and $task.Token -eq $state.ScanSequence) { $state.Scanning=$false; $state.Cancelling=$false; $ui.Progress.IsIndeterminate=$false }
                if ($task.Kind -eq 'Preview' -and $task.Token -eq $state.PreviewSequence) { $state.PreviewBusy=$false; $ui.EmptyText.Text=T 'Podgl\u0105d niedost\u0119pny'; $ui.EmptyPreview.Visibility='Visible'; $ui.Preview.Source=$null }
                if ($task.Kind -eq 'Export') { $state.Busy=$false; $state.Cancelling=$false; $state.ExportWatch.Stop() }
                if (($task.Kind -ne 'Preview' -or $task.Token -eq $state.PreviewSequence) -and ($task.Kind -ne 'Scan' -or $task.Token -eq $state.ScanSequence)) { $ui.Status.Text=$_.Exception.Message; Announce-Status }
                Set-ControlState
            } finally { $task.PowerShell.Dispose() }
            if ($task.Kind -eq 'Preview' -and $null -ne $state.PreviewRequest) { $previewTimer.Start() }
        }
        if ($state.CloseRequested -and -not $state.Busy -and -not $state.Scanning) { $window.Close() }
    })
    $workTimer.Start()

    function Set-Custom { if (-not $state.Updating) { $ui.Profile.SelectedIndex=1 } }
    function Set-Presets {
        $wasUpdating=$state.Updating; $state.Updating=$true
        try {
            $ui.Preset.Items.Clear()
            $sizes=switch ([string]$ui.Ratio.SelectedItem.Tag) {
                '9:16' { @('1080 x 1920','900 x 1600','720 x 1280','1440 x 2560','Wlasny') }
                '16:9' { @('1920 x 1080','1600 x 900','1280 x 720','2560 x 1440','Wlasny') }
                default { @('2880 x 1920','1619 x 1080','1920 x 1080','1280 x 720','Wlasny') }
            }
            foreach ($size in $sizes) { [void]$ui.Preset.Items.Add($size) }
            $ui.Preset.SelectedIndex=0
            if ($ui.Preset.SelectedItem -match '^(\d+) x (\d+)$') { $ui.WidthBox.Text=$Matches[1]; $ui.HeightBox.Text=$Matches[2] }
        } finally { $state.Updating=$wasUpdating }
    }
    $ui.Profile.Add_SelectionChanged({
        if ($state.Updating -or $ui.Profile.SelectedIndex -ne 0) { return }
        $state.Updating=$true
        try { $ui.Ratio.SelectedIndex=0; Set-Presets; $ui.Mode.SelectedIndex=0; $ui.FitPad.IsChecked=$true; $ui.Quality.Value=85; $ui.QualityNumber.Text='85'; $ui.DpiBox.Text='72' } finally { $state.Updating=$false }
        Request-Preview
    })
    $ui.Ratio.Add_SelectionChanged({ if (-not $state.Updating) { Set-Custom; Set-Presets; Request-Preview } })
    $ui.Preset.Add_SelectionChanged({
        if ($state.Updating) { return }
        Set-Custom
        if ($ui.Preset.SelectedItem -match '^(\d+) x (\d+)$') { $state.Updating=$true; $ui.WidthBox.Text=$Matches[1]; $ui.HeightBox.Text=$Matches[2]; $state.Updating=$false }
        Request-Preview
    })
    foreach ($box in @($ui.WidthBox,$ui.HeightBox)) {
        $box.Add_LostFocus({ if ($state.Updating) { return }; Set-Custom; $state.Updating=$true; $ui.Preset.SelectedItem='Wlasny'; $state.Updating=$false; Request-Preview })
    }
    $ui.Quality.Add_ValueChanged({ if ($state.Updating) { return }; Set-Custom; $ui.QualityNumber.Text=[string][int]$ui.Quality.Value; Request-Preview })
    $ui.QualityNumber.Add_LostFocus({
        $value=0
        if ([int]::TryParse($ui.QualityNumber.Text,[ref]$value) -and $value -ge 1 -and $value -le 100) { $ui.Quality.Value=$value; Request-Preview }
        else { $ui.QualityNumber.Text=[string][int]$ui.Quality.Value }
    })
    $ui.DpiBox.Add_LostFocus({ Set-Custom; Request-Preview })
    $ui.FitPad.Add_Checked({ if (-not $state.Updating) { $ui.Mode.SelectedIndex=0 } })
    $ui.FitCrop.Add_Checked({ if (-not $state.Updating) { $ui.Mode.SelectedIndex=1 } })
    $ui.Mode.Add_SelectionChanged({
        if ($state.Updating) { return }
        $state.Updating=$true
        try { $ui.FitPad.IsChecked=$ui.Mode.SelectedIndex -eq 0; $ui.FitCrop.IsChecked=$ui.Mode.SelectedIndex -eq 1 } finally { $state.Updating=$false }
        Set-Custom; Request-Preview
    })
    $ui.Before.Add_Checked({ if ($state.Ready) { Request-Preview } })
    $ui.After.Add_Checked({ if ($state.Ready) { Request-Preview } })
    $ui.Sources.Add_SelectionChanged({
        if ($state.Updating) { return }
        $state.Updating=$true; $ui.Filmstrip.SelectedItem=$ui.Sources.SelectedItem; $state.Updating=$false
        if ($null -ne $ui.Filmstrip.SelectedItem) { $ui.Filmstrip.ScrollIntoView($ui.Filmstrip.SelectedItem) }
        $ui.Zoom.Value=100; Request-Preview
    })
    $ui.Filmstrip.Add_SelectionChanged({ if (-not $state.Updating -and $null -ne $ui.Filmstrip.SelectedItem) { $ui.Sources.SelectedItem=$ui.Filmstrip.SelectedItem; $ui.Sources.ScrollIntoView($ui.Sources.SelectedItem) } })
    $ui.PrevPhoto.Add_Click({ if ($ui.Sources.SelectedIndex -gt 0) { $ui.Sources.SelectedIndex--; $ui.Sources.ScrollIntoView($ui.Sources.SelectedItem) } })
    $ui.NextPhoto.Add_Click({ if ($ui.Sources.SelectedIndex -lt $photos.Count-1) { $ui.Sources.SelectedIndex++; $ui.Sources.ScrollIntoView($ui.Sources.SelectedItem) } })
    $ui.Zoom.Add_ValueChanged({ Update-Zoom })
    $ui.ZoomIn.Add_Click({ $ui.Zoom.Value=[Math]::Min($ui.Zoom.Maximum,$ui.Zoom.Value+25) })
    $ui.ZoomOut.Add_Click({ $ui.Zoom.Value=[Math]::Max($ui.Zoom.Minimum,$ui.Zoom.Value-25) })
    $ui.FitView.Add_Click({ $ui.Zoom.Value=100; $ui.PreviewScroll.ScrollToHorizontalOffset(0); $ui.PreviewScroll.ScrollToVerticalOffset(0); Update-Zoom })
    $ui.PreviewSurface.Add_SizeChanged({ Update-Zoom })
    $ui.PreviewScroll.Add_PreviewMouseWheel({
        param($sender,$eventArgs)
        if ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) { $ui.Zoom.Value=[Math]::Max(100,[Math]::Min(400,$ui.Zoom.Value+$(if ($eventArgs.Delta -gt 0) { 25 } else { -25 }))); $eventArgs.Handled=$true }
    })
    $ui.SelectAll.Add_Click({
        if ($state.Updating) { return }
        $include=$ui.SelectAll.IsChecked -ne $false; $state.Updating=$true
        try { foreach ($photo in $photos) { $photo.IsIncluded=$include } } finally { $state.Updating=$false }
        Update-Counts
    })
    $ui.Recursive.Add_Click({ Start-Scan })
    $ui.AddFolder.Add_Click({
        $dialog=New-Object Windows.Forms.FolderBrowserDialog
        try { if ($dialog.ShowDialog() -eq 'OK') { Add-Sources @($dialog.SelectedPath) } } finally { $dialog.Dispose() }
    })
    $ui.AddFiles.Add_Click({
        $dialog=New-Object Microsoft.Win32.OpenFileDialog; $dialog.Filter='Zdjecia JPG|*.jpg;*.jpeg'; $dialog.Multiselect=$true
        if ($dialog.ShowDialog($window)) { Add-Sources $dialog.FileNames }
    })
    $ui.RemoveSource.Add_Click({
        $photo=$ui.Sources.SelectedItem
        if ($null -eq $photo -or $state.Busy -or $state.Downloading) { return }
        $index=$ui.Sources.SelectedIndex; $state.Removed[$photo.FullPath]=$true
        [void]$state.Paths.Remove($photo.FullPath); $state.ItemByPath.Remove($photo.FullPath); [void]$photos.Remove($photo)
        if ($photos.Count) { $ui.Sources.SelectedIndex=[Math]::Min($index,$photos.Count-1) }
        Update-Counts; Update-Output
    })
    $ui.ClearSources.Add_Click({
        foreach ($task in $state.Tasks.ToArray()) { if ($task.Kind -eq 'Scan') { $task.Control.Cancel=$true } }
        $state.ScanSequence++; $state.Scanning=$false; $state.Paths.Clear(); $state.Removed.Clear(); $state.Inclusion.Clear(); $state.ItemByPath.Clear()
        $photos.Clear(); $ui.Progress.IsIndeterminate=$false; $ui.Progress.Value=0; $ui.Status.Text='Gotowe do pracy'; Request-Preview; Update-Counts
    })
    $ui.ChooseOutput.Add_Click({
        $dialog=New-Object Windows.Forms.FolderBrowserDialog
        try { if ($dialog.ShowDialog() -eq 'OK') { $state.CustomOutput=$true; $ui.Output.Text=$dialog.SelectedPath; Update-Output; Start-Scan } } finally { $dialog.Dispose() }
    })
    $ui.DefaultOutput.Add_Click({ $state.CustomOutput=$false; Update-Output; Start-Scan })
    $ui.BrandLink.Add_Click({ Start-Process $appInfo.website })
    $sourceMenu=New-Object Windows.Controls.ContextMenu
    $ui.SourcePath=New-Object Windows.Controls.TextBox
    $ui.SourcePath.IsReadOnly=$true; $ui.SourcePath.MinWidth=320; $ui.SourcePath.MaxWidth=640
    $ui.SourcePath.HorizontalScrollBarVisibility='Auto'
    [Windows.Automation.AutomationProperties]::SetName($ui.SourcePath,(T 'Pe\u0142na \u015bcie\u017cka \u017ar\u00f3d\u0142a'))
    [void]$sourceMenu.Items.Add($ui.SourcePath)
    $copySource=New-Object Windows.Controls.MenuItem; $copySource.Header=T 'Kopiuj \u015bcie\u017ck\u0119 \u017ar\u00f3d\u0142a'
    $copySource.Add_Click({ if ($ui.SourcePath.Text) { [Windows.Clipboard]::SetText($ui.SourcePath.Text) } })
    [void]$sourceMenu.Items.Add($copySource)
    $ui.PhotoName.ContextMenu=$sourceMenu
    $ui.RepositoryLink.Add_Click({ Start-Process ('https://github.com/'+$appInfo.repository) })
    if ($ui.ContainsKey('SettingsButton')) { $ui.SettingsButton.Add_Click({ $ui.DimensionsExpander.IsExpanded=-not $ui.DimensionsExpander.IsExpanded; $ui.DimensionsExpander.BringIntoView() }) }

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
    $ui.Cancel.Add_Click({
        $state.Cancelling=$true
        foreach ($task in $state.Tasks.ToArray()) { if ($task.Kind -in @('Scan','Export')) { $task.Control.Cancel=$true } }
        $ui.Cancel.IsEnabled=$false; $ui.Status.Text=T 'Zatrzymywanie po bie\u017c\u0105cym zdj\u0119ciu...'
        Announce-Status
    })
    $ui.Start.Add_Click({
        if ($state.Busy -or $state.Scanning -or $state.Downloading) { return }
        $included=@($photos | Where-Object IsIncluded)
        if ($included.Count -eq 0) { $ui.Status.Text=T 'Zaznacz zdj\u0119cia do eksportu'; return }
        try {
            $options=Get-ExportOptions
            $snapshot=@(foreach ($photo in $included) {
                [pscustomobject]@{FullPath=$photo.FullPath;SourceRoot=$photo.SourceRoot;SourcePath=$photo.SourcePath;SourceName=$photo.SourceName;RelativePath=$photo.RelativePath;Name=$photo.Name;Orientation=$photo.Orientation;Width=$photo.OriginalWidth;Height=$photo.OriginalHeight;Error=$photo.Error}
            })
            $destination=if ($state.CustomOutput) { $ui.Output.Text.Trim() } else { '' }
            foreach ($item in $snapshot) { [void](Get-ResizerQueueTargetPath -Item $item -DestinationFolder $destination) }
        } catch {
            $ui.Status.Text=$_.Exception.Message
            if ($null -ne $state.InvalidControl) {
                $ui.DimensionsExpander.IsExpanded=$true; $state.InvalidControl.BringIntoView()
                $window.UpdateLayout()
                [void]$state.InvalidControl.Focus(); $state.InvalidControl.SelectAll()
            }
            Announce-Status; return
        }
        $state.Busy=$true; $state.Cancelling=$false; $state.Outputs=@(); $state.ExportWatch=[Diagnostics.Stopwatch]::StartNew()
        $ui.Log.Clear(); $ui.Progress.IsIndeterminate=$false; $ui.Progress.Value=0
        $ui.Status.Text=T ('Eksport {0} zdj\u0119\u0107...' -f $included.Count)
        Announce-Status
        Start-Work 'Export' @{Items=$snapshot;Options=$options;Destination=$destination} 0
        Set-ControlState
    })
    $ui.OpenOutput.Add_Click({
        $paths=@($state.Outputs | Select-Object -Unique)
        if ($paths.Count -eq 1) { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $paths[0]); return }
        $menu=New-Object Windows.Controls.ContextMenu
        foreach ($path in $paths) {
            if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
            $entry=New-Object Windows.Controls.MenuItem; $entry.Header=$path; $entry.Tag=$path
            $entry.Add_Click({ param($sender,$eventArgs) Start-Process explorer.exe -ArgumentList ('"{0}"' -f $sender.Tag) })
            [void]$menu.Items.Add($entry)
        }
        $menu.PlacementTarget=$ui.OpenOutput; $menu.IsOpen=$true
    })

    function Open-Overlay([string]$Kind) {
        $ui.MainLayout.IsEnabled=$false
        if ($Kind -eq 'Log') { $ui.LogOverlay.Visibility='Visible'; $ui.Log.ScrollToEnd(); [void]$ui.CloseLog.Focus() }
        else { $ui.UpdateOverlay.Visibility='Visible'; [void]$ui.CheckUpdate.Focus() }
    }
    function Close-Overlay {
        if ($state.Installing) { return }
        $wasLog=$ui.LogOverlay.Visibility -eq 'Visible'
        $ui.LogOverlay.Visibility='Collapsed'; $ui.UpdateOverlay.Visibility='Collapsed'; $ui.MainLayout.IsEnabled=$true
        if ($wasLog) { [void]$ui.LogButton.Focus() } else { [void]$ui.UpdatesButton.Focus() }
    }
    $ui.LogButton.Add_Click({ Open-Overlay 'Log' })
    $ui.CloseLog.Add_Click({ Close-Overlay })
    $ui.UpdatesButton.Add_Click({ Open-Overlay 'Updates' })
    $ui.CloseUpdates.Add_Click({ Close-Overlay })
    $window.Add_PreviewKeyDown({
        param($sender,$eventArgs)
        if ($eventArgs.Key -eq [Windows.Input.Key]::Escape -and ($ui.LogOverlay.Visibility -eq 'Visible' -or $ui.UpdateOverlay.Visibility -eq 'Visible')) { Close-Overlay; $eventArgs.Handled=$true }
    })
    function Start-UpdateTask([string]$Kind,[scriptblock]$Completed) {
        if ($state.NetworkBusy -or ($Kind -eq 'Download' -and ($state.Busy -or $state.Scanning))) { return }
        $state.NetworkBusy=$true; $state.Downloading=$Kind -eq 'Download'
        $ui.CheckUpdate.IsEnabled=$false; $ui.UpdateProgress.Visibility='Visible'
        $ui.UpdateStatus.Text=if ($Kind -eq 'Download') { 'Pobieranie i sprawdzanie paczki...' } else { 'Sprawdzanie GitHub Releases...' }
        $ps=[PowerShell]::Create()
        [void]$ps.AddScript('param($root,$kind,$candidate) $ErrorActionPreference="Stop"; . (Join-Path $root "ResizerUpdates.ps1"); if ($kind -eq "Check") { Get-ResizerRelease -Metadata (Get-ResizerAppInfo -Directory $root) } else { Save-ResizerUpdate -Candidate $candidate }').AddArgument($root).AddArgument($Kind).AddArgument($state.Candidate)
        $state.NetworkTasks.Add([pscustomobject]@{PowerShell=$ps;Handle=$ps.BeginInvoke();Completed=$Completed})
        Set-ControlState
    }
    $networkTimer=New-Object Windows.Threading.DispatcherTimer; $networkTimer.Interval=[TimeSpan]::FromMilliseconds(160)
    $networkTimer.Add_Tick({
        foreach ($task in $state.NetworkTasks.ToArray()) {
            if (-not $task.Handle.IsCompleted) { continue }
            [void]$state.NetworkTasks.Remove($task); $state.NetworkBusy=$false; $state.Downloading=$false
            $ui.UpdateProgress.Visibility='Collapsed'; $ui.CheckUpdate.IsEnabled=$true
            try {
                $result=$task.PowerShell.EndInvoke($task.Handle)
                if ($task.PowerShell.Streams.Error.Count) { throw $task.PowerShell.Streams.Error[0].ToString() }
                & $task.Completed $result[0]
            } catch { $state.Installing=$false; $ui.UpdateStatus.Text=$_.Exception.Message }
            finally { $task.PowerShell.Dispose(); Set-ControlState }
        }
    })
    $networkTimer.Start()
    $checkCompleted={
        param($candidate)
        $state.Candidate=$candidate
        if ($candidate.Available) { $ui.UpdateStatus.Text='Dostepna wersja {0} ({1:N1} MB).' -f $candidate.Version,($candidate.Size/1MB); $ui.UpdatesCaption.Text='Nowa wersja '+$candidate.Version }
        elseif ($candidate.Status -eq 'NoRelease') { $ui.UpdateStatus.Text='Repozytorium nie ma jeszcze opublikowanych wydan.' }
        else { $ui.UpdateStatus.Text='Masz aktualna wersje programu.' }
    }
    $ui.CheckUpdate.Add_Click({ Start-UpdateTask 'Check' $checkCompleted })
    $ui.InstallUpdate.Add_Click({
        if ($state.Busy -or $state.Scanning -or $state.NetworkBusy -or $null -eq $state.Candidate -or -not $state.Candidate.Available) { return }
        $state.Installing=$true
        Start-UpdateTask 'Download' {
            param($stage)
            $ui.UpdateStatus.Text='Instalowanie aktualizacji...'
            $installer=Join-Path $stage 'Install-Update.ps1'
            $psPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $command='"{0}" -Sta -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" -AppDirectory "{2}" -StageDirectory "{3}" -ExpectedVersion "{4}" -ParentProcessId {5}' -f $psPath,$installer,$root,$stage,$state.Candidate.Version,$PID
            $shell=New-Object -ComObject WScript.Shell; [void]$shell.Run($command,0,$false)
            $state.Installing=$false; $window.Close()
        }
    })
    $ui.AutoUpdate.Add_Click({ [void](New-Item -ItemType Directory -Path $configDirectory -Force); [IO.File]::WriteAllText($configFile,(@{CheckOnStartup=[bool]$ui.AutoUpdate.IsChecked}|ConvertTo-Json)) })
    $window.Add_Closing({
        param($sender,$eventArgs)
        if ($state.Busy -or $state.Scanning) {
            $state.CloseRequested=$true; $state.Cancelling=$true; $eventArgs.Cancel=$true
            foreach ($task in $state.Tasks.ToArray()) { if ($task.Kind -in @('Scan','Export')) { $task.Control.Cancel=$true } }
            $ui.Status.Text=T 'Zatrzymywanie po bie\u017c\u0105cym zdj\u0119ciu...'
            Set-ControlState; Announce-Status
        } elseif ($state.Installing -and $state.NetworkBusy) { $eventArgs.Cancel=$true; $ui.UpdateStatus.Text='Poczekaj na zakonczenie pobierania.' }
    })
    $window.Add_ContentRendered({ if ($null -ne $OnShown) { & $OnShown $window } elseif ($ui.AutoUpdate.IsChecked) { Start-UpdateTask 'Check' $checkCompleted } })
    $window.Add_SizeChanged({
        $available=$window.ActualWidth
        $ui.QueueColumn.Width=[Windows.GridLength]::new([Math]::Min(420,[Math]::Max(280,$available*0.29)))
        $ui.InspectorColumn.Width=[Windows.GridLength]::new([Math]::Min(324,[Math]::Max(280,$available*0.225)))
        $compact=$window.ActualHeight -lt 850
        $ui.Settings.Margin=if ($compact) { [Windows.Thickness]::new(20,8,20,4) } else { [Windows.Thickness]::new(20,24,20,14) }
        $ui.InspectorHeading.Margin=if ($compact) { [Windows.Thickness]::new(0,0,0,8) } else { [Windows.Thickness]::new(0,0,0,18) }
        $ui.SizePair.Margin=if ($compact) { [Windows.Thickness]::new(0,8,0,8) } else { [Windows.Thickness]::new(0,18,0,22) }
        $ui.FitLabel.Margin=if ($compact) { [Windows.Thickness]::new(0,8,0,4) } else { [Windows.Thickness]::new(0,22,0,8) }
        $ui.QualityRow.Margin=if ($compact) { [Windows.Thickness]::new(0,8,0,0) } else { [Windows.Thickness]::new(0,20,0,0) }
        $ui.DimensionsExpander.Margin=if ($compact) { [Windows.Thickness]::new(0,8,0,0) } else { [Windows.Thickness]::new(0,24,0,0) }
        if ($ui.Zoom.Value -eq 100) { Update-Zoom }
    })
    Set-Presets; $state.Ready=$true; Update-Counts; Update-Output
    if ($InitialFolders.Count) { Add-Sources $InitialFolders }
    $area=[Windows.SystemParameters]::WorkArea
    $window.MinWidth=[Math]::Min(1000,$area.Width-32); $window.MinHeight=[Math]::Min(680,$area.Height-32)
    $window.Width=[Math]::Min(1440,$area.Width-32); $window.Height=[Math]::Min(1024,$area.Height-32)
    try { [void]$window.ShowDialog() } finally {
        $state.Closed=$true; $previewTimer.Stop(); $workTimer.Stop(); $networkTimer.Stop()
        foreach ($task in $state.Tasks.ToArray()) { $task.Control.Cancel=$true }
        foreach ($task in @($state.Tasks.ToArray())+@($state.NetworkTasks.ToArray())) { try { $task.PowerShell.Stop() } catch { }; $task.PowerShell.Dispose() }
    }
}
