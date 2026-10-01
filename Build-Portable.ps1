# Copyright (c) 2026 Dariusz Trachimowicz / Digital Xperts
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSE for terms. Distributed WITHOUT ANY WARRANTY.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'ResizerUpdates.ps1')
$metadata = Get-ResizerAppInfo
$files = @(Get-ResizerManagedFiles)
$portable = Join-Path $root 'ResizerJPG_portable'
$archivePath = Join-Path $root 'ResizerJPG_portable.zip'
$modules = @('ResizerUIModels.ps1','ResizerQueue.ps1')
foreach ($file in ($files + $modules)) {
    $source = Join-Path $root $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Brak pliku: $source" }
    if ([IO.Path]::GetExtension($file) -eq '.ps1') {
        $parseErrors = $null
        $parseTokens = $null
        [void][Management.Automation.Language.Parser]::ParseFile($source,[ref]$parseTokens,[ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
    }
}
[void](New-Item -ItemType Directory -Path $portable -Force)
$hashes = [ordered]@{}
foreach ($file in $files) {
    if ($file -eq 'ResizerUI.ps1') {
        # Keep the 16-entry archive accepted by the already deployed 2.0.0 updater.
        $parts = @($modules + @('ResizerUI.ps1') | ForEach-Object { Get-Content -LiteralPath (Join-Path $root $_) -Raw })
        [IO.File]::WriteAllText((Join-Path $portable $file),($parts -join [Environment]::NewLine))
    } else {
        Copy-Item -LiteralPath (Join-Path $root $file) -Destination (Join-Path $portable $file) -Force
        if ((Get-FileHash -LiteralPath (Join-Path $root $file)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $portable $file)).Hash) { throw "Niepoprawna kopia: $file" }
    }
    $hashes[$file] = (Get-FileHash -LiteralPath (Join-Path $portable $file) -Algorithm SHA256).Hash
}
$manifest = [ordered]@{version=$metadata.version;files=$hashes}
$manifestPath = Join-Path $portable 'package-manifest.json'
[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 4))
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $root 'package-manifest.json') -Force
$files += 'package-manifest.json'
$packageFiles = @($files | ForEach-Object { Join-Path $portable $_ })
Compress-Archive -LiteralPath $packageFiles -DestinationPath $archivePath -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    if ($archive.Entries.Count -ne $files.Count) { throw 'Niepoprawna liczba plikow w ZIP.' }
    foreach ($file in $files) {
        $entry = $archive.GetEntry($file)
        if ($null -eq $entry) { throw "Brak pliku w ZIP: $file" }
        $stream = $entry.Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') } finally { $stream.Dispose(); $sha.Dispose() }
        if ($hash -ne (Get-FileHash -LiteralPath (Join-Path $portable $file)).Hash) { throw "Niepoprawna zawartosc ZIP: $file" }
    }
} finally { $archive.Dispose() }
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($archivePath + '.sha256'),($archiveHash + '  ResizerJPG_portable.zip' + [Environment]::NewLine))
[void](Test-ResizerPackage -Directory $portable -ExpectedVersion $metadata.version)
& (Join-Path $root 'UtworzSkrotZIkona.ps1')
Write-Host "Paczka zweryfikowana: $archivePath"
