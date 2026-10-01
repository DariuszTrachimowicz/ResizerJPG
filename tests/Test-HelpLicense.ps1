# Copyright (c) 2026 Dariusz Trachimowicz / Digital Xperts
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSE for terms. Distributed WITHOUT ANY WARRANTY.
param([string]$RenderDirectory = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Run with Windows PowerShell 5.1 -STA.' }
$root = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
function Assert($condition, [string]$message) { if (-not $condition) { throw $message } }
function Click($button) { $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) }

# Contract failures are collected so RED identifies all absent entry points.
[xml]$xml = Get-Content -LiteralPath (Join-Path $root 'ResizerWindow.xaml') -Raw
$reader = New-Object Xml.XmlNodeReader($xml)
try { $contract = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
$failures = @()
foreach ($name in @('HelpButton','HelpIcon','LicenseLink','CopyrightFooter')) {
    if ($null -eq $contract.FindName($name)) { $failures += "Missing help/license control: $name" }
}
if ((Get-FileHash -LiteralPath (Join-Path $root 'LICENSE') -Algorithm SHA256).Hash -ne 'FB981668C18A279E285FC4D83FBA1E836CC84DD4DAA73C9697D3CFD2D8ACA6E0') {
    $failures += 'LICENSE must be the exact upstream GPL-3.0-only text.'
}
. (Join-Path $root 'ResizerUI.ps1')
if (-not (Get-Command Show-ResizerWindow).Parameters.ContainsKey('DocumentOpener')) { $failures += 'Missing injectable local document command.' }
Assert ($failures.Count -eq 0) ($failures -join "`n")
$info = Get-ResizerAppInfo
Assert ($info.version -match '^\d+\.\d+\.\d+$' -and [version]$info.version -ge [version]'2.2.0' -and $info.license -eq 'GPL-3.0-only') 'Release metadata must identify a valid current app version and GPL-3.0-only.'
Assert (@(Get-ResizerManagedFiles).Count -eq 15) 'Existing 15 managed files plus manifest must keep the 16-entry archive contract.'

# Load engine definitions without invoking the application entry point.
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ResizerJPG.ps1'),[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0) 'Engine must parse.'
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) { . ([scriptblock]::Create($statement.Extent.Text)) }
}
function Bounds($control, $surface) {
    $p = $control.TranslatePoint([Windows.Point]::new(0,0),$surface)
    return [Windows.Rect]::new($p.X,$p.Y,$control.ActualWidth,$control.ActualHeight)
}
$script:failure = $null
$script:documents = New-Object 'Collections.Generic.List[string]'
$script:throwOpener = $false
Show-ResizerWindow -DocumentOpener {
    param($path)
    if ($script:throwOpener) { throw 'Test document launch failure' }
    $script:documents.Add($path)
} -OnShown {
    param($window)
    try {
        $ui = $window.Tag
        # Photo roots must never influence document resolution.
        $ui.State.Paths.Add('C:\Photos & unrelated source')
        foreach ($pair in @(@('HelpButton','README.md'),@('LicenseLink','LICENSE'))) {
            $button = $ui[$pair[0]]
            Assert ($button.IsTabStop -and $button.Focusable -and $button.ToolTip -and [Windows.Automation.AutomationProperties]::GetName($button)) "$($pair[0]) needs accessible name, tooltip and keyboard focus."
            [void]$button.Focus(); Invoke-ResizerUiEvents
            Assert ($button.IsKeyboardFocused) "$($pair[0]) must accept keyboard focus."
            Click $button
            Assert ($script:documents[$script:documents.Count-1] -ceq (Join-Path $root $pair[1])) "$($pair[0]) must open the exact application document."
        }
        Assert ($script:documents.Count -eq 2) 'Each command must open only one document.'
        $script:throwOpener = $true
        Click $ui.HelpButton
        Assert ($ui.Status.Text -match 'Test document launch failure') 'Opener exceptions must reach readable status without crashing the dispatcher.'
        $script:throwOpener = $false
        Click $ui.LicenseLink
        Assert ($script:documents.Count -eq 3) 'Commands must still work after a failed launch.'
        Assert ($ui.LicenseLink.Content -match 'GPLv3' -and $ui.LicenseLink.Content -match 'gwarancji') 'Footer must show GPLv3 and no warranty.'
        Assert ($ui.CopyrightFooter.Text -match '2026.*Dariusz Trachimowicz.*Digital Xperts') 'Copyright must remain visible.'
        $helpGeometry = $ui.HelpIcon.Content.Child.Children[0].Data
        Assert ($helpGeometry.Bounds.Width -ge 20 -and $helpGeometry.Bounds.Height -ge 20) 'Help icon must include its question circle.'
        $ui.UpdatesCaption.Text = 'Nowa wersja ' + $info.version
        foreach ($size in @(@(1000,680),@(1440,1024))) {
            $window.Width = $size[0]; $window.Height = $size[1]
            Invoke-ResizerUiEvents; $window.UpdateLayout()
            $surface = $window.Content
            foreach ($band in @(@('BrandLink','HeaderTitle','SettingsButton','UpdatesButton','HelpButton'),@('CopyrightFooter','LicenseLink','VersionFooter'))) {
                $previous = $null
                foreach ($name in $band) {
                    $control = $ui[$name]; $b = Bounds $control $surface
                    Assert ($control.IsVisible -and $b.Width -gt 0 -and $b.Height -gt 0 -and $b.Left -ge 0 -and $b.Top -ge 0 -and $b.Right -le ($surface.ActualWidth+0.5) -and $b.Bottom -le ($surface.ActualHeight+0.5)) "$name clips at $($size -join 'x')."
                    Assert ($null -eq $previous -or $b.Left -ge $previous.Right) "$name overlaps its neighbor at $($size -join 'x')."
                    Assert ($control.DesiredSize.Width -le ($control.ActualWidth+$control.Margin.Left+$control.Margin.Right+0.5)) "$name is internally clipped."
                    $previous = $b
                }
            }
            Assert ($ui.MainLayout.RowDefinitions[3].ActualHeight -eq 28) 'Credits must retain their 28px band.'
            Assert ($ui.LicenseLink.ActualHeight -le 28) 'License button must fit the credits band.'
            if ($RenderDirectory) {
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($RenderDirectory))
                $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$surface.ActualWidth,[int]$surface.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($surface)
                $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                $stream = [IO.File]::Create((Join-Path $RenderDirectory ('help-{0}x{1}.png' -f $size[0],$size[1])))
                try { $encoder.Save($stream) } finally { $stream.Dispose() }
            }
        }
    } catch { $script:failure = $_ } finally { $window.Close() }
}
if ($script:failure) { throw $script:failure }
Write-Host 'PASS: exact local routes, accessible commands, callback failure recovery and compact/desktop bounds.'

# A fresh application fixture intentionally has no documents: no source files are deleted.
$fixture = Join-Path $root ('work\help fixture & spaces ' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
foreach ($name in @('ResizerUI.ps1','ResizerUpdates.ps1','ResizerUIModels.ps1','ResizerQueue.ps1','ResizerWindow.xaml','AppInfo.json','lucide-paths.json','digital-xperts-logo.png','resizer-jpg.ico')) {
    Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $fixture $name)
}
. (Join-Path $fixture 'ResizerUI.ps1')
Show-ResizerWindow -DocumentOpener { throw 'Missing documents must not reach the opener' } -OnShown {
    param($window)
    try {
        foreach ($pair in @(@('HelpButton','README.md'),@('LicenseLink','LICENSE'))) {
            Click $window.Tag[$pair[0]]
            Assert ($window.Tag.Status.Text -like ('*Brak pliku*'+$pair[1]+'*')) 'Missing documents need a readable filename error.'
        }
    } catch { $script:failure = $_ } finally { $window.Close() }
}
if ($script:failure) { throw $script:failure }

# Intercept only the process boundary: exercise the real default opener safely.
foreach ($name in @('README.md','LICENSE')) { Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $fixture $name) }
$script:launches = New-Object 'Collections.Generic.List[object]'
$script:throwLaunch = $false
function Start-Process {
    [CmdletBinding()]param([string]$FilePath,[string[]]$ArgumentList,[switch]$Wait)
    if ($script:throwLaunch) { throw 'Test Notepad failure' }
    $script:launches.Add(@{FilePath=$FilePath;Arguments=$ArgumentList;Wait=[bool]$Wait})
}
Show-ResizerWindow -OnShown {
    param($window)
    try {
        foreach ($pair in @(@('HelpButton','README.md'),@('LicenseLink','LICENSE'))) {
            Click $window.Tag[$pair[0]]
            $launch = $script:launches[$script:launches.Count-1]
            Assert ($launch.FilePath -ceq (Join-Path $env:SystemRoot 'System32\notepad.exe')) 'Default opener must use trusted Notepad.'
            Assert ($launch.Arguments.Count -eq 1 -and $launch.Arguments[0] -ceq ('"'+(Join-Path $fixture $pair[1])+'"')) 'Notepad must receive one quoted exact path, including spaces and shell metacharacters.'
            Assert (-not $launch.Wait) 'Document launch must not wait for the editor.'
        }
        Assert ($script:launches.Count -eq 2) 'Default commands must launch once each.'
        $script:throwLaunch = $true
        Click $window.Tag.LicenseLink
        Assert ($window.Tag.Status.Text -match 'Test Notepad failure') 'Default launch errors must not escape the dispatcher.'
    } catch { $script:failure = $_ } finally { $window.Close() }
}
if ($script:failure) { throw $script:failure }
Write-Host 'PASS: missing-file handling, trusted non-waiting Notepad arguments, launch errors, GPL hash and 16-entry contract.'
