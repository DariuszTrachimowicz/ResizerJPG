Set-StrictMode -Version Latest

$folder = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcher = Join-Path $folder "Uruchom Resizer JPG.vbs"
$target = Join-Path $env:SystemRoot "System32\wscript.exe"
$icon = Join-Path $folder "resizer-jpg.ico"
$shortcutPath = Join-Path $folder "Resizer JPG.lnk"

if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "Nie znaleziono uruchamiacza bez konsoli: $launcher"
}

if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    throw "Nie znaleziono Windows Script Host: $target"
}

if (-not (Test-Path -LiteralPath $icon -PathType Leaf)) {
    throw "Nie znaleziono ikony: $icon"
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $target
$shortcut.Arguments = "//nologo ""$launcher"""
$shortcut.WorkingDirectory = $folder
$shortcut.IconLocation = "$icon,0"
$shortcut.Description = "Resizer JPG - tworca oprogramowania: Dariusz Trachimowicz"
$shortcut.Save()

Write-Host "Utworzono skrot z ikona:"
Write-Host $shortcutPath
