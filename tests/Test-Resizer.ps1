param([switch]$Ui, [string]$ProgramFolder = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = if ($ProgramFolder) { [IO.Path]::GetFullPath($ProgramFolder) } else { Split-Path -Parent $PSScriptRoot }
$errorsFound = $null
$tokensFound = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ResizerJPG.ps1'), [ref]$tokensFound, [ref]$errorsFound)
if ($errorsFound.Count) { throw ($errorsFound | Out-String) }
Add-Type -AssemblyName System.Drawing
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) {
        . ([scriptblock]::Create($statement.Extent.Text))
    }
}
function Assert($Condition, $Message) {
    if (-not $Condition) { throw $Message }
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('resizer-test-' + [guid]::NewGuid())
[void](New-Item -ItemType Directory -Path $fixture)
try {
    foreach ($size in @(@(120,180,'portrait.jpg'), @(180,120,'landscape.jpeg'))) {
        $bitmap = New-Object Drawing.Bitmap($size[0], $size[1])
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([Drawing.Color]::White)
        $graphics.FillRectangle([Drawing.Brushes]::SeaGreen, 20, 20, 70, 90)
        $graphics.FillEllipse([Drawing.Brushes]::Crimson, 35, 35, 45, 45)
        $bitmap.Save((Join-Path $fixture $size[2]), [Drawing.Imaging.ImageFormat]::Jpeg)
        $graphics.Dispose()
        $bitmap.Dispose()
    }
    $source = Join-Path $fixture 'portrait.jpg'
    $originalHash = (Get-FileHash $source).Hash
    $result = Invoke-BatchResize -SourceFolder $source -Ratio Auto -ResizeMode Pad -TargetWidth 288 -TargetHeight 192 -JpegQuality 85 -OutputDpi 72 -OnMessage {}
    Assert ($result.Done -eq 1) 'Single JPG must be accepted.'
    $output = Join-Path $fixture 'resize\portrait_R.jpg'
    $image = [Drawing.Image]::FromFile($output)
    Assert ($image.Width -eq 192 -and $image.Height -eq 288) 'Portrait dimensions must be swapped automatically.'
    Assert ([Math]::Abs($image.HorizontalResolution - 72) -lt 1 -and [Math]::Abs($image.VerticalResolution - 72) -lt 1) 'Both DPI values must be 72.'
    $image.Dispose()
    Assert ((Get-FileHash $source).Hash -eq $originalHash) 'Original must remain unchanged.'
    $result = Invoke-BatchResize -SourceFolder $fixture -Ratio Auto -ResizeMode Pad -TargetWidth 288 -TargetHeight 192 -JpegQuality 85 -OutputDpi 72 -IncludeSubfolders -OnMessage {}
    Assert ($result.Total -eq 2 -and $result.Done -eq 2) 'Recursive batch must exclude generated resize files.'
    Assert (Test-Path (Join-Path $fixture 'resize\portrait_R_1.jpg')) 'Existing results must not be overwritten.'
    $image = [Drawing.Image]::FromFile((Join-Path $fixture 'resize\landscape_R.jpeg'))
    Assert ($image.Width -eq 288 -and $image.Height -eq 192) 'Landscape dimensions must be retained.'
    $image.Dispose()
    $result = Invoke-BatchResize -SourceFolder $fixture -Ratio Auto -ResizeMode Crop -TargetWidth 288 -TargetHeight 192 -JpegQuality 85 -OutputDpi 72 -ShouldCancel { $true } -OnMessage {}
    Assert ($result.Cancelled -and $result.Done -eq 0) 'Cancelled batch must not process another photo.'
    Write-Host 'PASS: file/folder, orientation, DPI, suffix, collision, recursion, cancellation, unchanged original.'
    if ($Ui) { & (Join-Path $PSScriptRoot 'Test-WpfUI.ps1') -ProgramFolder $root }
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\resizer-test-'
    if ($resolvedFixture.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
