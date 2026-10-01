param(
    [string]$InputFolder = "",
    [string]$OutputFolder = "",
    [ValidateSet("16:9", "9:16", "Auto")]
    [string]$AspectRatio = "Auto",
    [ValidateSet("Crop", "Pad")]
    [string]$Mode = "Pad",
    [int]$Width = 0,
    [int]$Height = 0,
    [ValidateRange(1, 100)]
    [int]$Quality = 85,
    [ValidateRange(1, 600)]
    [int]$Dpi = 72,
    [switch]$Recursive,
    [Alias('MakaluSklep')]
    [switch]$OnlineStore,
    [string[]]$DroppedFolders = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Get-DefaultTargetSize {
    param([string]$Ratio)

    if ($Ratio -eq "Auto") {
        return [pscustomobject]@{ Width = 2880; Height = 1920 }
    }

    if ($Ratio -eq "9:16") {
        return [pscustomobject]@{ Width = 1080; Height = 1920 }
    }

    return [pscustomobject]@{ Width = 1920; Height = 1080 }
}

function Add-ResizedSuffixToPath {
    param([string]$RelativePath)

    $folder = Split-Path -Parent $RelativePath
    $name = [System.IO.Path]::GetFileNameWithoutExtension($RelativePath)
    $extension = [System.IO.Path]::GetExtension($RelativePath)
    $resizedName = "{0}_R{1}" -f $name, $extension

    if ([string]::IsNullOrWhiteSpace($folder)) {
        return $resizedName
    }

    return Join-Path $folder $resizedName
}

function Apply-OnlineStoreProfile {
    return [pscustomobject]@{
        AspectRatio = "Auto"
        Mode = "Pad"
        Width = 2880
        Height = 1920
        Quality = 85
        Dpi = 72
    }
}

function Get-NormalizedFolderPath {
    param([string]$Path)

    $trimChars = [char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )

    return [System.IO.Path]::GetFullPath($Path).TrimEnd($trimChars)
}

function Get-RelativePathCompat {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString())) {
        $baseFull += [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = New-Object System.Uri($baseFull)
    $fullUri = New-Object System.Uri([System.IO.Path]::GetFullPath($FullPath))
    $relativeUri = $baseUri.MakeRelativeUri($fullUri).ToString()

    return [System.Uri]::UnescapeDataString($relativeUri).Replace(
        [System.IO.Path]::AltDirectorySeparatorChar,
        [System.IO.Path]::DirectorySeparatorChar
    )
}

function Get-UniquePath {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $Path
    }

    $folder = Split-Path -Parent $Path
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $extension = [System.IO.Path]::GetExtension($Path)
    $index = 1

    do {
        $candidate = Join-Path $folder ("{0}_{1}{2}" -f $name, $index, $extension)
        $index += 1
    } while (Test-Path -LiteralPath $candidate)

    return $candidate
}

function Assert-TargetAspectRatio {
    param(
        [string]$Ratio,
        [int]$TargetWidth,
        [int]$TargetHeight
    )

    if ($TargetWidth -le 0 -or $TargetHeight -le 0) {
        throw "Szerokosc i wysokosc musza byc wieksze od zera."
    }

    if ($Ratio -eq "Auto") {
        return
    }

    $expected = if ($Ratio -eq "9:16") { 9.0 / 16.0 } else { 16.0 / 9.0 }
    $actual = [double]$TargetWidth / [double]$TargetHeight

    if ([Math]::Abs($actual - $expected) -gt 0.001) {
        throw "Rozmiar $TargetWidth x $TargetHeight nie pasuje do proporcji $Ratio."
    }
}

function Get-ImageOrientation {
    param([string]$SourcePath)

    $image = $null

    try {
        $image = [System.Drawing.Image]::FromFile($SourcePath)
        Apply-ExifOrientation -Image $image

        if ($image.Height -gt $image.Width) {
            return "Portrait"
        }

        return "Landscape"
    } finally {
        if ($null -ne $image) {
            $image.Dispose()
        }
    }
}

function Get-TargetSizeForRatio {
    param(
        [string]$Ratio,
        [int]$BaseWidth,
        [int]$BaseHeight,
        [string]$Orientation
    )

    if ($Ratio -eq "Auto") {
        $longSide = [Math]::Max($BaseWidth, $BaseHeight)
        $shortSide = [Math]::Min($BaseWidth, $BaseHeight)

        if ($Orientation -eq "Portrait") {
            return [pscustomobject]@{
                Ratio = "pionowy"
                Width = $shortSide
                Height = $longSide
            }
        }

        return [pscustomobject]@{
            Ratio = "poziomy"
            Width = $longSide
            Height = $shortSide
        }
    }

    return [pscustomobject]@{
        Ratio = $Ratio
        Width = $BaseWidth
        Height = $BaseHeight
    }
}

function Apply-ExifOrientation {
    param([System.Drawing.Image]$Image)

    $orientationId = 0x0112
    if (-not ($Image.PropertyIdList -contains $orientationId)) {
        return
    }

    try {
        $orientation = [BitConverter]::ToUInt16($Image.GetPropertyItem($orientationId).Value, 0)

        switch ($orientation) {
            2 { $Image.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX) }
            3 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
            4 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipX) }
            5 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipX) }
            6 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
            7 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipX) }
            8 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
        }

        try {
            $Image.RemovePropertyItem($orientationId)
        } catch {
            # Some images expose orientation metadata as read-only.
        }
    } catch {
        # Bad EXIF data should not stop the batch.
    }
}

function Get-JpegCodec {
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object { $_.MimeType -eq "image/jpeg" } |
        Select-Object -First 1

    if ($null -eq $codec) {
        throw "Nie znaleziono kodeka JPG w systemie."
    }

    return $codec
}

function Save-Jpeg {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [string]$TargetPath,
        [int]$JpegQuality
    )

    $codec = Get-JpegCodec
    $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encoderParam = $null

    try {
        $safeQuality = [Math]::Max(1, [Math]::Min(100, $JpegQuality))
        $encoderParam = New-Object System.Drawing.Imaging.EncoderParameter(
            [System.Drawing.Imaging.Encoder]::Quality,
            [int64]$safeQuality
        )
        $encoderParams.Param[0] = $encoderParam
        $Bitmap.Save($TargetPath, $codec, $encoderParams)
    } finally {
        if ($null -ne $encoderParam) {
            $encoderParam.Dispose()
        }
        $encoderParams.Dispose()
    }
}

function Resize-Jpeg {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [int]$TargetWidth,
        [int]$TargetHeight,
        [string]$ResizeMode,
        [int]$JpegQuality,
        [int]$OutputDpi
    )

    $image = $null
    $canvas = $null
    $graphics = $null

    try {
        $image = [System.Drawing.Image]::FromFile($SourcePath)
        Apply-ExifOrientation -Image $image

        $canvas = New-Object System.Drawing.Bitmap(
            $TargetWidth,
            $TargetHeight,
            [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
        )

        $canvas.SetResolution($OutputDpi, $OutputDpi)

        $graphics = [System.Drawing.Graphics]::FromImage($canvas)
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.Clear([System.Drawing.Color]::White)

        $sourceX = 0.0
        $sourceY = 0.0
        $sourceWidth = [double]$image.Width
        $sourceHeight = [double]$image.Height
        $targetX = 0.0
        $targetY = 0.0
        $drawWidth = [double]$TargetWidth
        $drawHeight = [double]$TargetHeight

        if ($ResizeMode -eq "Crop") {
            $targetRatio = [double]$TargetWidth / [double]$TargetHeight
            $sourceRatio = [double]$image.Width / [double]$image.Height

            if ($sourceRatio -gt $targetRatio) {
                $sourceWidth = [double]$image.Height * $targetRatio
                $sourceX = ([double]$image.Width - $sourceWidth) / 2.0
            } else {
                $sourceHeight = [double]$image.Width / $targetRatio
                $sourceY = ([double]$image.Height - $sourceHeight) / 2.0
            }
        } else {
            $scale = [Math]::Min(
                [double]$TargetWidth / [double]$image.Width,
                [double]$TargetHeight / [double]$image.Height
            )
            $drawWidth = [double]$image.Width * $scale
            $drawHeight = [double]$image.Height * $scale
            $targetX = ([double]$TargetWidth - $drawWidth) / 2.0
            $targetY = ([double]$TargetHeight - $drawHeight) / 2.0
        }

        $sourceRect = New-Object System.Drawing.RectangleF(
            [float]$sourceX,
            [float]$sourceY,
            [float]$sourceWidth,
            [float]$sourceHeight
        )
        $targetRect = New-Object System.Drawing.RectangleF(
            [float]$targetX,
            [float]$targetY,
            [float]$drawWidth,
            [float]$drawHeight
        )

        $graphics.DrawImage($image, $targetRect, $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
        Save-Jpeg -Bitmap $canvas -TargetPath $TargetPath -JpegQuality $JpegQuality
    } finally {
        if ($null -ne $graphics) {
            $graphics.Dispose()
        }
        if ($null -ne $canvas) {
            $canvas.Dispose()
        }
        if ($null -ne $image) {
            $image.Dispose()
        }
    }
}

function Invoke-BatchResize {
    param(
        [string]$SourceFolder,
        [string]$DestinationFolder,
        [string]$Ratio,
        [string]$ResizeMode,
        [int]$TargetWidth,
        [int]$TargetHeight,
        [int]$JpegQuality,
        [int]$OutputDpi,
        [switch]$IncludeSubfolders,
        [scriptblock]$ShouldCancel = { $false },
        [scriptblock]$OnMessage = { param($Message) Write-Host $Message },
        [scriptblock]$OnProgress = { param($Done, $Total, $Name) }
    )

    if ([string]::IsNullOrWhiteSpace($SourceFolder)) {
        throw "Wybierz folder ze zdjeciami JPG."
    }

    if (-not (Test-Path -LiteralPath $SourceFolder)) {
        throw "Plik lub folder ze zdjeciami nie istnieje: $SourceFolder"
    }

    $sourceItem = Get-Item -LiteralPath $SourceFolder -ErrorAction Stop
    $sourceRoot = if ($sourceItem.PSIsContainer) { $sourceItem.FullName } else { $sourceItem.DirectoryName }
    if ([string]::IsNullOrWhiteSpace($DestinationFolder)) {
        $DestinationFolder = Join-Path $sourceRoot "resize"
    }

    $sourceFull = Get-NormalizedFolderPath -Path $sourceRoot
    $destinationFull = Get-NormalizedFolderPath -Path $DestinationFolder

    if ($sourceFull -eq $destinationFull) {
        throw "Folder wynikowy musi byc inny niz folder ze zdjeciami."
    }

    Assert-TargetAspectRatio -Ratio $Ratio -TargetWidth $TargetWidth -TargetHeight $TargetHeight

    if ($OutputDpi -le 0) {
        throw "DPI musi byc wieksze od zera."
    }

    New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null

    if (-not $sourceItem.PSIsContainer) {
        $items = @($sourceItem)
    } elseif ($IncludeSubfolders) {
        $items = Get-ChildItem -LiteralPath $SourceFolder -Recurse -Force -ErrorAction Stop
    } else {
        $items = Get-ChildItem -LiteralPath $SourceFolder -Force -ErrorAction Stop
    }

    $destinationPrefix = $destinationFull + [System.IO.Path]::DirectorySeparatorChar
    $files = @(
        $items |
            Where-Object {
                -not $_.PSIsContainer -and
                ($_.Extension -match '^\.(jpg|jpeg)$') -and
                -not ($sourceItem.PSIsContainer -and (Get-RelativePathCompat -BasePath $sourceRoot -FullPath $_.FullName) -match '(^|[\\/])resize[\\/]') -and
                -not ([System.IO.Path]::GetFullPath($_.FullName).StartsWith(
                    $destinationPrefix,
                    [System.StringComparison]::OrdinalIgnoreCase
                ))
            }
    )

    if ($files.Count -eq 0) {
        throw "Nie znaleziono plikow JPG w wybranym folderze."
    }

    & $OnMessage ("Znaleziono plikow JPG: {0}" -f $files.Count)
    if ($Ratio -eq "Auto") {
        $longSide = [Math]::Max($TargetWidth, $TargetHeight)
        $shortSide = [Math]::Min($TargetWidth, $TargetHeight)
        & $OnMessage ("Format wyniku: Auto - poziome {0} x {1}, pionowe {1} x {0}" -f $longSide, $shortSide)
    } else {
        & $OnMessage ("Format wyniku: {0} ({1} x {2})" -f $Ratio, $TargetWidth, $TargetHeight)
    }
    & $OnMessage ("Tryb: {0}" -f $(if ($ResizeMode -eq "Crop") { "przyciecie do kadru" } else { "dopasowanie z marginesami" }))
    & $OnMessage ("Jakosc JPG: {0}, DPI: {1}" -f $JpegQuality, $OutputDpi)
    & $OnMessage ("Folder wynikowy: {0}" -f $DestinationFolder)

    $done = 0
    $failed = 0
    $cancelled = $false
    & $OnProgress 0 $files.Count ""

    foreach ($file in $files) {
        if (& $ShouldCancel) {
            $cancelled = $true
            break
        }
        $done += 1

        try {
            if ($IncludeSubfolders -and $sourceItem.PSIsContainer) {
                $relativePath = Get-RelativePathCompat -BasePath $sourceRoot -FullPath $file.FullName
            } else {
                $relativePath = $file.Name
            }

            $targetRelativePath = Add-ResizedSuffixToPath -RelativePath $relativePath
            $targetPath = Join-Path $DestinationFolder $targetRelativePath
            $targetFolder = Split-Path -Parent $targetPath
            New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
            $targetPath = Get-UniquePath -Path $targetPath
            $orientation = if ($Ratio -eq "Auto") { Get-ImageOrientation -SourcePath $file.FullName } else { "" }
            $targetSize = Get-TargetSizeForRatio `
                -Ratio $Ratio `
                -BaseWidth $TargetWidth `
                -BaseHeight $TargetHeight `
                -Orientation $orientation

            Resize-Jpeg `
                -SourcePath $file.FullName `
                -TargetPath $targetPath `
                -TargetWidth $targetSize.Width `
                -TargetHeight $targetSize.Height `
                -ResizeMode $ResizeMode `
                -JpegQuality $JpegQuality `
                -OutputDpi $OutputDpi

            if ($Ratio -eq "Auto") {
                & $OnMessage ("OK: {0} -> {1} ({2} x {3})" -f $file.Name, $targetSize.Ratio, $targetSize.Width, $targetSize.Height)
            } else {
                & $OnMessage ("OK: {0}" -f $file.Name)
            }
        } catch {
            $failed += 1
            & $OnMessage ("BLAD: {0} - {1}" -f $file.Name, $_.Exception.Message)
        }

        & $OnProgress $done $files.Count $file.Name
    }

    return [pscustomobject]@{
        Total = $files.Count
        Done = $done - $failed
        Failed = $failed
        Cancelled = $cancelled
        OutputFolder = $DestinationFolder
    }
}

. (Join-Path $PSScriptRoot 'ResizerUI.ps1')

if ([string]::IsNullOrWhiteSpace($InputFolder) -and $DroppedFolders.Count -eq 0) {
    Show-ResizerWindow
} elseif ($DroppedFolders.Count -gt 0) {
    Show-ResizerWindow -InitialFolders $DroppedFolders
} else {
    if ($OnlineStore) {
        $profile = Apply-OnlineStoreProfile
        $AspectRatio = $profile.AspectRatio
        $Mode = $profile.Mode
        $Width = $profile.Width
        $Height = $profile.Height
        $Quality = $profile.Quality
        $Dpi = $profile.Dpi
    }

    $size = Get-DefaultTargetSize -Ratio $AspectRatio
    if ($Width -le 0) {
        $Width = $size.Width
    }
    if ($Height -le 0) {
        $Height = $size.Height
    }

    $result = Invoke-BatchResize `
        -SourceFolder $InputFolder `
        -DestinationFolder $OutputFolder `
        -Ratio $AspectRatio `
        -ResizeMode $Mode `
        -TargetWidth $Width `
        -TargetHeight $Height `
        -JpegQuality $Quality `
        -OutputDpi $Dpi `
        -IncludeSubfolders:$Recursive

    Write-Host ("Gotowe. Udane: {0}, bledy: {1}, folder: {2}" -f $result.Done, $result.Failed, $result.OutputFolder)
}
