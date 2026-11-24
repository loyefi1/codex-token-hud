' Codex Token HUD detached launcher
' Starts the HUD through WScript.Shell.Run so it is not attached to any
' console window: closing a PowerShell window will not terminate the HUD.
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")

dir = fso.GetParentFolderName(WScript.ScriptFullName)
script = dir & "\overlay.ps1"

If Not fso.FileExists(script) Then
    WScript.Quit 1
End If

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & script & """"
sh.Run cmd, 0, False