' Copyright (c) 2026 Dariusz Trachimowicz / Digital Xperts
' SPDX-License-Identifier: GPL-3.0-only
' See LICENSE for terms. Distributed WITHOUT ANY WARRANTY.
Option Explicit

Dim shell, fso, folder, launcherPath, iconPath, shortcutPath, shortcut, wscriptPath

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

folder = fso.GetParentFolderName(WScript.ScriptFullName)
launcherPath = fso.BuildPath(folder, "Uruchom Resizer JPG.vbs")
iconPath = fso.BuildPath(folder, "resizer-jpg.ico")
shortcutPath = fso.BuildPath(folder, "Resizer JPG.lnk")
wscriptPath = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\wscript.exe"

If Not fso.FileExists(launcherPath) Then
    MsgBox "Nie znaleziono uruchamiacza bez konsoli: " & launcherPath, 48, "Resizer JPG"
    WScript.Quit 1
End If

If Not fso.FileExists(iconPath) Then
    MsgBox "Nie znaleziono ikony: " & iconPath, 48, "Resizer JPG"
    WScript.Quit 1
End If

Set shortcut = shell.CreateShortcut(shortcutPath)
shortcut.TargetPath = wscriptPath
shortcut.Arguments = "//nologo """ & launcherPath & """"
shortcut.WorkingDirectory = folder
shortcut.IconLocation = iconPath & ",0"
shortcut.Description = "Resizer JPG - tworca oprogramowania: Dariusz Trachimowicz"
shortcut.Save

MsgBox "Utworzono skrot z ikona:" & vbCrLf & shortcutPath, 64, "Resizer JPG"
