# Copyright (c) 2026 Dariusz Trachimowicz / Digital Xperts
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSE for terms. Distributed WITHOUT ANY WARRANTY.
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

# Notify only this saved shortcut; leave global associations and user apps alone.
try {
    if (-not ('ResizerShortcutShell' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ResizerShortcutShell {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    public static extern void SHChangeNotify(uint eventId, uint flags,
        [MarshalAs(UnmanagedType.LPWStr)] string item1, IntPtr item2);
}
'@ -ErrorAction Stop
    }
    # SHCNE_UPDATEITEM = 0x2000; SHCNF_PATHW = 0x0005.
    [ResizerShortcutShell]::SHChangeNotify(0x2000, 0x0005, $shortcutPath, [IntPtr]::Zero)
} catch {
    Write-Warning ("Skrot zapisany, ale powiadomienie Windows o ikonie nie powiodlo sie: " + $_.Exception.Message)
}

Write-Host "Utworzono skrot z ikona:"
Write-Host $shortcutPath
