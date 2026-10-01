' Copyright (c) 2026 Dariusz Trachimowicz / Digital Xperts
' SPDX-License-Identifier: GPL-3.0-only
' See LICENSE for terms. Distributed WITHOUT ANY WARRANTY.
Option Explicit

Dim shell, fso, folder, creatorPath, shortcutPath, powershellPath, command, exitCode, quiet, runError

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

folder = fso.GetParentFolderName(WScript.ScriptFullName)
creatorPath = fso.BuildPath(folder, "UtworzSkrotZIkona.ps1")
shortcutPath = fso.BuildPath(folder, "Resizer JPG.lnk")
powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
quiet = WScript.Arguments.Named.Exists("quiet")

If Not fso.FileExists(creatorPath) Then
    If Not quiet Then MsgBox "Nie znaleziono kreatora skrotu: " & creatorPath, 48, "Resizer JPG"
    WScript.Quit 1
End If

command = """" & powershellPath & """ -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & creatorPath & """"
On Error Resume Next
exitCode = shell.Run(command, 0, True)
runError = Err.Description
If Err.Number <> 0 Then
    On Error GoTo 0
    If Not quiet Then MsgBox "Nie mozna uruchomic kreatora skrotu: " & runError, 48, "Resizer JPG"
    WScript.Quit 1
End If
On Error GoTo 0

If exitCode <> 0 Then
    If Not quiet Then MsgBox "Nie udalo sie utworzyc skrotu (kod " & exitCode & ")." & vbCrLf & "Sprawdz pliki programu (w tym resizer-jpg.ico) oraz dostep do folderu programu i pamieci ikon w LOCALAPPDATA." & vbCrLf & "Kreator: " & creatorPath, 48, "Resizer JPG"
    WScript.Quit exitCode
End If

If Not quiet Then MsgBox "Utworzono skrot z ikona:" & vbCrLf & shortcutPath, 64, "Resizer JPG"
WScript.Quit 0
