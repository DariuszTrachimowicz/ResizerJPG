param([string]$ProgramFolder='', [switch]$LiveUpdates)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = if ($ProgramFolder) { [IO.Path]::GetFullPath($ProgramFolder) } else { Split-Path -Parent $PSScriptRoot }
Add-Type -AssemblyName System.Drawing
$parseErrors = $null
$parseTokens = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ResizerJPG.ps1'),[ref]$parseTokens,[ref]$parseErrors)
foreach ($statement in $ast.EndBlock.Statements) { if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) { . ([scriptblock]::Create($statement.Extent.Text)) } }
. (Join-Path $root 'ResizerUI.ps1')
$metadata = Get-ResizerAppInfo -Directory $root
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('resizer-wpf-test-'+[guid]::NewGuid())
[void](New-Item -ItemType Directory -Path $fixture)
try {
    foreach ($size in @(@(480,720,'produkt-pion.jpg'),@(720,480,'produkt-poziom.jpg'))) {
        $image = New-Object Drawing.Bitmap($size[0],$size[1])
        $g = [Drawing.Graphics]::FromImage($image)
        $g.Clear([Drawing.Color]::White)
        $g.FillRectangle([Drawing.Brushes]::DarkCyan,100,100,240,260)
        $g.FillEllipse([Drawing.Brushes]::Coral,155,155,120,120)
        $image.Save((Join-Path $fixture $size[2]),[Drawing.Imaging.ImageFormat]::Jpeg)
        $g.Dispose(); $image.Dispose()
    }
    $script:uiFailure = ''
    Show-ResizerWindow -InitialFolders @($fixture) -OnShown {
        param($window)
        try {
            $ui = $window.Tag
            Assert ($ui.Sources.Items.Count -eq 1) 'Initial source must load.'
            Assert ($ui.Profile.SelectedItem.Content -eq 'Makalu Sklep') 'Makalu Sklep must be the default profile.'
            Assert ($ui.VersionFooter.Text -like ('*'+$metadata.version)) 'Version must be visible in footer.'
            Assert ($null -ne $ui.BrandLogo.Source) 'Original brand logo must render.'
            Assert ($null -ne $ui.Preview.Source -and $ui.Preview.Source.PixelWidth -gt 1) 'Photo preview must be nonblank.'
            $data = New-Object Windows.DataObject
            $data.SetData([Windows.DataFormats]::FileDrop,[string[]]@((Join-Path $fixture 'produkt-pion.jpg')))
            $constructor = [Windows.DragEventArgs].GetConstructors([Reflection.BindingFlags]'Instance,NonPublic')[0]
            $parameters = New-Object 'object[]' 5
            $parameters[0] = $data.PSObject.BaseObject
            $parameters[1] = [Windows.DragDropKeyStates]::None
            $parameters[2] = [Windows.DragDropEffects]::Copy
            $parameters[3] = $window.PSObject.BaseObject
            $parameters[4] = (New-Object Windows.Point(0,0)).PSObject.BaseObject
            $drag = $constructor.Invoke($parameters)
            $drag.RoutedEvent = [Windows.DragDrop]::PreviewDragOverEvent
            $window.RaiseEvent($drag)
            Assert ($drag.Effects -eq [Windows.DragDropEffects]::Copy) 'File drag-over must be accepted.'
            $drag.RoutedEvent = [Windows.DragDrop]::PreviewDropEvent
            $drag.Handled = $false
            $window.RaiseEvent($drag)
            Assert ($ui.Sources.Items.Count -eq 1) 'Covered JPG must not be duplicated.'
            $otherFolder = Join-Path $fixture 'Inne zdjecia'
            [void](New-Item -ItemType Directory -Path $otherFolder)
            Copy-Item -LiteralPath (Join-Path $fixture 'produkt-pion.jpg') -Destination (Join-Path $otherFolder 'inne.jpg')
            $data.SetData([Windows.DataFormats]::FileDrop,[string[]]@($fixture,$otherFolder))
            $drag.Handled = $false
            $window.RaiseEvent($drag)
            Assert ($ui.Sources.Items.Count -eq 2) 'Multiple-folder drop must load both sources.'
            $ui.Quality.Value = 75
            Assert ($ui.QualityNumber.Text -eq '75') 'Quality label must follow slider.'
            $ui.Profile.SelectedIndex = 0
            Assert ($ui.Quality.Value -eq 85 -and $ui.WidthBox.Text -eq '2880') 'Profile must restore defaults.'
            $ui.Before.IsChecked = $true
            Assert ($ui.Preview.Source.PixelWidth -eq 480) 'Original photo must be available.'
            $ui.After.IsChecked = $true
            $ui.NextPhoto.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            Assert ($ui.PhotoCounter.Text -eq '2 / 2') 'Preview navigation must reach second photo.'
            $timer = New-Object Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds(1)
            $timer.Add_Tick({ $ui.Cancel.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent))); $timer.Stop() })
            $timer.Start()
            $ui.Start.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            $timer.Stop()
            Assert ($ui.Status.Text -match '^Zatrzymano') 'Cancellation must stop the GUI batch.'
            $ui.Start.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            Assert ($ui.Status.Text -match 'zapisano: 3.*bledy: 0') 'GUI must export photos from both folders.'
            Assert (Test-Path (Join-Path $fixture 'resize\produkt-pion_R.jpg')) 'GUI must write suffixed JPG.'
            Assert ($ui.Start.IsEnabled -and -not $ui.Cancel.IsEnabled) 'Controls must reset after batch.'
            $ui.UpdatesButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            Assert ($ui.UpdateOverlay.Visibility -eq 'Visible') 'Updates overlay must open.'
            if ($LiveUpdates) {
                $ui.CheckUpdate.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                $deadline = [DateTime]::UtcNow.AddSeconds(25)
                while ($ui.UpdateProgress.Visibility -eq 'Visible' -and [DateTime]::UtcNow -lt $deadline) { Invoke-ResizerUiEvents; Start-Sleep -Milliseconds 20 }
                Assert ($ui.UpdateStatus.Text -eq 'Masz aktualna wersje programu.') 'Live update check must reach published current release.'
                Write-Host 'PASS: asynchronous update check against published GitHub Release.'
            }
            $ui.CloseUpdates.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            foreach ($size in @(@(1240,840,'Resizer-v2.png'),@(1000,680,'Resizer-v2-compact.png'))) {
                $window.Width = $size[0]; $window.Height = $size[1]
                $window.UpdateLayout()
                Invoke-ResizerUiEvents
                $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.Content.ActualWidth,[int]$window.Content.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($window.Content)
                $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                $stream = [IO.File]::Create((Join-Path $PSScriptRoot $size[2]))
                $encoder.Save($stream); $stream.Dispose()
            }
            Write-Host 'PASS: WPF branding, Makalu, version, preview, quality, before/after, navigation, drag/drop, cancellation/restart, export, updates panel, two sizes.'
        } catch { $script:uiFailure = $_.ToString() } finally { $window.Close() }
    }
    if ($script:uiFailure) { throw $script:uiFailure }
} finally {
    $full = [IO.Path]::GetFullPath($fixture)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\resizer-wpf-test-'
    if ($full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $full -Recurse -Force }
}
