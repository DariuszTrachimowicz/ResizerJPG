param([string]$ProgramFolder = '', [switch]$LiveUpdates, [switch]$QueueContractOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = if ($ProgramFolder) { [IO.Path]::GetFullPath($ProgramFolder) } else { Split-Path -Parent $PSScriptRoot }
Add-Type -AssemblyName System.Drawing,PresentationFramework,PresentationCore,WindowsBase

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-VisualNodes($Node) {
    $Node
    if ($Node -is [Windows.Media.Visual] -or $Node -is [Windows.Media.Media3D.Visual3D]) {
        for ($index = 0; $index -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Node); $index++) {
            Get-VisualNodes ([Windows.Media.VisualTreeHelper]::GetChild($Node, $index))
        }
    }
}

function Assert-QueueTemplate($List, [switch]$IncludeCheckbox) {
    Assert ($null -ne $List.ItemTemplate) 'Photo queue must render individual photo viewmodels, not folder sources.'
    $nodes = @(Get-VisualNodes ($List.ItemTemplate.LoadContent()))
    $thumbnailBindings = @($nodes | Where-Object {
        if ($_ -is [Windows.Controls.Image]) {
            $binding = [Windows.Data.BindingOperations]::GetBinding($_, [Windows.Controls.Image]::SourceProperty)
            $null -ne $binding -and $binding.Path.Path -eq 'Thumbnail'
        }
    })
    Assert ($thumbnailBindings.Count -gt 0) 'Photo queue must display the photo viewmodel Thumbnail ImageSource.'
    if ($IncludeCheckbox) {
        $toggles = @($nodes | Where-Object { $_ -is [Windows.Controls.CheckBox] -and $_.Tag -eq 'PhotoToggle' })
        Assert ($toggles.Count -eq 1) 'Each photo needs its own PhotoToggle inclusion checkbox.'
        $binding = [Windows.Data.BindingOperations]::GetBinding($toggles[0], [Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty)
        Assert ($null -ne $binding -and $binding.Path.Path -eq 'IsIncluded' -and $binding.Mode -eq 'TwoWay') 'PhotoToggle must bind IsIncluded TwoWay independently of preview selection.'
    }
}

# Load XAML without showing a window for the non-interactive TDD red cycle.
[xml]$contractXaml = Get-Content -LiteralPath (Join-Path $root 'ResizerWindow.xaml') -Raw
$contractReader = New-Object Xml.XmlNodeReader($contractXaml)
try { $contractWindow = [Windows.Markup.XamlReader]::Load($contractReader) } finally { $contractReader.Dispose() }
$contractSources = $contractWindow.FindName('Sources')
Assert ($contractSources -is [Windows.Controls.ListBox]) 'Sources must be a flat ListBox of photos.'
Assert-QueueTemplate $contractSources -IncludeCheckbox
$contractFilmstrip = $contractWindow.FindName('Filmstrip')
Assert ($contractFilmstrip -is [Windows.Controls.ListBox]) 'Photo queue must expose the synchronized thumbnail filmstrip.'
Assert-QueueTemplate $contractFilmstrip
$requiredNames = @(
    'MainLayout',
    'Before','After','Preview','PreviewSurface','PreviewScroll','EmptyPreview','EmptyText','DropHighlight',
    'Profile','Ratio','Preset','WidthBox','HeightBox','DpiBox','Quality','QualityNumber','Mode','FitPad','FitCrop',
    'DimensionsExpander','Settings','BrandLink','BrandLogo','UpdatesButton','UpdatesCaption','VersionFooter',
    'InstalledVersion','RepositoryLink','UpdateOverlay','CheckUpdate','InstallUpdate','CloseUpdates','AutoUpdate',
    'UpdateStatus','UpdateProgress','LogOverlay','Log','LogButton','CloseLog','AddFolder','AddFiles','RemoveSource',
    'ClearSources','Recursive','SelectAll','Output','ChooseOutput','DefaultOutput','OutputExample','OutputFilename',
    'SelectionCount','StartButton','StartCaption','Cancel','OpenOutput','Status','Progress','PhotoName',
    'PhotoDimensions','PreviewTitle','PrevPhoto','NextPhoto','PhotoCounter','Zoom','ZoomCaption','ZoomIn','ZoomOut','FitView',
    'FolderPlusIcon','ImagesIcon','TrashIcon','PrevIcon','NextIcon','EmptyImageIcon','OutputFolderIcon',
    'ResetIcon','PlayIcon','StopIcon','UpdatesIcon','CloseUpdatesIcon','CloseLogIcon'
)
foreach ($name in $requiredNames) {
    Assert ($null -ne $contractWindow.FindName($name)) ('Required event-binding control missing: ' + $name)
}
Assert ($contractWindow.FindName('PreviewSurface') -is [Windows.Controls.Grid]) 'PreviewSurface must remain a Grid around PreviewScroll.'
Assert ($contractWindow.FindName('PreviewScroll') -is [Windows.Controls.ScrollViewer]) 'PreviewScroll must support zoomed photo scrolling.'
Assert ($contractWindow.FindName('PreviewScroll').Focusable) 'PreviewScroll must be keyboard focusable for accessible scrolling.'
Assert ($contractWindow.FindName('Settings') -is [Windows.Controls.StackPanel]) 'Settings must remain a StackPanel for shared enable/disable.'
Assert ($contractWindow.FindName('Output').IsReadOnly -and $contractWindow.FindName('OutputFilename').IsReadOnly) 'Output paths and _R filename examples must not be editable.'
Assert ($contractWindow.FindName('OutputExample') -is [Windows.Controls.TextBox] -and $contractWindow.FindName('OutputExample').IsReadOnly) 'Full output path must be a selectable read-only TextBox.'
Assert ($contractWindow.FindName('SelectAll') -is [Windows.Controls.CheckBox] -and $contractWindow.FindName('SelectAll').IsThreeState) 'SelectAll must be a tri-state checkbox.'
Assert ($contractWindow.FindName('Mode').Visibility -eq 'Collapsed') 'Legacy Pad/Crop ComboBox must be collapsed.'
Assert ($contractWindow.FindName('Zoom').Minimum -eq 100 -and $contractWindow.FindName('Zoom').Maximum -eq 400) 'Photo zoom must span fitted 100 to 400 percent.'
Assert ($contractWindow.FindName('Cancel').Visibility -eq 'Collapsed') 'Stop action must be collapsed before processing.'
Write-Host 'PASS: queue thumbnails, inclusion binding and named XAML contract.'
if ($QueueContractOnly) { return }

$parseErrors = $null
$parseTokens = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ResizerJPG.ps1'), [ref]$parseTokens, [ref]$parseErrors)
Assert ($parseErrors.Count -eq 0) 'CLI script must remain parseable in Windows PowerShell 5.1.'
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) { . ([scriptblock]::Create($statement.Extent.Text)) }
}
. (Join-Path $root 'ResizerUI.ps1')
$metadata = Get-ResizerAppInfo -Directory $root

function Invoke-UiClick($Button) {
    $Button.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
}

function Invoke-UiEscape($Window) {
    $event = [Windows.Input.KeyEventArgs]::new([Windows.Input.Keyboard]::PrimaryDevice, [Windows.PresentationSource]::FromVisual($Window), [Environment]::TickCount, [Windows.Input.Key]::Escape)
    $event.RoutedEvent = [Windows.Input.Keyboard]::PreviewKeyDownEvent
    $Window.RaiseEvent($event)
    Assert ($event.Handled) 'An open modal must handle Escape rather than passing it to the main view.'
    Invoke-ResizerUiEvents
}

function Wait-UiIdle($Ui, [string]$Operation) {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        Invoke-ResizerUiEvents
        if (-not $Ui.State.Scanning -and -not $Ui.State.PreviewBusy -and -not $Ui.State.Busy) { return }
        Start-Sleep -Milliseconds 20
    } while ([DateTime]::UtcNow -lt $deadline)
    throw ('Timed out waiting for ' + $Operation + ': Scanning=' + $Ui.State.Scanning + '; PreviewBusy=' + $Ui.State.PreviewBusy + '; Busy=' + $Ui.State.Busy)
}

function Invoke-PhotoDrop($Window, [string[]]$Paths) {
    $data = New-Object Windows.DataObject
    $data.SetData([Windows.DataFormats]::FileDrop, $Paths)
    $constructor = [Windows.DragEventArgs].GetConstructors([Reflection.BindingFlags]'Instance,NonPublic')[0]
    $parameters = New-Object 'object[]' 5
    $parameters[0] = $data.PSObject.BaseObject
    $parameters[1] = [Windows.DragDropKeyStates]::None
    $parameters[2] = [Windows.DragDropEffects]::Copy
    $parameters[3] = $Window.PSObject.BaseObject
    $parameters[4] = (New-Object Windows.Point(0,0)).PSObject.BaseObject
    $drag = $constructor.Invoke($parameters)
    $drag.RoutedEvent = [Windows.DragDrop]::PreviewDragOverEvent
    $Window.RaiseEvent($drag)
    Assert ($drag.Effects -eq [Windows.DragDropEffects]::Copy) 'Photo and folder drag-over must be accepted.'
    $drag.RoutedEvent = [Windows.DragDrop]::PreviewDropEvent
    $drag.Handled = $false
    $Window.RaiseEvent($drag)
}

function Assert-ExportImage([string]$Path, [int]$Width, [int]$Height, [int]$Dpi = 72) {
    Assert (Test-Path -LiteralPath $Path -PathType Leaf) ('Missing safe suffixed export: ' + $Path)
    $image = [Drawing.Image]::FromFile($Path)
    try {
        Assert ($image.Width -eq $Width -and $image.Height -eq $Height) ('Incorrect Makalu dimensions: ' + $Path)
        Assert ([Math]::Abs($image.HorizontalResolution - $Dpi) -lt 1 -and [Math]::Abs($image.VerticalResolution - $Dpi) -lt 1) ('Incorrect export DPI: ' + $Path)
    } finally { $image.Dispose() }
}

function Save-UiRender($Window, [int]$Width, [int]$Height, [string]$Name) {
    $Window.Width = $Width
    $Window.Height = $Height
    $Window.UpdateLayout()
    Invoke-ResizerUiEvents
    Assert ($Window.Content.ActualWidth -gt 0 -and $Window.Content.ActualHeight -gt 0) 'Rendered client surface must not be blank.'
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$Window.Content.ActualWidth, [int]$Window.Content.ActualHeight, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($Window.Content)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create((Join-Path $PSScriptRoot $Name))
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('resizer-wpf-test-' + [guid]::NewGuid())
$sourceA = Join-Path $fixture 'Kolekcja'
$sourceB = Join-Path $fixture 'Inne zdjecia'
$originalHashes = @{}
[void](New-Item -ItemType Directory -Path $sourceA, $sourceB, (Join-Path $sourceB 'child'), (Join-Path $sourceB 'resize'))
try {
    foreach ($size in @(@(480,720,'produkt-pion.jpg'), @(720,480,'produkt-poziom.jpg'))) {
        $image = New-Object Drawing.Bitmap($size[0], $size[1])
        $g = [Drawing.Graphics]::FromImage($image)
        try {
            $g.Clear([Drawing.Color]::White)
            $g.FillRectangle([Drawing.Brushes]::DarkCyan,100,100,240,260)
            $g.FillEllipse([Drawing.Brushes]::Coral,155,155,120,120)
            $image.Save((Join-Path $sourceA $size[2]), [Drawing.Imaging.ImageFormat]::Jpeg)
        } finally { $g.Dispose(); $image.Dispose() }
    }
    Copy-Item -LiteralPath (Join-Path $sourceA 'produkt-pion.jpg') -Destination (Join-Path $sourceB 'inne.jpg')
    Copy-Item -LiteralPath (Join-Path $sourceA 'produkt-pion.jpg') -Destination (Join-Path $sourceB 'resize\ignored_R.jpg')
    foreach ($path in @((Join-Path $sourceA 'produkt-pion.jpg'), (Join-Path $sourceA 'produkt-poziom.jpg'), (Join-Path $sourceB 'inne.jpg'))) {
        $originalHashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    $script:uiFailure = ''
    Show-ResizerWindow -InitialFolders @($sourceA) -OnShown {
        param($window)
        $ui = $window.Tag
        try {
            Assert ($ui.ContainsKey('QueueItems')) 'Window.Tag must expose QueueItems rather than folder source state.'
            Assert ($ui.ContainsKey('State') -and $ui.State -is [hashtable]) 'Window.Tag must expose asynchronous State.'
            foreach ($key in @('Scanning','Busy','PreviewBusy','Cancelling')) { Assert ($ui.State.ContainsKey($key)) ('Missing asynchronous state: ' + $key) }
            Wait-UiIdle $ui 'initial scan and preview'
            Assert ($ui.QueueItems -is [Collections.Specialized.INotifyCollectionChanged]) 'QueueItems must be an observable photo collection.'
            Assert ($ui.QueueItems.Count -eq 2 -and $ui.Sources.Items.Count -eq 2) 'Initial folder must show two individual photos.'
            Assert ($ui.Sources.ItemsSource -is [Windows.Data.ListCollectionView]) 'Sources must expose a grouped ListCollectionView.'
            $groups = @($ui.Sources.ItemsSource.GroupDescriptions | Where-Object { $_.PropertyName -eq 'SourceRoot' })
            Assert ($groups.Count -eq 1 -and $ui.Sources.ItemsSource.Groups.Count -eq 1) 'Photo rows must group by SourceRoot.'
            Assert ($ui.Filmstrip.Items.Count -eq 2) 'Filmstrip must contain the same initial photos.'
            foreach ($photo in $ui.QueueItems) {
                foreach ($property in @('FullPath','SourceRoot','SourceName','RelativePath','Name','Details','Orientation','OriginalWidth','OriginalHeight','Thumbnail','IsIncluded','Status','LastOutputPath')) {
                    Assert ($null -ne $photo.PSObject.Properties[$property]) ('Photo viewmodel missing: ' + $property)
                }
                Assert ($photo -is [ComponentModel.INotifyPropertyChanged]) 'Photo inclusion must notify the UI.'
                Assert ($photo.Thumbnail -is [Windows.Media.ImageSource] -and $photo.Thumbnail.PixelWidth -gt 0) 'Photo row must have a decoded thumbnail.'
                Assert ($photo.IsIncluded) 'Initial photos must be included by default.'
            }
            Assert ($ui.SelectAll.IsChecked -eq $true) 'SelectAll must initially show all included.'
            Assert ($ui.Profile.SelectedItem.Content -eq 'Makalu Sklep') 'Makalu Sklep must be the default profile.'
            Assert ($ui.Ratio.SelectedItem.Tag -eq 'Auto' -and $ui.Quality.Value -eq 85 -and $ui.DpiBox.Text -eq '72') 'Makalu defaults must remain Auto 2:3, JPG 85 and 72 DPI.'
            Assert ($ui.VersionFooter.Text -like ('*' + $metadata.version) -and $ui.InstalledVersion.Text -like ('*' + $metadata.version)) 'Installed version must appear in both places.'
            Assert ($null -ne $ui.BrandLogo.Source) 'Original brand logo must render.'
            Assert ($null -ne $ui.Preview.Source -and $ui.Preview.Source.PixelWidth -gt 1) 'Initial preview must be nonblank.'
            $portrait = @($ui.QueueItems | Where-Object { $_.Name -eq 'produkt-pion.jpg' })[0]
            $landscape = @($ui.QueueItems | Where-Object { $_.Name -eq 'produkt-poziom.jpg' })[0]
            $ui.Sources.SelectedItem = $portrait
            $ui.Before.IsChecked = $true
            Wait-UiIdle $ui 'original portrait'
            Assert ($ui.ContainsKey('SourcePath')) 'Window.Tag must expose the accessible source path context control.'
            Assert ($ui.SourcePath -is [Windows.Controls.TextBox] -and $ui.SourcePath.IsReadOnly) 'Source path context control must be a selectable read-only TextBox.'
            Assert ($null -ne $ui.PhotoName.ContextMenu -and $ui.PhotoName.ContextMenu.Items.Contains($ui.SourcePath)) 'Source path TextBox must be present in PhotoName.ContextMenu.'
            Assert ($ui.SourcePath.Text -eq (Join-Path $sourceA 'produkt-pion.jpg')) 'PhotoName context must expose the full selected portrait source path.'
            Assert ([Windows.Automation.AutomationProperties]::GetHelpText($ui.PhotoName) -eq (Join-Path $sourceA 'produkt-pion.jpg')) 'Accessible photo help must expose the full selected source path.'
            Assert ($ui.Preview.Source.PixelWidth -eq 480 -and $ui.Preview.Source.PixelHeight -eq 720) 'Before preview must retain source dimensions.'
            Assert ([object]::ReferenceEquals($ui.Filmstrip.SelectedItem, $portrait)) 'Sources selection must synchronize Filmstrip.'
            $ui.Filmstrip.SelectedItem = $landscape
            Wait-UiIdle $ui 'filmstrip landscape'
            Assert ($ui.SourcePath.Text -eq (Join-Path $sourceA 'produkt-poziom.jpg')) 'PhotoName source path context must follow filmstrip selection.'
            Assert ([object]::ReferenceEquals($ui.Sources.SelectedItem, $landscape)) 'Filmstrip selection must synchronize Sources.'
            Assert ($ui.Preview.Source.PixelWidth -eq 720 -and $ui.Preview.Source.PixelWidth -le 2048) 'Original preview must use the source with a bounded decode.'
            $ui.After.IsChecked = $true
            Wait-UiIdle $ui 'native result preview'
            Assert ($ui.Preview.Source.PixelWidth -eq 2880 -and $ui.Preview.Source.PixelHeight -eq 1920) 'After preview must use full native Makalu landscape dimensions.'
            Invoke-PhotoDrop $window @((Join-Path $sourceA 'produkt-pion.jpg'))
            Wait-UiIdle $ui 'duplicate JPG drop'
            Assert ($ui.QueueItems.Count -eq 2) 'A covered JPG must not be duplicated.'
            $ui.Recursive.IsChecked = $false
            Invoke-UiClick $ui.Recursive
            Invoke-PhotoDrop $window @($sourceA, $sourceB, (Join-Path $sourceB 'child'))
            Wait-UiIdle $ui 'multiple folder drop'
            Assert ($ui.QueueItems.Count -eq 3 -and $ui.Sources.Items.Count -eq 3 -and $ui.Filmstrip.Items.Count -eq 3) 'Two folders and an empty child must add only the third unique photo.'
            $ui.Recursive.IsChecked = $true
            Invoke-UiClick $ui.Recursive
            Wait-UiIdle $ui 'recursive rescan'
            Assert ($ui.QueueItems.Count -eq 3) 'Recursive rescan must deduplicate photos and ignore resize outputs.'
            Assert (@($ui.Sources.ItemsSource.Groups).Count -eq 2) 'Individual photos must remain grouped under their two containing sources.'
            $portrait = @($ui.QueueItems | Where-Object { $_.Name -eq 'produkt-pion.jpg' })[0]
            $landscape = @($ui.QueueItems | Where-Object { $_.Name -eq 'produkt-poziom.jpg' })[0]
            $window.UpdateLayout()
            $groupExpanders = @((Get-VisualNodes $ui.Sources) | Where-Object { $_ -is [Windows.Controls.Expander] })
            Assert ($groupExpanders.Count -eq 2) 'Both containing folders must have collapsible photo groups.'
            $groupExpanders[0].IsExpanded = $false
            $window.UpdateLayout()
            Assert ($ui.QueueItems.Count -eq 3 -and $ui.Filmstrip.Items.Count -eq 3) 'Collapsing a folder group must not remove photos from the queue or filmstrip.'
            $groupExpanders[0].IsExpanded = $true
            $excluded = @($ui.QueueItems | Where-Object { $_.Name -eq 'inne.jpg' })[0]
            $ui.Sources.SelectedItem = $excluded
            Wait-UiIdle $ui 'preview selected but excluded photo'
            $excluded.IsIncluded = $false
            Invoke-ResizerUiEvents
            Assert ([object]::ReferenceEquals($ui.Sources.SelectedItem, $excluded)) 'Inclusion checkbox must not change preview selection.'
            Assert ($ui.StartCaption.Text -match '2' -and $ui.SelectionCount.Text -match '2') 'PropertyChanged must immediately update the count of two included photos.'
            Assert ($null -eq $ui.SelectAll.IsChecked) 'SelectAll must show indeterminate for a partially included queue.'
            $ui.SelectAll.IsChecked = $false
            Invoke-UiClick $ui.SelectAll
            Invoke-ResizerUiEvents
            Assert (@($ui.QueueItems | Where-Object { $_.IsIncluded }).Count -eq 0 -and -not $ui.StartButton.IsEnabled) 'Unchecking SelectAll must exclude every photo and disable export.'
            $ui.SelectAll.IsChecked = $true
            Invoke-UiClick $ui.SelectAll
            Invoke-ResizerUiEvents
            Assert (@($ui.QueueItems | Where-Object { $_.IsIncluded }).Count -eq 3) 'Checking SelectAll must include every photo.'
            $excluded.IsIncluded = $false
            Invoke-ResizerUiEvents
            $ui.Sources.SelectedIndex = 0
            Wait-UiIdle $ui 'first navigation photo'
            for ($index = 1; $index -le 2; $index++) {
                Invoke-UiClick $ui.NextPhoto
                Wait-UiIdle $ui 'next photo'
                Assert ($ui.PhotoCounter.Text -eq ('{0} / 3' -f ($index + 1))) 'Navigation must include all three photos, including unchecked rows.'
            }
            Invoke-UiClick $ui.PrevPhoto
            Wait-UiIdle $ui 'previous photo'
            Assert ($ui.PhotoCounter.Text -eq '2 / 3') 'Previous navigation must stay synchronized with photo rows.'
            $ui.Zoom.Value = 250
            Invoke-ResizerUiEvents
            Assert ($ui.ZoomCaption.Text -match '250') 'Zoom caption must follow the slider.'
            Invoke-UiClick $ui.ZoomIn
            Assert ($ui.Zoom.Value -gt 250) 'Zoom-in command must increase fitted percentage.'
            $zoomBeforeOut = $ui.Zoom.Value
            Invoke-UiClick $ui.ZoomOut
            Assert ($ui.Zoom.Value -lt $zoomBeforeOut) 'Zoom-out command must decrease fitted percentage.'
            Invoke-UiClick $ui.FitView
            Assert ($ui.Zoom.Value -eq 100) 'FitView must reset zoom to fitted 100 percent.'
            $ui.FitCrop.IsChecked = $true
            Wait-UiIdle $ui 'crop segment'
            Assert ($ui.Mode.SelectedIndex -eq 1) 'Visible crop segment must drive legacy export mode.'
            $ui.FitPad.IsChecked = $true
            Wait-UiIdle $ui 'white pad segment'
            Assert ($ui.Mode.SelectedIndex -eq 0) 'Visible whole-photo segment must restore Pad.'
            $ui.Quality.Value = 75
            Wait-UiIdle $ui 'custom quality'
            Assert ($ui.QualityNumber.Text -eq '75') 'Quality label must follow the slider.'
            $ui.Profile.SelectedIndex = 0
            Wait-UiIdle $ui 'Makalu reset'
            Assert ($ui.Quality.Value -eq 85 -and $ui.WidthBox.Text -eq '2880' -and $ui.DpiBox.Text -eq '72') 'Profile must restore Makalu dimensions, quality and DPI.'
            foreach ($invalid in @(@('DpiBox','0'), @('WidthBox','invalid'), @('HeightBox','0'))) {
                $box = $ui[$invalid[0]]
                $saved = $box.Text
                $box.Text = $invalid[1]
                $ui.DimensionsExpander.IsExpanded = $false
                [void]$ui.StartButton.Focus()
                Invoke-UiClick $ui.StartButton
                Wait-UiIdle $ui 'invalid custom settings'
                Assert (-not $ui.State.Busy -and $ui.Status.Text -match 'Niepopraw|wartosc|proporcj') 'Invalid custom dimensions or DPI must produce a validation status.'
                if ($invalid[0] -in @('WidthBox','DpiBox')) {
                    Assert ($ui.DimensionsExpander.IsExpanded) ('Invalid ' + $invalid[0] + ' must expand advanced settings.')
                    Assert ($box.IsKeyboardFocused) ('Start with invalid ' + $invalid[0] + ' must focus the offending field.')
                }
                Assert (@(Get-ChildItem -LiteralPath $sourceA -Filter '*_R.jpg' -Recurse).Count -eq 0) 'Invalid settings must not export any photo.'
                $box.Text = $saved
                Wait-UiIdle $ui 'restore valid settings'
            }
            Invoke-UiClick $ui.StartButton
            Assert ($ui.State.Busy) 'Export must start asynchronously and expose Busy before completion.'
            Assert ($ui.Cancel.Visibility -eq 'Visible' -and $ui.Cancel.IsEnabled) 'Busy export must expose an enabled stop command.'
            $window.UpdateLayout()
            $cancelWords = @((Get-VisualNodes $ui.Cancel) | Where-Object { $_ -is [Windows.Controls.TextBlock] -and $_.Text -eq 'Zatrzymaj' })
            Assert ($cancelWords.Count -gt 0) 'Stop command must visibly say Zatrzymaj.'
            Invoke-UiClick $ui.Cancel
            Assert ($ui.State.Cancelling -and -not $ui.Cancel.IsEnabled) 'Immediate cancellation must set Cancelling and disable repeated stop requests.'
            # PropertyChanged updates counts synchronously; it must not re-enable a pending stop action.
            $excluded.IsIncluded = $true
            Assert ($ui.State.Cancelling -and -not $ui.Cancel.IsEnabled) 'Changing inclusion during cancellation must not re-enable Cancel.'
            $excluded.IsIncluded = $false
            Assert ($ui.State.Cancelling -and -not $ui.Cancel.IsEnabled) 'Restoring the subset during cancellation must keep Cancel disabled.'
            Wait-UiIdle $ui 'cancellation'
            Assert ($ui.Status.Text -match '^Zatrzymano') 'Immediate cancellation request must stop the asynchronous batch.'
            $progressValues = New-Object 'Collections.Generic.List[double]'
            $onProgress = { param($sender, $event) $progressValues.Add($event.NewValue) }.GetNewClosure()
            $ui.Progress.Add_ValueChanged($onProgress)
            Invoke-UiClick $ui.StartButton
            Assert ($ui.State.Busy -and -not $ui.State.Cancelling) 'The next export must start without stale cancellation state.'
            Wait-UiIdle $ui 'restart with included subset'
            $ui.Progress.Remove_ValueChanged($onProgress)
            Assert ($ui.Status.Text -match 'zapisano: 2.*bledy: 0') 'Restart must export the two included photos, not just the preview selection.'
            Assert (@($progressValues | Where-Object { $_ -gt 0 -and $_ -lt $ui.Progress.Maximum }).Count -gt 0) 'Processed progress must advance between files, not only at batch completion.'
            Assert-ExportImage (Join-Path $sourceA 'resize\produkt-pion_R.jpg') 1920 2880
            Assert-ExportImage (Join-Path $sourceA 'resize\produkt-poziom_R.jpg') 2880 1920
            Assert (-not (Test-Path -LiteralPath (Join-Path $sourceB 'resize\inne_R.jpg'))) 'Unchecked photo must not be exported.'
            Assert (@(Get-ChildItem -LiteralPath $sourceA -Filter '*_R.jpg' -Recurse).Count -eq 2) 'Subset export must have exactly two generated outputs.'
            Assert ($ui.StartButton.IsEnabled -and $ui.Cancel.Visibility -eq 'Collapsed' -and $ui.OpenOutput.IsEnabled) 'Completion must reset processing controls and enable opening output.'
            $excluded.IsIncluded = $true
            Invoke-ResizerUiEvents
            Assert ($ui.StartCaption.Text -match '3') 'Restoring inclusion must immediately restore export count.'
            Invoke-UiClick $ui.StartButton
            Wait-UiIdle $ui 'all included photos'
            Assert ($ui.Status.Text -match 'zapisano: 3.*bledy: 0') 'Restored inclusion must export all three photos.'
            Assert-ExportImage (Join-Path $sourceB 'resize\inne_R.jpg') 1920 2880
            foreach ($path in $originalHashes.Keys) {
                Assert ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $originalHashes[$path]) ('Original photo changed: ' + $path)
            }
            # Repeated exports retain _R and add a collision counter instead of overwriting earlier results.
            Assert ($ui.OutputFilename.IsReadOnly -and $ui.OutputFilename.Text -match '_R(?:_\d+)?\.jpg$') 'Generated name example must preserve uneditable _R suffix with an optional collision counter.'
            Assert ($ui.OutputExample.IsReadOnly -and [IO.Path]::IsPathRooted($ui.OutputExample.Text) -and (Test-Path -LiteralPath $ui.OutputExample.Text -PathType Leaf)) 'Selectable output example must expose the full path to an actual exported file.'
            Invoke-UiClick $ui.UpdatesButton
            Assert ($ui.UpdateOverlay.Visibility -eq 'Visible') 'Updates overlay must open.'
            Assert (-not $ui.MainLayout.IsEnabled) 'Updates modal must disable the underlying main view.'
            Invoke-ResizerUiEvents
            Assert ($ui.CheckUpdate.IsKeyboardFocused) 'Opening updates must focus its check command.'
            $installed = [pscustomobject]@{repository=$metadata.repository;version='2.1.0';releaseAsset=$metadata.releaseAsset}
            $priorStable = [pscustomobject]@{draft=$false;prerelease=$false;tag_name='v2.0.0';assets=@()}
            $comparison = Get-ResizerRelease -Metadata $installed -Release $priorStable
            Assert (-not $comparison.Available -and $comparison.Status -eq 'Current') 'Installed 2.1.0 must count as current against previously published stable 2.0.0.'
            if ($LiveUpdates) {
                Invoke-UiClick $ui.CheckUpdate
                $deadline = [DateTime]::UtcNow.AddSeconds(30)
                while ($ui.UpdateProgress.Visibility -eq 'Visible' -and [DateTime]::UtcNow -lt $deadline) {
                    Invoke-ResizerUiEvents
                    Start-Sleep -Milliseconds 20
                }
                Assert ($ui.UpdateProgress.Visibility -ne 'Visible') 'Live update check must complete before its deadline.'
                Assert ($ui.UpdateStatus.Text -eq 'Masz aktualna wersje programu.') 'Live update check must treat installed version equal to or newer than stable as current.'
                Write-Host 'PASS: live asynchronous stable release comparison (no publication or install).'
            }
            Invoke-UiClick $ui.CloseUpdates
            Assert ($ui.UpdateOverlay.Visibility -eq 'Collapsed') 'Updates overlay must close.'
            Assert ($ui.MainLayout.IsEnabled -and $ui.UpdatesButton.IsKeyboardFocused) 'Closing updates must re-enable the main view and restore trigger focus.'
            Invoke-UiClick $ui.UpdatesButton
            Invoke-UiEscape $window
            Assert ($ui.UpdateOverlay.Visibility -eq 'Collapsed' -and $ui.MainLayout.IsEnabled -and $ui.UpdatesButton.IsKeyboardFocused) 'Escape must close updates and restore main view focus.'
            Invoke-UiClick $ui.LogButton
            Assert ($ui.LogOverlay.Visibility -eq 'Visible') 'Log overlay must open.'
            Assert (-not $ui.MainLayout.IsEnabled) 'Log modal must disable the underlying main view.'
            Invoke-ResizerUiEvents
            Assert ($ui.CloseLog.IsKeyboardFocused) 'Opening the log must focus its close command.'
            Invoke-UiClick $ui.CloseLog
            Assert ($ui.LogOverlay.Visibility -eq 'Collapsed') 'Log overlay must close.'
            Assert ($ui.MainLayout.IsEnabled -and $ui.LogButton.IsKeyboardFocused) 'Closing the log must re-enable the main view and restore trigger focus.'
            Invoke-UiClick $ui.LogButton
            Invoke-UiEscape $window
            Assert ($ui.LogOverlay.Visibility -eq 'Collapsed' -and $ui.MainLayout.IsEnabled -and $ui.LogButton.IsKeyboardFocused) 'Escape must close the log and restore main view focus.'
            $ui.Sources.SelectedItem = $portrait
            $ui.Before.IsChecked = $true
            Wait-UiIdle $ui 'render fixture preview'
            Save-UiRender $window 1440 1024 'Resizer-v2.png'
            Save-UiRender $window 1000 680 'Resizer-v2-compact.png'
            # Fitted 100 percent must be recalculated when the window shrinks, including image margins.
            Assert ($ui.Zoom.Value -eq 100) 'Compact render must remain at fitted 100 percent.'
            Assert ($ui.Preview.Width + 24 -le $ui.PreviewScroll.ViewportWidth + 1) ('Compact fitted preview exceeds viewport width: image+margin={0}; viewport={1}.' -f ($ui.Preview.Width + 24), $ui.PreviewScroll.ViewportWidth)
            Assert ($ui.Preview.Height + 24 -le $ui.PreviewScroll.ViewportHeight + 1) ('Compact fitted preview exceeds viewport height: image+margin={0}; viewport={1}.' -f ($ui.Preview.Height + 24), $ui.PreviewScroll.ViewportHeight)
            Assert ($ui.PreviewScroll.ScrollableWidth -le 1 -and $ui.PreviewScroll.ScrollableHeight -le 1) ('Compact fitted preview must not scroll at 100 percent: width={0}; height={1}.' -f $ui.PreviewScroll.ScrollableWidth, $ui.PreviewScroll.ScrollableHeight)
            $ui.Sources.SelectedItem = $excluded
            Wait-UiIdle $ui 'remove photo selection'
            Invoke-UiClick $ui.RemoveSource
            Wait-UiIdle $ui 'remove individual photo'
            Assert ($ui.QueueItems.Count -eq 2 -and $ui.Filmstrip.Items.Count -eq 2) 'RemoveSource must remove one photo, not its whole source folder.'
            & $ui.AddSources @($excluded.FullPath)
            Wait-UiIdle $ui 're-add removed photo'
            Assert ($ui.QueueItems.Count -eq 3 -and @($ui.QueueItems | Where-Object FullPath -eq $excluded.FullPath).Count -eq 1) 'An explicitly re-added photo must not remain excluded by removal history.'
            Invoke-UiClick $ui.ClearSources
            Wait-UiIdle $ui 'clear photo queue'
            Assert ($ui.QueueItems.Count -eq 0 -and $ui.Sources.Items.Count -eq 0 -and $ui.Filmstrip.Items.Count -eq 0) 'ClearSources must clear both queue views.'
            Assert ($ui.EmptyPreview.Visibility -eq 'Visible' -and -not $ui.StartButton.IsEnabled) 'Empty queue must restore empty preview and disable export.'
            Write-Host 'PASS: photo queue, groups, thumbnails, tri-state inclusion, native preview, navigation, zoom, drop, validation, asynchronous cancellation/restart, original-safe export, overlays and two renders.'
        } catch {
            $script:uiFailure = $_.ToString() + "`n" + $_.ScriptStackTrace
        } finally {
            # Allow asynchronous workers to finish before closing their window.
            if ($ui.ContainsKey('State')) {
                if ($ui.State.Busy) { Invoke-UiClick $ui.Cancel }
                try { Wait-UiIdle $ui 'safe window close' } catch {
                    if (-not $script:uiFailure) { $script:uiFailure = $_.ToString() }
                }
            }
            $window.Close()
        }
    }
    if ($script:uiFailure) { throw $script:uiFailure }
} finally {
    $full = [IO.Path]::GetFullPath($fixture)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\resizer-wpf-test-'
    if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $full -Recurse -Force }
}
