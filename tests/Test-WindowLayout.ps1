param([string]$ProgramFolder = '', [string]$RenderDirectory = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Run this test with Windows PowerShell 5.1 -STA.' }
$root = if ($ProgramFolder) { [IO.Path]::GetFullPath($ProgramFolder) } else { Split-Path -Parent $PSScriptRoot }
[xml]$xml = Get-Content -LiteralPath (Join-Path $root 'ResizerWindow.xaml') -Raw
$ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('w', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
$ns.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
function Assert($condition, [string]$message) { if (-not $condition) { throw $message } }
function Named([string]$name) { return $xml.SelectSingleNode("//*[@x:Name='$name']", $ns) }

# These are the event/binding boundary owned by ResizerUI, not template-local names.
$required = @(
    'MainLayout','QueueColumn','InspectorColumn','Sources','SourceCount','SelectAll','Before','After','Preview','PreviewSurface','PreviewScroll',
    'EmptyPreview','EmptyText','DropHighlight','Profile','PortraitSize','LandscapeSize','Ratio','Preset',
    'WidthBox','HeightBox','DpiBox','Quality','QualityNumber','Mode','FitPad','FitCrop',
    'DimensionsExpander','Settings','BrandLink','BrandLogo','UpdatesButton','UpdatesCaption',
    'VersionFooter','InstalledVersion','RepositoryLink','UpdateOverlay','CheckUpdate','InstallUpdate',
    'CloseUpdates','AutoUpdate','UpdateStatus','UpdateProgress','LogOverlay','Log','LogButton','CloseLog',
    'AddFolder','AddFiles','RemoveSource','ClearSources','Recursive','Output','ChooseOutput','DefaultOutput',
    'OutputExample','OutputFilename','SelectionCount','StartButton','StartCaption','Cancel','OpenOutput',
    'Status','Progress','PhotoName','PhotoDimensions','PreviewTitle','PrevPhoto','NextPhoto','PhotoCounter',
    'Filmstrip','ZoomToolbar','Zoom','ZoomCaption','ZoomIn','ZoomOut','FitView','SettingsButton',
    'FolderPlusIcon','ImagesIcon','TrashIcon','PrevIcon','NextIcon','EmptyImageIcon','OutputFolderIcon',
    'ResetIcon','PlayIcon','StopIcon','UpdatesIcon','CloseUpdatesIcon','CloseLogIcon',
    'SettingsIcon','ZoomInIcon','ZoomOutIcon','FitIcon','PadIcon','CropIcon'
)
foreach ($name in $required) { Assert ($null -ne (Named $name)) "Missing required WPF control: $name" }
Assert ($xml.DocumentElement.GetAttribute('MinWidth') -eq '1000' -and $xml.DocumentElement.GetAttribute('MinHeight') -eq '680') 'Window must retain the 1000 x 680 minimum.'
Assert ($xml.DocumentElement.GetAttribute('FontSize') -eq '14') 'Operational text must use a readable 14px base.'
$layout = Named 'MainLayout'
$rows = $layout.SelectNodes('w:Grid.RowDefinitions/w:RowDefinition', $ns)
Assert ($rows.Count -eq 4 -and $rows[0].Height -eq '76' -and $rows[2].Height -eq '100' -and $rows[3].Height -eq '28') 'Header, operational footer and credits must remain separate fixed-height bands.'
$columns = $layout.SelectNodes('w:Grid.ColumnDefinitions/w:ColumnDefinition', $ns)
Assert ($columns.Count -eq 3 -and $columns[0].Width -eq '360' -and $columns[1].Width -eq '*' -and $columns[2].Width -eq '304') 'Desktop pane contract must be 360 / fluid / 304.'
Assert ($columns[0].MinWidth -eq '280' -and $columns[1].MinWidth -eq '320' -and $columns[2].MinWidth -eq '280') 'Compact panes must not squeeze queue/inspector below 280 or preview below 320.'
Assert ((Named 'SelectAll').IsThreeState -eq 'True') 'SelectAll must represent partial inclusion.'
Assert ((Named 'PreviewScroll').GetAttribute('HorizontalScrollBarVisibility') -eq 'Auto' -and (Named 'PreviewScroll').GetAttribute('VerticalScrollBarVisibility') -eq 'Auto') 'Zoomed preview must pan in both axes.'
Assert ((Named 'Preview').Stretch -eq 'Uniform' -and $null -eq (Named 'Preview').SelectSingleNode('w:Image.LayoutTransform|w:Image.RenderTransform', $ns)) 'Preview dimensions are owned by the fit/zoom handler, not a hardcoded image transform.'
$sources = Named 'Sources'
$toggle = $sources.SelectSingleNode('.//w:DataTemplate//w:CheckBox[@Tag="PhotoToggle"]', $ns)
Assert ($null -ne $toggle -and $toggle.IsChecked -match 'Binding IsIncluded' -and $toggle.IsChecked -match 'Mode=TwoWay') 'Every photo must expose an independent two-way inclusion checkbox.'
Assert ($null -ne $sources.SelectSingleNode('.//w:Image[@Source="{Binding Thumbnail}"]', $ns)) 'Queue must show individual photo thumbnails.'
Assert ($null -ne $sources.SelectSingleNode('.//w:GroupStyle/w:GroupStyle.HeaderTemplate//w:TextBlock[@Text="{Binding Items[0].SourceName}"]', $ns)) 'Folder group header must use the friendly SourceName.'
Assert ($null -ne $sources.SelectSingleNode('.//w:GroupStyle.HeaderTemplate//w:Run[@Text="{Binding ItemCount, Mode=OneWay}"]', $ns)) 'Folder group header must safely display the read-only photo count.'
Assert ($null -ne $sources.SelectSingleNode('.//w:GroupStyle.ContainerStyle//w:Expander', $ns)) 'Folder groups must be collapsible without a nested tree.'
Assert ($null -ne (Named 'Filmstrip').SelectSingleNode('.//w:StackPanel[@Orientation="Horizontal"]', $ns)) 'Filmstrip must scroll horizontally.'
Assert ((Named 'Mode').Visibility -eq 'Collapsed' -and (Named 'Mode').SelectedIndex -eq '0') 'Compatibility Mode must stay hidden and default to Pad.'
Assert ((Named 'FitPad').IsChecked -eq 'True' -and (Named 'FitPad').GroupName -eq (Named 'FitCrop').GroupName) 'Fit segments must default to whole photo.'
foreach ($name in @('Output','OutputFilename')) { Assert ((Named $name).IsReadOnly -eq 'True') "$name must preserve safe, uneditable output naming." }
Assert ((Named 'OutputFilename').Text -match '_R\.jpg$') 'Output filename example must preserve the _R suffix.'
Assert ((Named 'Cancel').Visibility -eq 'Collapsed' -and $null -ne (Named 'Cancel').SelectSingleNode('.//w:TextBlock[@Text="Zatrzymaj"]', $ns)) 'Stop must be collapsed initially and have a visible word label when active.'
Assert ((Named 'Zoom').Minimum -eq '100' -and (Named 'Zoom').Maximum -eq '400') 'Zoom must be fit-relative 100 to 400 percent.'
foreach ($name in @('WidthBox','HeightBox','DpiBox','Preset')) {
    Assert ($null -ne (Named $name).SelectSingleNode('ancestor::w:Expander[@x:Name="DimensionsExpander"]', $ns)) "$name must remain in advanced settings."
}
foreach ($target in @('Button','RadioButton','ComboBox','CheckBox','TextBox','Slider')) {
    $style = $xml.SelectSingleNode("//w:Window.Resources/w:Style[@TargetType='$target']", $ns)
    Assert ($null -ne $style) "$target must have a shared accessible style."
    $height = $style.SelectSingleNode('w:Setter[@Property="MinHeight"]', $ns)
    Assert ($null -ne $height -and [double]$height.Value -ge 36) "$target targets must be at least 36px."
    Assert ($null -ne $style.SelectSingleNode('.//w:Trigger[@Property="IsEnabled" and @Value="False"]', $ns)) "$target must show disabled state."
    Assert ($null -ne $style.SelectSingleNode('.//w:Trigger[@Property="IsKeyboardFocused" or @Property="IsKeyboardFocusWithin"]', $ns)) "$target must show keyboard focus."
}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$reader = New-Object Xml.XmlNodeReader($xml)
try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
try {
    foreach ($name in $required) { Assert ($null -ne $window.FindName($name)) "XamlReader cannot resolve required name: $name" }
    Assert ($window.FindName('Sources') -is [Windows.Controls.ListBox]) 'Sources must stay a ListBox.'
    Assert ($window.FindName('PreviewSurface') -is [Windows.Controls.Grid]) 'PreviewSurface must remain a Grid for viewport measurement.'
    Assert ($window.FindName('PreviewScroll') -is [Windows.Controls.ScrollViewer]) 'PreviewScroll must support panning the zoomed image.'
    Assert ($window.FindName('Settings') -is [Windows.Controls.StackPanel]) 'Settings must remain the main editable StackPanel.'
    $table = New-Object Data.DataTable
    foreach ($field in @('Name','SourceName','SourceRoot','FullPath','Details','Orientation')) { [void]$table.Columns.Add($field, [string]) }
    [void]$table.Columns.Add('IsIncluded', [bool])
    [void]$table.Columns.Add('Thumbnail', [object])
    $photoPath = Join-Path $PSScriptRoot 'Preview-photo.png'
    $thumbnail = $null
    if (Test-Path -LiteralPath $photoPath) {
        $thumbnail = New-Object Windows.Media.Imaging.BitmapImage
        $thumbnail.BeginInit(); $thumbnail.CacheOption = 'OnLoad'; $thumbnail.UriSource = New-Object Uri($photoPath); $thumbnail.EndInit(); $thumbnail.Freeze()
    }
    foreach ($index in 1..10) {
        $row = $table.NewRow()
        $row.Name = 'MAK_{0:0000}.jpg' -f (1041+$index)
        $row.SourceName = if ($index -le 6) { 'Kolekcja jesien' } else { 'Nowe produkty' }
        $row.SourceRoot = if ($index -le 6) { 'C:\Photos\A' } else { 'C:\Photos\B' }
        $row.FullPath = $row.SourceRoot + '\' + $row.Name
        $row.Details = '1920 x 2880 px'; $row.Orientation = 'Pion'; $row.IsIncluded = $true
        if ($null -ne $thumbnail) { $row['Thumbnail'] = $thumbnail.PSObject.BaseObject }
        $table.Rows.Add($row)
    }
    $view = [Windows.Data.ListCollectionView]::new($table.DefaultView)
    [void]$view.GroupDescriptions.Add((New-Object Windows.Data.PropertyGroupDescription('SourceRoot')))
    $window.FindName('Sources').ItemsSource = $view
    $window.FindName('Sources').SelectedIndex = 0
    $window.FindName('Filmstrip').ItemsSource = $table.DefaultView
    $window.FindName('Filmstrip').SelectedIndex = 0
    $window.FindName('SelectAll').IsChecked = $true
    $window.FindName('SourceCount').Text = '10 zdjec / 2 foldery'
    $window.FindName('SelectionCount').Text = '10 z 10'
    $window.FindName('StartCaption').Text = 'Eksportuj 10 zdjec'
    $window.FindName('PhotoName').Text = 'MAK_1042.jpg'
    $window.FindName('PhotoDimensions').Text = '1920 x 2880 px | JPG 85 | 72 DPI'
    $window.FindName('PreviewTitle').Text = 'MAK_1042.jpg'
    $window.FindName('ZoomCaption').Text = '400% widoku'
    $window.FindName('PhotoCounter').Text = '1 / 10'
    $window.FindName('Preview').Source = $thumbnail
    $window.FindName('EmptyPreview').Visibility = 'Collapsed'
    $window.FindName('Preset').Items.Add('2880 x 1920') | Out-Null
    $window.FindName('Preset').SelectedIndex = 0
    $logo = New-Object Windows.Media.Imaging.BitmapImage
    $logo.BeginInit(); $logo.CacheOption = 'OnLoad'; $logo.UriSource = New-Object Uri((Join-Path $root 'digital-xperts-logo.png')); $logo.EndInit(); $logo.Freeze()
    $window.FindName('BrandLogo').Source = $logo
    $content = $window.Content
    $window.FindName('DimensionsExpander').IsExpanded = $true
    foreach ($size in @(@(1440,1024,360,304),@(1000,680,280,280))) {
        $window.Width = $size[0]; $window.Height = $size[1]
        $main = $window.FindName('MainLayout')
        # Main agent owns the SizeChanged handler; simulate its compact widths only.
        $main.ColumnDefinitions[0].Width = New-Object Windows.GridLength($size[2])
        $main.ColumnDefinitions[2].Width = New-Object Windows.GridLength($size[3])
        $viewport = New-Object Windows.Size(($size[0]-16),($size[1]-39))
        $content.Measure($viewport)
        $content.Arrange((New-Object Windows.Rect(0,0,$viewport.Width,$viewport.Height)))
        $content.UpdateLayout()
        $surface = $window.FindName('PreviewSurface')
        $window.FindName('Preview').Width = [Math]::Max(1, $surface.ActualWidth-24)
        $window.FindName('Preview').Height = [Math]::Max(1, $surface.ActualHeight-24)
        $content.UpdateLayout()
        foreach ($name in @('StartButton','StartCaption','Output','OutputFilename','SelectionCount','Status','AddFolder','AddFiles','SelectAll','Before','After','ZoomIn','ZoomOut','FitView','Profile','Ratio','FitPad','FitCrop','LogButton','OpenOutput')) {
            $control = $window.FindName($name)
            Assert ($control.Visibility -eq 'Visible' -and $control.ActualWidth -gt 0 -and $control.ActualHeight -gt 0) "$name must remain laid out at $($size[0]) x $($size[1])."
            $point = $control.TranslatePoint((New-Object Windows.Point(0,0)), $content)
            Assert ($point.X -ge -0.5 -and $point.Y -ge -0.5 -and ($point.X+$control.ActualWidth) -le ($viewport.Width+0.5) -and ($point.Y+$control.ActualHeight) -le ($viewport.Height+0.5)) "$name clips outside the viewport at $($size[0]) x $($size[1])."
        }
        $button = $window.FindName('StartButton')
        Assert ($button.ActualHeight -ge 36 -and $button.ActualWidth -ge 160) 'Export action must not disappear into a scrollable settings panel.'
        $caption = $window.FindName('StartCaption')
        Assert ($caption.ActualWidth -ge 110) 'Export action must leave room for its Polish count caption.'
        foreach ($name in @('Output','OutputFilename')) {
            $textInput = $window.FindName($name)
            $hostView = $textInput.Template.FindName('PART_ContentHost', $textInput)
            Assert ($hostView.ViewportHeight -ge ($textInput.FontSize*1.3)) "$name clips its text line inside the input template."
        }
        foreach ($name in @('AddFolder','AddFiles','FitPad','FitCrop')) {
            $control = $window.FindName($name)
            $inner = $control.Content
            Assert (($inner.DesiredSize.Width+$control.Padding.Left+$control.Padding.Right+2) -le ($control.ActualWidth+0.5)) "$name clips its icon/Polish label in the compact pane."
        }
        $zoomLabel = $window.FindName('ZoomCaption')
        $labelSize = New-Object Windows.Media.FormattedText($zoomLabel.Text,[Globalization.CultureInfo]::InvariantCulture,[Windows.FlowDirection]::LeftToRight,([Windows.Media.Typeface]::new($zoomLabel.FontFamily,$zoomLabel.FontStyle,$zoomLabel.FontWeight,$zoomLabel.FontStretch)),$zoomLabel.FontSize,$zoomLabel.Foreground)
        Assert ($labelSize.Width -le $zoomLabel.ActualWidth) 'Zoom caption must not overlap neighboring icon buttons.'
        Assert ($null -ne $window.FindName('Sources').ItemContainerGenerator.ContainerFromIndex(0)) 'Grouped queue must actually generate photo rows.'
        if ($RenderDirectory) {
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($RenderDirectory))
            $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$viewport.Width,[int]$viewport.Height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
            $bitmap.Render($content)
            $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
            $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $path = Join-Path $RenderDirectory ('layout-{0}x{1}.png' -f $size[0],$size[1])
            $stream = [IO.File]::Create($path)
            try { $encoder.Save($stream) } finally { $stream.Dispose() }
            Write-Host ('RENDER: ' + $path)
        }
    }
    Write-Host 'PASS: XAML contract, photo bindings/groups, safe output, accessible templates, STA loading and footer visibility at 1440x1024 / 1000x680.'
} finally { $window.Close() }
