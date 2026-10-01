# Copyright (c) 2026 Dariusz Trachimowicz / Digital Xperts
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSE for terms. Distributed WITHOUT ANY WARRANTY.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
$portable = Join-Path $root 'ResizerJPG_portable'
$metadata = Get-Content -LiteralPath (Join-Path $root 'AppInfo.json') -Raw | ConvertFrom-Json
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $portable 'ResizerUI.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Portable UI must parse in PowerShell 5.1.' }
$functions = @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] } | Select-Object -ExpandProperty Name)
foreach ($name in @('Get-ResizerQueueItems','Invoke-ResizerQueueExport','Get-ResizerPreviewData','Show-ResizerWindow')) {
    if ($name -notin $functions) { throw "Portable UI must include its queue module: $name" }
}
if ((Get-Content -LiteralPath (Join-Path $portable 'ResizerUI.ps1') -Raw) -notmatch 'class ResizerPhoto') { throw 'Portable UI must contain its WPF notification model.' }
$legacy = & git -C $root show v2.0.0:ResizerUpdates.ps1
if ($LASTEXITCODE -ne 0) { throw 'The original v2.0.0 updater is required for compatibility testing.' }
. ([scriptblock]::Create(($legacy -join [Environment]::NewLine)))
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('resizer-compatible-test-'+[guid]::NewGuid())
try {
    Expand-ResizerPackage -ArchivePath (Join-Path $root 'ResizerJPG_portable.zip') -Destination $fixture
    $package = Test-ResizerPackage -Directory $fixture -ExpectedVersion $metadata.version
    if ($package.Files.Count -ne 16) { throw 'Existing 2.0.0 updater must accept the original 16-entry archive.' }
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $fixture 'ResizerJPG.ps1'),[ref]$tokens,[ref]$errors)
    foreach ($statement in $ast.EndBlock.Statements) { if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) { . ([scriptblock]::Create($statement.Extent.Text)) } }
    . (Join-Path $fixture 'ResizerUI.ps1')
    if (-not ('ResizerPhoto' -as [type]) -or $null -eq (Get-Command Get-ResizerQueueItems -ErrorAction SilentlyContinue)) { throw 'Extracted package must load without development modules.' }
    Write-Host 'PASS: standalone queue/models and original 2.0.0 ZIP/manifest updater compatibility.'
} finally {
    $full = [IO.Path]::GetFullPath($fixture)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\resizer-compatible-test-'
    if ($full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full)) { Remove-Item -LiteralPath $full -Recurse -Force }
}
