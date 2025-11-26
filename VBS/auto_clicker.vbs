Option Explicit
'-----------------------------------------------------------------------------
' Auto Clicker (VBScript)
' Usage examples:
'   cscript //nologo auto_clicker.vbs            ' default: 500 ms interval, 50 clicks
'   cscript //nologo auto_clicker.vbs 250 25     ' 250 ms interval, 25 clicks
'
' The script shells out to PowerShell to call the Win32 mouse_event API. Ensure
' PowerShell is available and that the app has permission to control the mouse.
'-----------------------------------------------------------------------------

Const DEFAULT_INTERVAL = 500   ' milliseconds
Const DEFAULT_COUNT    = 50

Dim intervalMs, clickCount, args
intervalMs = DEFAULT_INTERVAL
clickCount = DEFAULT_COUNT
Set args = WScript.Arguments

If args.Count > 0 Then
  If IsNumeric(args.Item(0)) Then intervalMs = CLng(args.Item(0))
End If
If args.Count > 1 Then
  If IsNumeric(args.Item(1)) Then clickCount = CLng(args.Item(1))
End If

If intervalMs < 1 Then
  WScript.Echo "Interval must be at least 1 millisecond."
  WScript.Quit 1
End If
If clickCount < 1 Then
  WScript.Echo "Click count must be at least 1."
  WScript.Quit 1
End If

Dim fso, tempFolder, psPath, shell, tempName
Set fso = CreateObject("Scripting.FileSystemObject")
tempFolder = fso.GetSpecialFolder(2) ' TemporaryFolder
Randomize
tempName = "vb_autoclick_" & CLng(Timer * 1000) & Int(Rnd * 1000) & ".ps1"
psPath = tempFolder & "\" & tempName

Dim writer
Set writer = fso.CreateTextFile(psPath, True)
writer.WriteLine("$ErrorActionPreference = 'Stop'")
writer.WriteLine("$count = " & clickCount)
writer.WriteLine("$interval = " & intervalMs)
writer.WriteLine("Add-Type -Namespace Native -Name Mouse -MemberDefinition @'")
writer.WriteLine("using System;")
writer.WriteLine("using System.Runtime.InteropServices;")
writer.WriteLine("public static class MouseHelper {")
writer.WriteLine("    [DllImport(\"user32.dll\", SetLastError = true)]")
writer.WriteLine("    public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);")
writer.WriteLine("}")
writer.WriteLine("'@;")
writer.WriteLine("$down = 0x0002")
writer.WriteLine("$up   = 0x0004")
writer.WriteLine("for ($i = 1; $i -le $count; $i++) {")
writer.WriteLine("    [Native.MouseHelper]::mouse_event($down,0,0,0,[UIntPtr]::Zero)")
writer.WriteLine("    [Native.MouseHelper]::mouse_event($up,0,0,0,[UIntPtr]::Zero)")
writer.WriteLine("    if ($i -lt $count) { Start-Sleep -Milliseconds $interval }")
writer.WriteLine("}")
writer.Close

Set shell = CreateObject("WScript.Shell")
Dim psCommand, exitCode
psCommand = "powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File """ & psPath & """"
exitCode = shell.Run(psCommand, 0, True)

On Error Resume Next
fso.DeleteFile psPath
On Error GoTo 0

If exitCode <> 0 Then
  WScript.Echo "PowerShell exited with code " & exitCode
  WScript.Quit exitCode
End If

WScript.Echo "Completed " & clickCount & " click(s) at " & intervalMs & " ms intervals."
