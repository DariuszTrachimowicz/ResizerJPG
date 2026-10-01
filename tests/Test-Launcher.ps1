# Copyright (c) 2026 Dariusz Trachimowicz / Digital Xperts
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSE for terms. Distributed WITHOUT ANY WARRANTY.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('resizer-launch-test-' + [guid]::NewGuid())
[void](New-Item -ItemType Directory -Path $fixture)
try {
    $first = Join-Path $fixture 'Pierwszy folder'
    $second = Join-Path $fixture "Drugi folder O'Brien"
    [void](New-Item -ItemType Directory -Path $first,$second)
    Copy-Item -LiteralPath (Join-Path $root 'Uruchom Resizer JPG.vbs') -Destination $fixture
    $probe = @'
param([string[]]$DroppedFolders)
$receipt = @{ Paths = @($DroppedFolders); Apartment = [string][Threading.Thread]::CurrentThread.ApartmentState }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'receipt.json'), ($receipt | ConvertTo-Json))
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'ResizerJPG.ps1'),$probe)
    [IO.File]::WriteAllText((Join-Path $fixture 'ResizerUI.ps1'),'# Launcher probe')
    $launcher = Join-Path $fixture 'Uruchom Resizer JPG.vbs'
    Start-Process -FilePath wscript.exe -WindowStyle Hidden -ArgumentList ('//nologo "{0}" "{1}" "{2}"' -f $launcher,$first,$second) -Wait
    $receiptPath = Join-Path $fixture 'receipt.json'
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $receiptPath) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $receiptPath)) { throw 'Launcher did not invoke PowerShell.' }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.Paths.Count -ne 2 -or $receipt.Paths[0] -ne $first -or $receipt.Paths[1] -ne $second) { throw 'Launcher lost or incorrectly quoted dropped paths.' }
    if ($receipt.Apartment -ne 'STA') { throw 'GUI launcher must use STA.' }
    Write-Host 'PASS: real VBS launcher, two paths, spaces, apostrophe, STA.'
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\resizer-launch-test-'
    if ($resolvedFixture.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
