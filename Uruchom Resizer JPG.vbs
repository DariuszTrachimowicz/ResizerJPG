' Copyright (c) 2026 Dariusz Trachimowicz / Digital Xperts
' SPDX-License-Identifier: GPL-3.0-only
' See LICENSE for terms. Distributed WITHOUT ANY WARRANTY.
Option Explicit

Dim shell, fso, folder, scriptPath, powershellPath, command, scriptCommand, i

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

folder = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(folder, "ResizerJPG.ps1")
If Not fso.FileExists(scriptPath) Or Not fso.FileExists(fso.BuildPath(folder, "ResizerUI.ps1")) Then
    MsgBox "Brakuje plikow programu. Rozpakuj cala paczke Resizer JPG do jednego folderu.", 48, "Resizer JPG - Dariusz Trachimowicz"
    WScript.Quit 1
End If
powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
scriptCommand = "& '" & Replace(scriptPath, "'", "''") & "'"

If WScript.Arguments.Count > 0 Then
    scriptCommand = scriptCommand & " -DroppedFolders @("

    For i = 0 To WScript.Arguments.Count - 1
        If i > 0 Then scriptCommand = scriptCommand & ","
        scriptCommand = scriptCommand & "'" & Replace(WScript.Arguments(i), "'", "''") & "'"
    Next
    scriptCommand = scriptCommand & ")"
End If

scriptCommand = "try { " & scriptCommand & " } catch { Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Resizer JPG - Digital Xperts') | Out-Null; exit 1 }"
command = """" & powershellPath & """ -Sta -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command """ & scriptCommand & """"
shell.CurrentDirectory = folder
shell.Run command, 0, False
