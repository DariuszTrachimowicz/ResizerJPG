# Copyright (c) 2026 Dariusz Trachimowicz / Digital Xperts
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSE for terms. Distributed WITHOUT ANY WARRANTY.
param([string]$ProgramFolder = '', [string]$RenderDirectory = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
if (-not $ProgramFolder) { $ProgramFolder = $root }
$ProgramFolder = [IO.Path]::GetFullPath($ProgramFolder)
Add-Type -AssemblyName System.Drawing
function Assert($condition, [string]$message) { if (-not $condition) { throw $message } }

$masterPath = Join-Path $root 'resizer-icon.png'
Assert ((Get-FileHash -LiteralPath $masterPath).Hash -eq '43B1AB380D139AB713EA7CE26B07BF4B6878ED813D79BC15D6ABF1B43EE9187F') 'Approved master must remain byte-identical.'
Assert ((Get-FileHash -LiteralPath (Join-Path $ProgramFolder 'digital-xperts-logo.png')).Hash -eq '345DA929E1C609E423DEFC6DE124C35257D1DBBB6849ADADF96380ECDE51DB37') 'Header logo must remain byte-identical.'
$iconPath = Join-Path $ProgramFolder 'resizer-jpg.ico'
$bytes = [IO.File]::ReadAllBytes($iconPath)
$sizes = @(16,24,32,48,64,128,256)
Assert ($bytes.Length -ge 118) 'ICO directory is truncated.'
Assert ([BitConverter]::ToUInt16($bytes,0) -eq 0 -and [BitConverter]::ToUInt16($bytes,2) -eq 1 -and [BitConverter]::ToUInt16($bytes,4) -eq 7) 'ICO must contain exactly seven icon frames.'
$seen = @()
$payloads = @{}
for ($i = 0; $i -lt 7; $i++) {
    $entry = 6 + 16*$i
    $width = if ($bytes[$entry] -eq 0) { 256 } else { [int]$bytes[$entry] }
    $height = if ($bytes[$entry+1] -eq 0) { 256 } else { [int]$bytes[$entry+1] }
    $length = [BitConverter]::ToUInt32($bytes,$entry+8)
    $offset = [BitConverter]::ToUInt32($bytes,$entry+12)
    Assert ($width -eq $height -and $sizes -contains $width -and $seen -notcontains $width) 'ICO needs seven distinct requested square sizes.'
    Assert ($length -gt 0 -and $offset -ge 118 -and ([long]$offset+$length) -le $bytes.Length) "Invalid ICO payload for $width px."
    $seen += $width
    $payloads[$width] = @{ Entry = $entry; Offset = [int]$offset; Length = [int]$length }
}

$master = [Drawing.Bitmap]::new($masterPath)
$sheet = $null; $sheetGraphics = $null; $font = $null
try {
    if ($RenderDirectory) {
        $RenderDirectory = [IO.Path]::GetFullPath($RenderDirectory)
        [void][IO.Directory]::CreateDirectory($RenderDirectory)
        $sheet = [Drawing.Bitmap]::new(1000,310)
        $sheetGraphics = [Drawing.Graphics]::FromImage($sheet)
        $sheetGraphics.Clear([Drawing.Color]::FromArgb(238,238,238))
        $font = [Drawing.Font]::new('Segoe UI',10)
        $sheetGraphics.DrawString('Native ICO frames - actual pixel sizes (1:1)', $font, [Drawing.Brushes]::Black, 8, 4)
    }
    $left = 8
    foreach ($size in $sizes) {
        # Request each frame through Windows GDI+, rather than resizing one large PNG.
        $nativeIcon = $null; $frameStream = $null
        $bitmap = $null; $pngStream = $null
        try {
            $payload = $payloads[$size]
            if ($size -eq 256) {
                # .NET Framework's multi-frame selector treats the ICO size byte 0
                # as zero, not 256. Isolate the original entry without resampling.
                $frameBytes = New-Object byte[] (22+$payload.Length)
                [Array]::Copy($bytes,0,$frameBytes,0,6)
                $frameBytes[4] = 1; $frameBytes[5] = 0
                [Array]::Copy($bytes,$payload.Entry,$frameBytes,6,16)
                [Array]::Copy([BitConverter]::GetBytes([uint32]22),0,$frameBytes,18,4)
                [Array]::Copy($bytes,$payload.Offset,$frameBytes,22,$payload.Length)
                $frameStream = [IO.MemoryStream]::new($frameBytes)
                $nativeIcon = [Drawing.Icon]::new($frameStream,$size,$size)
            } else { $nativeIcon = [Drawing.Icon]::new($iconPath,$size,$size) }
            Assert ($nativeIcon.Width -eq $size -and $nativeIcon.Height -eq $size) "Native decoder did not select $size px."
            if ($bytes[$payload.Offset] -eq 137 -and $bytes[$payload.Offset+1] -eq 80) {
                # .NET Framework Icon.ToBitmap misreads PNG-backed ICO payloads.
                # Decode that exact directory entry with the native GDI+ PNG decoder.
                $pngStream = [IO.MemoryStream]::new($bytes,$payload.Offset,$payload.Length)
                $bitmap = [Drawing.Bitmap]::new($pngStream)
            } else {
                $bitmap = $nativeIcon.ToBitmap()
            }
            Assert ($bitmap.Width -eq $size -and $bitmap.Height -eq $size) "Decoded payload differs from $size px directory entry."
            $minX = $size; $minY = $size; $maxX = -1; $maxY = -1
            $cyan = 0; $white = 0; $dark = 0
            for ($y = 0; $y -lt $size; $y++) {
                for ($x = 0; $x -lt $size; $x++) {
                    $p = $bitmap.GetPixel($x,$y)
                    # Ignore faint resampling fringes when measuring optical bounds.
                    if ($p.A -ge 128) {
                        $minX = [Math]::Min($minX,$x); $maxX = [Math]::Max($maxX,$x)
                        $minY = [Math]::Min($minY,$y); $maxY = [Math]::Max($maxY,$y)
                        if ($p.R -lt 80 -and $p.G -gt 130 -and $p.B -gt 170) { $cyan++ }
                        if ($p.R -gt 210 -and $p.G -gt 210 -and $p.B -gt 210) { $white++ }
                        if ($p.R -lt 90 -and $p.G -lt 100 -and $p.B -lt 110) { $dark++ }
                    }
                }
            }
            $fillWidth = $maxX-$minX+1; $fillHeight = $maxY-$minY+1
            Write-Host ("Native {0}px: alpha>=128 bounds {1}x{2}, cyan/white/dark {3}/{4}/{5}" -f $size,$fillWidth,$fillHeight,$cyan,$white,$dark)
            Assert ($fillWidth/$size -ge 0.85 -and $fillHeight/$size -ge 0.85 -and [Math]::Abs($fillWidth-$fillHeight) -le 2) "Optical fill too small or nonsquare at ${size}px: ${fillWidth}x${fillHeight}; need >=85% in both dimensions."
            foreach ($corner in @(@(0,0),@(($size-1),0),@(0,($size-1)),@(($size-1),($size-1)))) {
                Assert ($bitmap.GetPixel($corner[0],$corner[1]).A -eq 0) "Corner must be transparent at $size px."
            }
            # At 16px antialiasing leaves 11 near-white pixels (4.3%); use 3% as
            # the palette floor while the independent 24/32px reference checks shape.
            Assert ($cyan -gt $size*$size*0.15 -and $white -gt $size*$size*0.03 -and $dark -gt $size*$size*0.04) "Missing cyan circle, white picture/arrow or dark photo border at $size px."
            if ($size -eq 24 -or $size -eq 32) {
                # Independent native resampling of the approved master; compare premultiplied
                # channels so invisible RGB does not affect the content measurement.
                $reference = [Drawing.Bitmap]::new($size,$size)
                $graphics = [Drawing.Graphics]::FromImage($reference)
                try {
                    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
                    $graphics.DrawImage($master,[Drawing.Rectangle]::new(0,0,$size,$size))
                    $difference = 0.0
                    for ($y = 0; $y -lt $size; $y++) {
                        for ($x = 0; $x -lt $size; $x++) {
                            $p = $bitmap.GetPixel($x,$y); $q = $reference.GetPixel($x,$y)
                            $difference += [Math]::Abs([int]$p.A-[int]$q.A)
                            foreach ($channel in @('R','G','B')) {
                                $difference += [Math]::Abs($p.$channel*$p.A/255.0-$q.$channel*$q.A/255.0)
                            }
                        }
                    }
                    $meanError = $difference/($size*$size*4)
                    Write-Host ('Native {0}px vs master: mean channel error {1:F3}/255' -f $size,$meanError)
                    Assert ($meanError -lt 12) "Native $size px content differs from approved master."
                } finally { $graphics.Dispose(); $reference.Dispose() }
            }
            if ($sheetGraphics) {
                $bitmap.Save((Join-Path $RenderDirectory ('icon-{0}.png' -f $size)),[Drawing.Imaging.ImageFormat]::Png)
                $sheetGraphics.DrawImageUnscaled($bitmap,$left,45)
                $sheetGraphics.DrawString("$size px",$font,[Drawing.Brushes]::Black,[single]$left,25)
                $left += [Math]::Max($size,60)+16
            }
        } finally {
            if ($bitmap) { $bitmap.Dispose() }
            if ($pngStream) { $pngStream.Dispose() }
            if ($nativeIcon) { $nativeIcon.Dispose() }
            if ($frameStream) { $frameStream.Dispose() }
        }
    }
    if ($sheet) { $sheet.Save((Join-Path $RenderDirectory 'app-icon-native-preview.png'),[Drawing.Imaging.ImageFormat]::Png) }
} finally {
    if ($font) { $font.Dispose() }
    if ($sheetGraphics) { $sheetGraphics.Dispose() }
    if ($sheet) { $sheet.Dispose() }
    $master.Dispose()
}

# Run the real creator twice in one process (type-guard regression), without launching
# the shortcut or touching a user's existing shortcuts, pinned items or application.
$fixture = Join-Path $root ("work\icon fixture & O'Brien " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
foreach ($name in @('UtworzSkrotZIkona.ps1','Uruchom Resizer JPG.vbs','resizer-jpg.ico')) {
    Copy-Item -LiteralPath (Join-Path $ProgramFolder $name) -Destination $fixture
}
$shell = New-Object -ComObject WScript.Shell
$previousWarningPreference = $WarningPreference
try {
    $WarningPreference = 'Stop'
    for ($run = 1; $run -le 2; $run++) {
        & (Join-Path $fixture 'UtworzSkrotZIkona.ps1')
        $shortcut = $shell.CreateShortcut((Join-Path $fixture 'Resizer JPG.lnk'))
        try {
            Assert ($shortcut.TargetPath -ieq (Join-Path $env:SystemRoot 'System32\wscript.exe')) 'Shortcut must use hidden VBS launcher via wscript.'
            Assert ($shortcut.Arguments -ceq ('//nologo "' + (Join-Path $fixture 'Uruchom Resizer JPG.vbs') + '"')) 'Shortcut must preserve one quoted launcher path.'
            Assert ($shortcut.WorkingDirectory -ieq $fixture) 'Shortcut working directory changed.'
            Assert ($shortcut.IconLocation -ieq ((Join-Path $fixture 'resizer-jpg.ico')+',0')) 'Shortcut must use the selected local ICO.'
            Assert ($shortcut.Description -ceq 'Resizer JPG - tworca oprogramowania: Dariusz Trachimowicz') 'Shortcut creator attribution changed.'
        } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
    }
} finally {
    $WarningPreference = $previousWarningPreference
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
}
Write-Host 'PASS: seven native frames, transparency, optical fill, master content and real shortcut creator twice.'
