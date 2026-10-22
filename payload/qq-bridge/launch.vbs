Set args = WScript.Arguments
If args.Count = 0 Then
  action = "status"
Else
  action = args(0)
End If
Set sh = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File ""D:\qq-bridge\launch.ps1"" -Action " & action
sh.Run cmd, 0, False
