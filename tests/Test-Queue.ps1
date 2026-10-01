# Copyright (c) 2026 Dariusz Trachimowicz / Digital Xperts
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSE for terms. Distributed WITHOUT ANY WARRANTY.
param([string]$ProgramFolder = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = if ($ProgramFolder) { [IO.Path]::GetFullPath($ProgramFolder) } else { Split-Path -Parent $PSScriptRoot }
Add-Type -AssemblyName System.Drawing
$parseErrors = $null; $tokens = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ResizerJPG.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) {
        . ([scriptblock]::Create($statement.Extent.Text))
    }
}
$module = Join-Path $root 'ResizerQueue.ps1'
if (Test-Path -LiteralPath $module) { . $module }
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert $threw $Message
}
function New-TestJpeg([string]$Path, [int]$Width = 240, [int]$Height = 120, [int]$Exif = 0) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $bitmap = New-Object Drawing.Bitmap($Width, $Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([Drawing.Color]::Crimson)
        $graphics.FillRectangle([Drawing.Brushes]::SeaGreen, 0, 0, ([int]($Width / 2)), $Height)
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Jpeg)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
    if ($Exif) {
        # Minimal little-endian TIFF APP1: orientation SHORT, or malformed ASCII.
        [byte[]]$app1 = @(255,225,0,34,69,120,105,102,0,0,73,73,42,0,8,0,0,0,1,0,18,1,3,0,1,0,0,0,6,0,0,0,0,0,0,0)
        if ($Exif -eq -1) { $app1[22] = 2; $app1[28] = 120; $app1[29] = 121 }
        [byte[]]$jpeg = [IO.File]::ReadAllBytes($Path)
        [IO.File]::WriteAllBytes($Path, [byte[]]($jpeg[0..1] + $app1 + $jpeg[2..($jpeg.Length - 1)]))
    }
}
function Read-TestImage([byte[]]$Bytes, [scriptblock]$Check) {
    $stream = New-Object IO.MemoryStream(,$Bytes)
    $image = $null
    try { $image = [Drawing.Bitmap]::FromStream($stream); & $Check $image } finally {
        if ($null -ne $image) { $image.Dispose() }; $stream.Dispose()
    }
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('resizer-queue-test-' + [guid]::NewGuid())
$source = Join-Path $fixture 'input'
$child = Join-Path $source 'child'
$custom = Join-Path $source 'destination'
$landscape = Join-Path $source 'same.JPG'
$portrait = Join-Path $child 'same.jpg'
$exif = Join-Path $child 'rotated.jpeg'
$badExif = Join-Path $child 'bad-exif.jpg'
$corrupt = Join-Path $source 'corrupt.jpg'
$script:failures = 0; $script:passes = 0
function Test([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:passes++; Write-Host "PASS: $Name" } catch {
        $script:failures++; Write-Host "FAIL: $Name - $($_.Exception.Message)"
    }
}
try {
    New-TestJpeg $landscape
    New-TestJpeg $portrait 120 240
    New-TestJpeg $exif 240 120 6
    New-TestJpeg $badExif 240 120 -1
    New-TestJpeg (Join-Path $source 'resize\generated.jpg')
    New-TestJpeg (Join-Path $child 'RESIZE\generated.jpg')
    New-TestJpeg (Join-Path $custom 'excluded.jpg')
    New-TestJpeg (Join-Path $source 'destination-other\included.jpg')
    [IO.File]::WriteAllText($corrupt, 'not a JPEG')
    $originals = @(Get-ChildItem -LiteralPath $source -File -Recurse | ForEach-Object {
        [pscustomobject]@{ Path = $_.FullName; Hash = (Get-FileHash -LiteralPath $_.FullName).Hash }
    })
    Test 'Required queue APIs are available without loading WPF' {
        foreach ($name in @('Get-ResizerQueueItems','Get-ResizerQueueTargetPath','Invoke-ResizerQueueExport','Get-ResizerPreviewData')) {
            Assert ($null -ne (Get-Command $name -ErrorAction SilentlyContinue)) "Missing queue API: $name"
        }
    }
    Test 'Background runspaces can load only AST core definitions and the queue module' {
        $definitions = @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] } | ForEach-Object { $_.Extent.Text }) -join "`n"
        $worker = [PowerShell]::Create()
        try {
            $body = 'param($Module,$Path) Add-Type -AssemblyName System.Drawing' + "`n" + $definitions + "`n" + '. $Module; Get-ResizerQueueItems -Paths @($Path)'
            [void]$worker.AddScript($body).AddArgument($module).AddArgument($exif)
            $result = @($worker.Invoke())
            Assert (-not $worker.HadErrors) ($worker.Streams.Error | Out-String)
            Assert ($result.Count -eq 1 -and $result[0].Orientation -eq 'Portrait' -and $result[0].ThumbnailBytes -is [byte[]]) 'Runspace queue data must be portable, EXIF-normalized byte data.'
        } finally { $worker.Dispose() }
    }
    Test 'Overlap deduplicates files and always preserves the outer relative root' {
        foreach ($paths in @(@($child,$source,$landscape), @($landscape,$source,$child))) {
            $items = @(Get-ResizerQueueItems -Paths $paths -IncludeSubfolders -ExcludedFolder $custom)
            Assert ($items.Count -eq 6) 'Expected six unique source JPGs, excluding resize and custom destination.'
            Assert (@($items | Where-Object { $_.Name -ieq 'same.jpg' }).Count -eq 2) 'Same names in different folders must survive.'
            $rotated = @($items | Where-Object FullPath -eq $exif)[0]
            Assert ($rotated.SourceRoot -eq $source -and $rotated.RelativePath -eq 'child\rotated.jpeg') 'Outer root must win regardless of path order.'
            Assert ($rotated.SourcePath -eq $source -and $rotated.SourceName -eq 'input') 'Source group identity must match its canonical root.'
        }
    }
    Test 'EXIF dimensions, malformed EXIF, corrupt items and thumbnail byte contract' {
        $items = @(Get-ResizerQueueItems -Paths @($source) -IncludeSubfolders -ExcludedFolder $custom)
        $rotated = @($items | Where-Object FullPath -eq $exif)[0]
        Assert ($rotated.Width -eq 120 -and $rotated.Height -eq 240 -and $rotated.Orientation -eq 'Portrait') 'EXIF 6 must normalize dimensions.'
        $malformed = @($items | Where-Object FullPath -eq $badExif)[0]
        Assert ($malformed.Width -eq 240 -and $malformed.Orientation -eq 'Landscape' -and -not $malformed.Error) 'Nonnumeric EXIF must not break ingestion.'
        $broken = @($items | Where-Object FullPath -eq $corrupt)[0]
        Assert ([bool]$broken.Error -and $broken.ThumbnailBytes.Length -eq 0) 'Corrupt JPG must remain a visible error item.'
        foreach ($item in @($items | Where-Object { -not $_.Error })) {
            Assert ($item.ThumbnailBytes -is [byte[]]) 'Thumbnail must be a byte array, not WPF.'
            Read-TestImage $item.ThumbnailBytes { param($image)
                Assert ([Math]::Max($image.Width,$image.Height) -le 160) 'Thumbnail exceeds 160 pixels.'
            }
        }
    }
    Test 'Explicit JPG in resize is accepted, custom destination is always excluded' {
        $items = @(Get-ResizerQueueItems -Paths @((Join-Path $source 'resize\generated.jpg'), (Join-Path $custom 'excluded.jpg')) -ExcludedFolder $custom)
        Assert ($items.Count -eq 1 -and $items[0].Name -eq 'generated.jpg') 'Explicit dropped JPG must obey core destination rules.'
        $items = @(Get-ResizerQueueItems -Paths @($source) -ExcludedFolder $custom)
        Assert ($items.Count -eq 2) 'Nonrecursive collection must exclude child files.'
    }
    Test 'Ingestion callbacks, cancellation and missing-path errors' {
        $state = @{ Count = 0; Progress = 0 }
        $items = @(Get-ResizerQueueItems -Paths @($source) -IncludeSubfolders -ShouldCancel { $state.Count -ge 1 } -OnItem { param($item) $state.Count++; 'ignored callback output' } -OnProgress { param($count,$name) $state.Progress = $count })
        Assert ($items.Count -eq 1 -and $state.Progress -eq 1) 'Cancellation must stop scanning between items and suppress callback output.'
        Assert-Throws { Get-ResizerQueueItems -Paths @((Join-Path $fixture 'missing')) } 'Missing paths must report an error.'
    }
    Test 'Target paths preserve hierarchy and reject traversal or source destination' {
        $item = @(Get-ResizerQueueItems -Paths @($source) -IncludeSubfolders -ExcludedFolder $custom | Where-Object FullPath -eq $portrait)[0]
        Assert ((Get-ResizerQueueTargetPath -Item $item) -eq (Join-Path $source 'resize\child\same_R.jpg')) 'Default target lost relative hierarchy.'
        Assert ((Get-ResizerQueueTargetPath -Item $item -DestinationFolder $custom) -eq (Join-Path $custom 'child\same_R.jpg')) 'Custom target lost hierarchy.'
        Assert-Throws { Get-ResizerQueueTargetPath -Item $item -DestinationFolder $source } 'Exact source root destination must be rejected.'
        foreach ($relative in @('..\escape.jpg','child\..\escape.jpg','C:\escape.jpg','\\server\escape.jpg','child\file.jpg:stream')) {
            $unsafe = [pscustomobject]@{ SourceRoot = $source; FullPath = $portrait; RelativePath = $relative }
            Assert-Throws { Get-ResizerQueueTargetPath -Item $unsafe -DestinationFolder $custom } "Unsafe relative path accepted: $relative"
        }
    }
    Test 'Drive-root source and destination paths remain absolute' {
        $driveRoot = [IO.Path]::GetPathRoot($source)
        $item = [pscustomobject]@{ SourceRoot=$driveRoot; FullPath=($driveRoot + 'photo.jpg'); RelativePath='photo.jpg' }
        Assert ((Get-ResizerQueueTargetPath -Item $item) -eq ($driveRoot + 'resize\photo_R.jpg')) 'Drive root must not become a drive-relative working-directory path.'
        Assert-Throws { Get-ResizerQueueTargetPath -Item $item -DestinationFolder $driveRoot } 'Exact drive-root source destination must be rejected.'
        $nested = [pscustomobject]@{ SourceRoot=$source; FullPath=$landscape; RelativePath='photo.jpg' }
        Assert ((Get-ResizerQueueTargetPath -Item $nested -DestinationFolder $driveRoot) -eq ($driveRoot + 'photo_R.jpg')) 'Custom drive-root destination must remain absolute.'
    }
    Test 'Subset export continues after corrupt JPG and never overwrites collisions' {
        $items = @(Get-ResizerQueueItems -Paths @($source) -IncludeSubfolders -ExcludedFolder $custom)
        $selected = @($items | Where-Object { $_.FullPath -in @($portrait,$corrupt,$exif) })
        $destination = Join-Path $fixture 'export'
        $collision = Join-Path $destination 'child\same_R.jpg'
        New-TestJpeg $collision
        $oldHash = (Get-FileHash -LiteralPath $collision).Hash
        $events = New-Object 'Collections.Generic.List[object]'
        $result = Invoke-ResizerQueueExport -Items $selected -DestinationFolder $destination -Ratio Auto -ResizeMode Pad -TargetWidth 2880 -TargetHeight 1920 -JpegQuality 85 -OutputDpi 72 -OnProgress {
            param($done,$total,$item,$success,$output,$errorMessage)
            $events.Add([pscustomobject]@{ Done=$done; Success=$success; Error=$errorMessage; Path=$output }); 'ignored'
        } -OnMessage {}
        Assert ($result.Total -eq 3 -and $result.Done -eq 2 -and $result.Failed -eq 1 -and -not $result.Cancelled) 'Subset export counts are wrong.'
        Assert (@($result.OutputFolders).Count -eq 1 -and $result.OutputFolders[0] -eq $destination) 'OutputFolders must report destination roots.'
        Assert ($events.Count -eq 3 -and $events[2].Done -eq 3 -and @($events | Where-Object { -not $_.Success -and $_.Error }).Count -eq 1) 'Progress must report every attempted file including errors.'
        Assert ((Get-FileHash -LiteralPath $collision).Hash -eq $oldHash) 'Existing target must not be overwritten.'
        Assert (Test-Path -LiteralPath (Join-Path $destination 'child\same_R_1.jpg')) 'Collision must use numbered suffix.'
        Assert (-not (Test-Path -LiteralPath (Join-Path $destination 'same_R.JPG'))) 'Unselected landscape must not be exported.'
        Read-TestImage ([IO.File]::ReadAllBytes((Join-Path $destination 'child\rotated_R.jpeg'))) { param($image)
            Assert ($image.Width -eq 1920 -and $image.Height -eq 2880) 'Makalu EXIF portrait export must be 1920 x 2880.'
            Assert ([Math]::Abs($image.HorizontalResolution - 72) -lt 1) 'Makalu DPI must be 72.'
        }
    }
    Test 'Export cancellation is between files and empty selection is harmless' {
        $items = @(Get-ResizerQueueItems -Paths @($landscape,$portrait))
        $state = @{ Done = 0 }
        $destination = Join-Path $fixture 'cancelled'
        $result = Invoke-ResizerQueueExport -Items $items -DestinationFolder $destination -Ratio Auto -ResizeMode Crop -TargetWidth 288 -TargetHeight 192 -JpegQuality 85 -OutputDpi 72 -ShouldCancel { $state.Done -ge 1 } -OnProgress { param($done) $state.Done = $done } -OnMessage {}
        Assert ($result.Cancelled -and $result.Total -eq 2 -and $result.Done -eq 1 -and $result.Failed -eq 0) 'Cancellation must not start the second file.'
        Assert (@(Get-ChildItem -LiteralPath $destination -Filter '*.jpg' -Recurse).Count -eq 1) 'Cancellation wrote extra files.'
        $empty = Invoke-ResizerQueueExport -Items @() -Ratio Auto -ResizeMode Pad -TargetWidth 288 -TargetHeight 192 -JpegQuality 85 -OutputDpi 72 -OnMessage {}
        Assert ($empty.Total -eq 0 -and $empty.Done -eq 0 -and @($empty.OutputFolders).Count -eq 0) 'Empty selection must not scan any source folder.'
    }
    Test 'Default export reports distinct roots, preserves landscape size and numbers repeat results' {
        $secondRoot = Join-Path $fixture 'second'
        $secondFile = Join-Path $secondRoot 'same.jpg'
        New-TestJpeg $secondFile
        $items = @(Get-ResizerQueueItems -Paths @($landscape,$secondFile,$landscape.ToLowerInvariant()))
        Assert ($items.Count -eq 2) 'File deduplication must be ordinal case-insensitive.'
        $result = Invoke-ResizerQueueExport -Items $items -OnMessage {}
        Assert ($result.Done -eq 2 -and @($result.OutputFolders).Count -eq 2) 'Default export must retain both source roots.'
        $output = Join-Path $source 'resize\same_R.JPG'
        Read-TestImage ([IO.File]::ReadAllBytes($output)) { param($image)
            Assert ($image.Width -eq 2880 -and $image.Height -eq 1920) 'Makalu landscape export must be 2880 x 1920.'
            Assert ([Math]::Abs($image.HorizontalResolution - 72) -lt 1) 'Default export DPI must be 72.'
        }
        $previousHash = (Get-FileHash -LiteralPath $output).Hash
        $result = Invoke-ResizerQueueExport -Items @($items[0]) -TargetWidth 288 -TargetHeight 192 -OnMessage {}
        Assert ($result.Done -eq 1 -and (Test-Path -LiteralPath (Join-Path $source 'resize\same_R_1.JPG'))) 'Repeated export must number outputs.'
        Assert ((Get-FileHash -LiteralPath $output).Hash -eq $previousHash) 'Repeated export replaced a previous result.'
    }
    Test 'Immediate cancellation writes no output and invalid options fail before writing' {
        $items = @(Get-ResizerQueueItems -Paths @($landscape))
        $destination = Join-Path $fixture 'no-writes'
        $result = Invoke-ResizerQueueExport -Items $items -DestinationFolder $destination -ShouldCancel { $true }
        Assert ($result.Cancelled -and $result.Done -eq 0 -and -not (Test-Path -LiteralPath $destination)) 'Pre-cancelled export must not create a destination.'
        Assert-Throws { Invoke-ResizerQueueExport -Items $items -DestinationFolder $destination -Ratio '16:9' -TargetWidth 100 -TargetHeight 100 } 'Invalid aspect ratio must fail before processing.'
        Assert-Throws { Invoke-ResizerQueueExport -Items $items -DestinationFolder $destination -OutputDpi 0 } 'Invalid DPI must be rejected.'
        Assert (-not (Test-Path -LiteralPath $destination)) 'Invalid options created an output folder.'
    }
    Test 'Result preview decodes real target codec output and Pad/Crop visibly differ' {
        $options = @{ Width=2880; Height=1920; Ratio='Auto'; Mode='Pad'; Quality=85; Dpi=72 }
        $preview = Get-ResizerPreviewData -Path $exif -Options $options
        Assert ($preview.SourceWidth -eq 120 -and $preview.SourceHeight -eq 240 -and $preview.TargetWidth -eq 1920 -and $preview.TargetHeight -eq 2880) 'Preview metadata must be EXIF-normalized.'
        Assert ($preview.Width -eq 1920 -and $preview.Height -eq 2880 -and $preview.Bytes -is [byte[]]) 'Result preview must not scale down the encoded target.'
        Assert ($preview.Bytes[0] -eq 255 -and $preview.Bytes[1] -eq 216) 'Result preview must use actual JPEG codec bytes.'
        Read-TestImage $preview.Bytes { param($image)
            Assert ($image.Width -eq 1920 -and $image.Height -eq 2880) 'Encoded JPEG dimensions differ from metadata.'
            $color = $image.GetPixel(2,2)
            Assert ($color.R -gt 245 -and $color.G -gt 245 -and $color.B -gt 245) 'Pad must leave a white margin.'
        }
        $options.Mode = 'Crop'; $options.Quality = 20
        $crop = Get-ResizerPreviewData -Path $exif -Options $options
        Read-TestImage $crop.Bytes { param($image)
            $color = $image.GetPixel(2,2)
            Assert ($color.R -lt 245 -or $color.G -lt 245 -or $color.B -lt 245) 'Crop must fill the target.'
        }
        Assert ($crop.Bytes.Length -ne $preview.Bytes.Length) 'Preview ignored mode/quality.'
        $options.Quality = 85
        $betterCrop = Get-ResizerPreviewData -Path $exif -Options $options
        Assert ([Convert]::ToBase64String($crop.Bytes) -ne [Convert]::ToBase64String($betterCrop.Bytes)) 'JPEG preview must reflect quality for the same mode and target.'
        Assert-Throws { Get-ResizerPreviewData -Path $corrupt -Options $options } 'Corrupt preview must surface an error.'
    }
    Test 'Original preview limits raster allocation and keeps original dimension metadata' {
        $large = Join-Path $fixture 'large.jpg'
        New-TestJpeg $large 3000 1500
        $preview = Get-ResizerPreviewData -Path $large -Options @{ Width=2880; Height=1920; Ratio='Auto'; Mode='Pad'; Quality=85; Dpi=72 } -Original
        Assert ($preview.SourceWidth -eq 3000 -and $preview.SourceHeight -eq 1500 -and $preview.Width -eq 2048 -and $preview.Height -eq 1024) 'Original preview must be bounded while retaining source metadata.'
        Read-TestImage $preview.Bytes { param($image) Assert ($image.Width -eq 2048 -and $image.Height -eq 1024) 'Original byte dimensions mismatch.' }
        $rotated = Get-ResizerPreviewData -Path $exif -Original
        Assert ($rotated.Width -eq 120 -and $rotated.Height -eq 240) 'Original preview must apply EXIF without upscaling.'
    }
    Test 'Preview deletes only its unique temporary leaf and releases handles' {
        $temporary = Join-Path $fixture 'preview-temp'
        [void][IO.Directory]::CreateDirectory($temporary)
        $sentinel = Join-Path $temporary 'keep.txt'
        [IO.File]::WriteAllText($sentinel, 'keep')
        $oldTemp = $env:TEMP; $oldTmp = $env:TMP
        try {
            $env:TEMP = $temporary; $env:TMP = $temporary
            $null = Get-ResizerPreviewData -Path $landscape -Options @{ Width=288; Height=192 }
            Assert (@(Get-ChildItem -LiteralPath $temporary -File).Count -eq 1 -and (Test-Path -LiteralPath $sentinel)) 'Preview leaked a temp file or deleted another file.'
        } finally { $env:TEMP = $oldTemp; $env:TMP = $oldTmp }
    }
    Test 'All source files remain byte-identical and unlocked' {
        foreach ($original in $originals) {
            Assert ((Get-FileHash -LiteralPath $original.Path).Hash -eq $original.Hash) 'Source SHA changed.'
            $handle = [IO.File]::Open($original.Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            $handle.Dispose()
        }
    }
    Write-Host ("Queue tests: {0} passed, {1} failed (PowerShell {2})." -f $script:passes,$script:failures,$PSVersionTable.PSVersion)
    if ($script:failures) { throw "Queue tests failed: $script:failures" }
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\resizer-queue-test-'
    if ($resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
