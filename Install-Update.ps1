param(
    [Parameter(Mandatory=$true)][string]$AppDirectory,
    [Parameter(Mandatory=$true)][string]$StageDirectory,
    [Parameter(Mandatory=$true)][string]$ExpectedVersion,
    [int]$ParentProcessId = 0,
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ResizerUpdates.ps1')
$appRoot = [IO.Path]::GetFullPath($AppDirectory).TrimEnd('\')
$stageRoot = [IO.Path]::GetFullPath($StageDirectory).TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $appRoot 'ResizerJPG.ps1') -PathType Leaf) -or $appRoot -eq $stageRoot) { throw 'Niepoprawny katalog programu.' }
$package = Test-ResizerPackage -Directory $stageRoot -ExpectedVersion $ExpectedVersion
if ($ParentProcessId -gt 0) {
    $process = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
    if ($null -ne $process -and -not $process.WaitForExit(60000)) { throw 'Program nadal pracuje. Aktualizacja nie zostala zainstalowana.' }
}
$backupRoot = Join-Path $appRoot ('_updates\backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
[void](New-Item -ItemType Directory -Path $backupRoot -Force)
$touched = @()
try {
    # Only application-owned files are installed; photo folders and user files are untouched.
    foreach ($file in $package.Files) {
        $target = Join-Path $appRoot $file
        if (Test-Path -LiteralPath $target -PathType Leaf) { Copy-Item -LiteralPath $target -Destination (Join-Path $backupRoot $file) -Force }
    }
    foreach ($file in $package.Files) {
        $target = Join-Path $appRoot $file
        $touched += $file
        Copy-Item -LiteralPath (Join-Path $stageRoot $file) -Destination $target -Force
    }
    [void](Test-ResizerPackage -Directory $appRoot -ExpectedVersion $ExpectedVersion)
    & (Join-Path $appRoot 'UtworzSkrotZIkona.ps1') | Out-Null
    $status = @{status='installed';version=$ExpectedVersion;backup=$backupRoot;time=[DateTime]::UtcNow.ToString('o')}
    [IO.File]::WriteAllText((Join-Path $appRoot '_updates\status.json'),($status | ConvertTo-Json))
} catch {
    $failure = $_.Exception.Message
    $rollbackErrors = @()
    foreach ($file in $touched) {
        $backup = Join-Path $backupRoot $file
        $target = Join-Path $appRoot $file
        try {
            if (Test-Path -LiteralPath $backup) {
                if ((Test-Path -LiteralPath $target) -and (Get-FileHash -LiteralPath $target).Hash -eq (Get-FileHash -LiteralPath $backup).Hash) { continue }
                Copy-Item -LiteralPath $backup -Destination $target -Force
            } elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
        } catch { $rollbackErrors += "$file : $($_.Exception.Message)" }
    }
    $statusName = if ($rollbackErrors.Count) { 'rollback_failed' } else { 'failed' }
    [IO.File]::WriteAllText((Join-Path $appRoot '_updates\status.json'),(@{status=$statusName;error=$failure;backup=$backupRoot;rollbackErrors=$rollbackErrors} | ConvertTo-Json))
    if (-not $NoRestart) {
        Add-Type -AssemblyName System.Windows.Forms
        $message = if ($rollbackErrors.Count) { "Aktualizacja nie powiodla sie. Przywracanie wymaga sprawdzenia. Kopia: $backupRoot" } else { 'Aktualizacja nie powiodla sie. Przywrocono poprzednie pliki.' }
        [void][Windows.Forms.MessageBox]::Show("$message`n$failure",'Resizer JPG - Digital Xperts')
    }
    throw $failure
}
if (-not $NoRestart) {
    $launcher = Join-Path $appRoot 'Uruchom Resizer JPG.vbs'
    Start-Process -FilePath wscript.exe -WindowStyle Hidden -ArgumentList ('//nologo "{0}"' -f $launcher)
}
