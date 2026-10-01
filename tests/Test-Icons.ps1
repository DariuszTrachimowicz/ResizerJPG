# Copyright (c) 2026 Dariusz Trachimowicz / Digital Xperts
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSE for terms. Distributed WITHOUT ANY WARRANTY.
param([string]$PathsJson = '', [switch]$CheckDialogs)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Run with Windows PowerShell 5.1 -STA.' }
$root = Split-Path -Parent $PSScriptRoot
if (-not $PathsJson) { $PathsJson = Join-Path $root 'lucide-paths.json' }
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$icons = Get-Content -LiteralPath $PathsJson -Raw | ConvertFrom-Json
function Assert($condition, [string]$message) { if (-not $condition) { throw $message } }

function Render-Icon([Windows.Media.Geometry]$Geometry) {
    # Match the production Canvas/Path, including stroke and round caps.
    $canvas = New-Object Windows.Controls.Canvas
    $canvas.Width = 24; $canvas.Height = 24
    $path = New-Object Windows.Shapes.Path
    $path.Data = $Geometry; $path.Stroke = [Windows.Media.Brushes]::Black
    $path.StrokeThickness = 1.7
    $path.StrokeStartLineCap = 'Round'; $path.StrokeEndLineCap = 'Round'; $path.StrokeLineJoin = 'Round'
    [void]$canvas.Children.Add($path)
    $canvas.Measure([Windows.Size]::new(24,24))
    $canvas.Arrange([Windows.Rect]::new(0,0,24,24)); $canvas.UpdateLayout()
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(96,96,384,384,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($canvas)
    $pixels = New-Object byte[] (96*96*4)
    $bitmap.CopyPixels($pixels,96*4,0)
    return ,$pixels
}

# Hand-derived coordinates from the independent SVG elements. Explicit L/l
# preserves the repeated relative pairs after the initial moveto (not M pairs).
# Rectangle corner rounding is existing converter behavior, outside this repair.
$expected = [ordered]@{
    'x' = 'M18 6 L6 18 M6 6 L18 18'
    'download' = 'M12 15 V3 M21 15 v4 a2 2 0 0 1-2 2 H5 a2 2 0 0 1-2-2 v-4 M7 10 L12 15 L17 10'
    'image' = 'M3 3 H21 V21 H3 Z M7 9 A2 2 0 1 0 11 9 A2 2 0 1 0 7 9 M21 15 l-3.086-3.086 a2 2 0 0 0-2.828 0 L6 21'
    'chevron-left' = 'M15 18 L9 12 L15 6'
    'chevron-right' = 'M9 18 L15 12 L9 6'
}
$pen = [Windows.Media.Pen]::new([Windows.Media.Brushes]::Black,1.7)
$pen.StartLineCap = 'Round'; $pen.EndLineCap = 'Round'; $pen.LineJoin = 'Round'
$failures = @()
foreach ($name in $expected.Keys) {
    $actualGeometry = [Windows.Media.Geometry]::Parse($icons.$name)
    $bounds = $actualGeometry.GetRenderBounds($pen)
    if ($bounds.Left -lt 0 -or $bounds.Top -lt 0 -or $bounds.Right -gt 24 -or $bounds.Bottom -gt 24) {
        $failures += "$name stroke escapes 24-unit viewBox: $bounds"
    }
    $actual = Render-Icon $actualGeometry
    $reference = Render-Icon ([Windows.Media.Geometry]::Parse($expected[$name]))
    if ([Convert]::ToBase64String($actual) -cne [Convert]::ToBase64String($reference)) {
        $failures += "$name rendered pixels differ from independent SVG coordinates"
    }
    if ($name -eq 'x') {
        foreach ($point in @(@(6,6),@(18,18),@(18,6),@(6,18),@(12,12))) {
            $alpha = $actual[(($point[1]*4)*96 + $point[0]*4)*4 + 3]
            if ($alpha -eq 0) { $failures += "x missing endpoint/intersection pixel at $($point -join ',')" }
        }
    }
}
Assert ($failures.Count -eq 0) ($failures -join "`n")
Write-Host 'PASS: five WPF pixel references, stroke bounds, X endpoints and intersection.'

if ($CheckDialogs) {
    Assert ([IO.Path]::GetFullPath($PathsJson) -eq (Join-Path $root 'lucide-paths.json')) 'Dialog check uses the checkout JSON.'
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ResizerJPG.ps1'),[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) 'ResizerJPG.ps1 must parse.'
    foreach ($statement in $ast.EndBlock.Statements) {
        if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) { . ([scriptblock]::Create($statement.Extent.Text)) }
    }
    . (Join-Path $root 'ResizerUI.ps1')
    function Click($button) { $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) }
    $script:dialogFailure = $null
    # OnShown suppresses the normal automatic network update check.
    Show-ResizerWindow -OnShown {
        param($window)
        try {
            $ui = $window.Tag
            foreach ($kind in @('Updates','Log')) {
                $trigger = $ui[($kind + 'Button')]
                $close = $ui[('Close' + $kind)]
                $overlay = if ($kind -eq 'Updates') { $ui.UpdateOverlay } else { $ui.LogOverlay }
                foreach ($method in @('Click','Escape')) {
                    Click $trigger
                    Invoke-ResizerUiEvents
                    Assert ($overlay.Visibility -eq 'Visible' -and -not $ui.MainLayout.IsEnabled) "$kind must open as a modal."
                    $focus = if ($kind -eq 'Updates') { $ui.CheckUpdate } else { $close }
                    Assert ($focus.IsKeyboardFocused) "$kind must focus its initial command."
                    $icon = $ui[('Close' + $kind + 'Icon')].Content.Child.Children[0]
                    $pixels = Render-Icon $icon.Data
                    Assert ([Convert]::ToBase64String($pixels) -ceq [Convert]::ToBase64String((Render-Icon ([Windows.Media.Geometry]::Parse($expected['x']))))) "$kind must bind the complete X."
                    if ($method -eq 'Click') { Click $close } else {
                        $key = [Windows.Input.KeyEventArgs]::new([Windows.Input.Keyboard]::PrimaryDevice,[Windows.PresentationSource]::FromVisual($window),[Environment]::TickCount,[Windows.Input.Key]::Escape)
                        $key.RoutedEvent = [Windows.Input.Keyboard]::PreviewKeyDownEvent
                        $window.RaiseEvent($key)
                        Assert ($key.Handled) "$kind must handle Escape."
                    }
                    Invoke-ResizerUiEvents
                    Assert ($overlay.Visibility -eq 'Collapsed' -and $ui.MainLayout.IsEnabled -and $trigger.IsKeyboardFocused) "$kind $method must close and restore focus."
                }
            }
        } catch { $script:dialogFailure = $_ } finally { $window.Close() }
    }
    if ($script:dialogFailure) { throw $script:dialogFailure }
    Write-Host 'PASS: Updates and Log bind complete X; click/Escape close and restore focus.'
}
