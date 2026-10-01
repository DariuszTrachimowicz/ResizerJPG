# Load after the core functions in ResizerJPG.ps1; this module has no WPF dependencies.
function Get-ResizerQueueFolderPath {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $volumeRoot = [IO.Path]::GetPathRoot($full)
    if ($full.TrimEnd([char[]]@('\','/')).Equals($volumeRoot.TrimEnd([char[]]@('\','/')), [StringComparison]::OrdinalIgnoreCase)) {
        return $volumeRoot
    }
    return Get-NormalizedFolderPath -Path $full
}

function Test-ResizerQueueDescendant {
    param([string]$Path, [string]$Folder)
    $prefix = (Get-ResizerQueueFolderPath -Path $Folder).TrimEnd([char[]]@('\','/')) + [IO.Path]::DirectorySeparatorChar
    return [IO.Path]::GetFullPath($Path).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function ConvertTo-ResizerQueuePreviewBytes {
    param([Drawing.Image]$Image, [int]$MaxEdge)
    $scale = [Math]::Min(1.0, $MaxEdge / [double][Math]::Max($Image.Width, $Image.Height))
    $width = [Math]::Max(1, [int][Math]::Round($Image.Width * $scale))
    $height = [Math]::Max(1, [int][Math]::Round($Image.Height * $scale))
    $bitmap = $null; $graphics = $null; $stream = $null
    try {
        $bitmap = New-Object Drawing.Bitmap($width, $height, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([Drawing.Color]::White)
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($Image, 0, 0, $width, $height)
        $stream = New-Object IO.MemoryStream
        $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Jpeg)
        return [pscustomobject]@{ Bytes = [byte[]]$stream.ToArray(); Width = $width; Height = $height }
    } finally {
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $bitmap) { $bitmap.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-ResizerQueueItems {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$Paths,
        [switch]$IncludeSubfolders,
        [string]$ExcludedFolder = '',
        [scriptblock]$ShouldCancel = { $false },
        [scriptblock]$OnItem = { param($Item) },
        [scriptblock]$OnProgress = { param($Count, $Name) }
    )
    $inputs = New-Object 'Collections.Generic.List[object]'
    $roots = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $Paths) {
        if (& $ShouldCancel) { return }
        if ([string]::IsNullOrWhiteSpace($path)) { throw 'Sciezka zrodla nie moze byc pusta.' }
        $entry = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if ($entry.PSIsContainer -or $entry.Extension -match '^\.(jpg|jpeg)$') {
            $inputs.Add($entry)
            $root = if ($entry.PSIsContainer) { $entry.FullName } else { $entry.DirectoryName }
            [void]$roots.Add((Get-ResizerQueueFolderPath -Path $root))
        }
    }
    # Resolve all roots first so a child dropped before its parent has the same identity.
    $orderedRoots = @($roots | Sort-Object Length, { $_ })
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $items = New-Object 'Collections.Generic.List[object]'
    $excluded = if ($ExcludedFolder) { Get-ResizerQueueFolderPath -Path $ExcludedFolder } else { '' }
    foreach ($entry in $inputs) {
        if (& $ShouldCancel) { break }
        $pending = New-Object 'Collections.Generic.Stack[object]'
        $pending.Push($entry)
        while ($pending.Count -gt 0) {
            if (& $ShouldCancel) { break }
            $current = $pending.Pop()
            $fullPath = [IO.Path]::GetFullPath($current.FullName)
            if ($excluded -and ($fullPath.Equals($excluded, [StringComparison]::OrdinalIgnoreCase) -or
                (Test-ResizerQueueDescendant -Path $fullPath -Folder $excluded))) { continue }
            $sourceRoot = $null
            foreach ($root in $orderedRoots) {
                if ($fullPath.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
                    (Test-ResizerQueueDescendant -Path $fullPath -Folder $root)) { $sourceRoot = $root; break }
            }
            if ($current.PSIsContainer) {
                $relativeFolder = Get-RelativePathCompat -BasePath $sourceRoot -FullPath $fullPath
                if ($relativeFolder -match '(^|[\\/])resize([\\/]|$)') { continue }
                # Do not follow junctions: cycles and output aliases are not source subfolders.
                if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                # Reverse the push order so the LIFO walk displays names ascending.
                foreach ($child in (Get-ChildItem -LiteralPath $fullPath -Force -ErrorAction Stop | Sort-Object Name -Descending)) {
                    if (& $ShouldCancel) { break }
                    if (-not $child.PSIsContainer -or $IncludeSubfolders) { $pending.Push($child) }
                }
                continue
            }
            if ($current.Extension -notmatch '^\.(jpg|jpeg)$' -or -not $seen.Add($fullPath)) { continue }
            $relativePath = Get-RelativePathCompat -BasePath $sourceRoot -FullPath $fullPath
            # Explicit file drops bypass only the resize-directory exclusion, as in the core CLI.
            if ($entry.PSIsContainer -and $relativePath -match '(^|[\\/])resize[\\/]') { continue }
            $item = [pscustomobject]@{
                FullPath = $fullPath
                SourceRoot = $sourceRoot
                SourcePath = $sourceRoot
                SourceName = [IO.Path]::GetFileName($sourceRoot)
                RelativePath = $relativePath
                Name = $current.Name
                Width = 0; Height = 0; Orientation = ''
                ThumbnailBytes = [byte[]]@(); Error = ''
            }
            $image = $null
            try {
                $image = [Drawing.Image]::FromFile($fullPath)
                Apply-ExifOrientation -Image $image
                $item.Width = $image.Width; $item.Height = $image.Height
                $item.Orientation = if ($image.Height -gt $image.Width) { 'Portrait' } else { 'Landscape' }
                $thumbnail = ConvertTo-ResizerQueuePreviewBytes -Image $image -MaxEdge 160
                $item.ThumbnailBytes = $thumbnail.Bytes
            } catch { $item.Error = $_.Exception.Message } finally {
                if ($null -ne $image) { $image.Dispose() }
            }
            $items.Add($item)
            $null = & $OnItem $item
            $null = & $OnProgress $items.Count $item.Name
        }
    }
    return $items.ToArray()
}

function Get-ResizerQueueTargetPath {
    param([Parameter(Mandatory=$true)]$Item, [string]$DestinationFolder = '')
    if ([string]::IsNullOrWhiteSpace([string]$Item.SourceRoot)) { throw 'Brak folderu zrodla.' }
    $sourceRoot = Get-ResizerQueueFolderPath -Path $Item.SourceRoot
    $destination = if ([string]::IsNullOrWhiteSpace($DestinationFolder)) {
        Join-Path $sourceRoot 'resize'
    } else { Get-ResizerQueueFolderPath -Path $DestinationFolder }
    if ($sourceRoot.Equals((Get-ResizerQueueFolderPath -Path $destination), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Folder wynikowy musi byc inny niz folder ze zdjeciami.'
    }
    $relative = [string]$Item.RelativePath
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':')) {
        throw 'Nieprawidlowa sciezka wzgledna zdjecia.'
    }
    foreach ($part in ($relative -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($part) -or $part -eq '.' -or $part -eq '..' -or
            $part -ne $part.TrimEnd([char[]]@(' ','.')) -or $part.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            throw 'Sciezka zdjecia nie moze wychodzic poza folder wynikowy.'
        }
    }
    if ([IO.Path]::GetExtension($relative) -notmatch '^\.(jpg|jpeg)$') { throw 'Wynik musi miec rozszerzenie JPG lub JPEG.' }
    $target = [IO.Path]::GetFullPath((Join-Path $destination (Add-ResizedSuffixToPath -RelativePath $relative)))
    if (-not (Test-ResizerQueueDescendant -Path $target -Folder $destination)) { throw 'Nieprawidlowa sciezka wyniku.' }
    if ($target.Equals([IO.Path]::GetFullPath($Item.FullPath), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Wynik nie moze nadpisac oryginalu.'
    }
    # Existing junctions must not redirect a relative output path outside the destination.
    $parent = [IO.Path]::GetDirectoryName($target)
    while ($parent) {
        if (Test-Path -LiteralPath $parent) {
            $directory = Get-Item -LiteralPath $parent -Force -ErrorAction Stop
            if (-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Folder wynikowy nie moze byc plikiem ani dowiazaniem.'
            }
        }
        $parent = [IO.Path]::GetDirectoryName($parent)
    }
    return $target
}

function Invoke-ResizerQueueExport {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Items,
        [string]$DestinationFolder = '',
        [ValidateSet('Auto','16:9','9:16')][string]$Ratio = 'Auto',
        [ValidateSet('Pad','Crop')][string]$ResizeMode = 'Pad',
        [int]$TargetWidth = 2880, [int]$TargetHeight = 1920,
        [ValidateRange(1,100)][int]$JpegQuality = 85,
        [ValidateRange(1,600)][int]$OutputDpi = 72,
        [scriptblock]$ShouldCancel = { $false },
        [scriptblock]$OnProgress = { param($Done,$Total,$Item,$Success,$OutputPath,$ErrorMessage) },
        [scriptblock]$OnMessage = { param($Message) }
    )
    Assert-TargetAspectRatio -Ratio $Ratio -TargetWidth $TargetWidth -TargetHeight $TargetHeight
    $folders = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $done = 0; $failed = 0; $attempted = 0; $cancelled = $false
    $null = & $OnMessage ("Zaznaczonych zdjec: {0}" -f $Items.Count)
    foreach ($item in $Items) {
        if (& $ShouldCancel) { $cancelled = $true; break }
        $success = $false; $targetPath = ''; $errorMessage = ''
        try {
            if ($item.Error) { throw ([string]$item.Error) }
            $targetPath = Get-ResizerQueueTargetPath -Item $item -DestinationFolder $DestinationFolder
            $destination = if ([string]::IsNullOrWhiteSpace($DestinationFolder)) {
                Join-Path $item.SourceRoot 'resize'
            } else { Get-ResizerQueueFolderPath -Path $DestinationFolder }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($targetPath))
            $targetPath = Get-UniquePath -Path $targetPath
            $orientation = if ($Ratio -eq 'Auto') { Get-ImageOrientation -SourcePath $item.FullPath } else { '' }
            $size = Get-TargetSizeForRatio -Ratio $Ratio -BaseWidth $TargetWidth -BaseHeight $TargetHeight -Orientation $orientation
            Resize-Jpeg -SourcePath $item.FullPath -TargetPath $targetPath -TargetWidth $size.Width -TargetHeight $size.Height `
                -ResizeMode $ResizeMode -JpegQuality $JpegQuality -OutputDpi $OutputDpi
            [void]$folders.Add($destination)
            $done++; $success = $true
        } catch { $failed++; $errorMessage = $_.Exception.Message }
        $attempted++
        $message = if ($success) { "OK: {0} -> {1}" -f $item.Name,$targetPath } else { "BLAD: {0} - {1}" -f $item.Name,$errorMessage }
        $null = & $OnMessage $message
        $null = & $OnProgress $attempted $Items.Count $item $success $targetPath $errorMessage
    }
    return [pscustomobject]@{ Total=$Items.Count; Done=$done; Failed=$failed; Cancelled=$cancelled; OutputFolders=[string[]]@($folders) }
}

function Get-ResizerPreviewData {
    param([Parameter(Mandatory=$true)][string]$Path, [hashtable]$Options = @{}, [switch]$Original)
    $settings = @{ Width=2880; Height=1920; Ratio='Auto'; Mode='Pad'; Quality=85; Dpi=72 }
    foreach ($key in $Options.Keys) {
        if (-not $settings.ContainsKey($key)) { throw "Nieznana opcja podgladu: $key" }
        $settings[$key] = $Options[$key]
    }
    if ($settings.Ratio -notin @('Auto','16:9','9:16') -or $settings.Mode -notin @('Pad','Crop')) { throw 'Nieprawidlowe proporcje lub tryb podgladu.' }
    Assert-TargetAspectRatio -Ratio $settings.Ratio -TargetWidth $settings.Width -TargetHeight $settings.Height
    if ([int]$settings.Quality -lt 1 -or [int]$settings.Quality -gt 100 -or [int]$settings.Dpi -lt 1 -or [int]$settings.Dpi -gt 600) {
        throw 'Nieprawidlowa jakosc JPG lub DPI.'
    }
    $image = $null; $temp = $null
    try {
        $image = [Drawing.Image]::FromFile([IO.Path]::GetFullPath($Path))
        Apply-ExifOrientation -Image $image
        $sourceWidth = $image.Width; $sourceHeight = $image.Height
        $orientation = if ($sourceHeight -gt $sourceWidth) { 'Portrait' } else { 'Landscape' }
        $size = Get-TargetSizeForRatio -Ratio $settings.Ratio -BaseWidth $settings.Width -BaseHeight $settings.Height -Orientation $orientation
        if ($Original) {
            $preview = ConvertTo-ResizerQueuePreviewBytes -Image $image -MaxEdge 2048
            $bytes = $preview.Bytes; $width = $preview.Width; $height = $preview.Height
        } else {
            $image.Dispose(); $image = $null
            $temp = Join-Path ([IO.Path]::GetTempPath()) ('resizer-preview-' + [guid]::NewGuid().ToString('N') + '.jpg')
            Resize-Jpeg -SourcePath $Path -TargetPath $temp -TargetWidth $size.Width -TargetHeight $size.Height `
                -ResizeMode $settings.Mode -JpegQuality $settings.Quality -OutputDpi $settings.Dpi
            $bytes = [IO.File]::ReadAllBytes($temp)
            $width = $size.Width; $height = $size.Height
        }
        return [pscustomobject]@{
            Bytes = [byte[]]$bytes; SourceWidth = $sourceWidth; SourceHeight = $sourceHeight
            TargetWidth = $size.Width; TargetHeight = $size.Height; Width = $width; Height = $height
        }
    } finally {
        if ($null -ne $image) { $image.Dispose() }
        if ($temp -and [IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}
