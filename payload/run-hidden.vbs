' ???? ? ??????????wscript ?????
Set args = WScript.Arguments
If args.Count < 1 Then WScript.Quit 1
Set sh = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & args(0) & """"
sh.Run cmd, 0, False
