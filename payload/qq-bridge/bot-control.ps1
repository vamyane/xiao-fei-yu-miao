# 小肥鱼喵 · QQ 机器人控制台（WinForms）
# 双击桌面快捷方式打开；所有启动/停止都走任务计划程序，独立于 DSH 进程
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

[System.Windows.Forms.Application]::EnableVisualStyles()
$ErrorActionPreference = 'SilentlyContinue'
$ROOT = 'D:\qq-bridge'
$logBox = $null

function Test-Port([int]$p) {
  return [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)
}

function Get-DshProcesses {
  return @(Get-Process | Where-Object { $_.ProcessName -like 'DeepSeek Harness*' })
}

function Get-DshPort {
  $pids = @(Get-DshProcesses | Select-Object -ExpandProperty Id)
  if (-not $pids) { return $null }
  foreach ($ln in (netstat -ano | Select-String 'LISTENING')) {
    if ($ln.Line -match '^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$') {
      $port = [int]$Matches[1]; $procId = [int]$Matches[2]
      if ($pids -contains $procId) {
        try {
          $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port/" -UseBasicParsing -TimeoutSec 1
          if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { return $port }
        } catch {
          if ($_.Exception.Response) { return $port }
        }
      }
    }
  }
  return $null
}

function Add-Log([string]$msg) {
  if ($script:logBox) {
    $script:logBox.AppendText(("[" + (Get-Date -Format 'HH:mm:ss') + "] " + $msg + "`r`n"))
  }
}

function Run-Task([string]$name) {
  $p = Start-Process -FilePath 'schtasks.exe' -ArgumentList '/Run', '/TN', $name -NoNewWindow -PassThru -WindowStyle Hidden
  $p.WaitForExit()
  Add-Log ("任务 " + $name + " 已触发")
}

function Get-BridgeToken {
  try { return (Get-Content -Path (Join-Path $ROOT 'state\console-token') -Raw -Encoding UTF8).Trim() } catch { return '' }
}

# ---------------- 窗口 ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = '小肥鱼喵 · QQ 机器人控制台'
$form.Size = New-Object System.Drawing.Size(560, 560)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 26, 32)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = '小肥鱼喵 · QQ 机器人'
$title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 16, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(120, 210, 255)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20, 15)
$form.Controls.Add($title)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = '私聊 / 群聊 / 画图 / 语音 / 表情包  ·  关闭本窗口不影响运行'
$sub.ForeColor = [System.Drawing.Color]::FromArgb(150, 160, 175)
$sub.AutoSize = $true
$sub.Location = New-Object System.Drawing.Point(22, 52)
$form.Controls.Add($sub)

# 状态面板
$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Location = New-Object System.Drawing.Point(20, 82)
$statusPanel.Size = New-Object System.Drawing.Size(505, 150)
$statusPanel.BackColor = [System.Drawing.Color]::FromArgb(34, 37, 46)
$form.Controls.Add($statusPanel)

$statusLabels = @{}
$names = @(
  @{ key = 'dsh'; text = 'DSH（大脑）' },
  @{ key = 'snowluma'; text = 'SnowLuma（QQ 网关）' },
  @{ key = 'bridge'; text = 'qq-bridge（桥接）' },
  @{ key = 'comfy'; text = 'ComfyUI（画图）' }
)
$y = 12
foreach ($n in $names) {
  $dot = New-Object System.Windows.Forms.Label
  $dot.Text = '●'
  $dot.ForeColor = [System.Drawing.Color]::Gray
  $dot.AutoSize = $true
  $dot.Location = New-Object System.Drawing.Point(14, $y)
  $statusPanel.Controls.Add($dot)

  $lbl = New-Object System.Windows.Forms.Label
  $lbl.Text = $n.text
  $lbl.AutoSize = $true
  $lbl.Location = New-Object System.Drawing.Point(38, $y)
  $statusPanel.Controls.Add($lbl)

  $val = New-Object System.Windows.Forms.Label
  $val.Text = '检测中…'
  $val.AutoSize = $true
  $val.ForeColor = [System.Drawing.Color]::FromArgb(150, 160, 175)
  $val.Location = New-Object System.Drawing.Point(250, $y)
  $statusPanel.Controls.Add($val)

  $statusLabels[$n.key] = @{ dot = $dot; val = $val }
  $y += 33
}

function Update-Status {
  $dshPort = Get-DshPort
  $s = $statusLabels
  if ($dshPort) {
    $s.dsh.dot.ForeColor = [System.Drawing.Color]::FromArgb(80, 220, 120)
    $s.dsh.val.Text = "运行中 · 端口 $dshPort"
  } else {
    $s.dsh.dot.ForeColor = [System.Drawing.Color]::FromArgb(230, 90, 90)
    $s.dsh.val.Text = '未运行'
  }
  $pairs = @(
    @{ key = 'snowluma'; port = 5099; label = '运行中' },
    @{ key = 'bridge'; port = 3100; label = '运行中' },
    @{ key = 'comfy'; port = 8188; label = '运行中' }
  )
  foreach ($p in $pairs) {
    if (Test-Port $p.port) {
      $s[$p.key].dot.ForeColor = [System.Drawing.Color]::FromArgb(80, 220, 120)
      $s[$p.key].val.Text = "$($p.label) · 端口 $($p.port)"
    } else {
      $s[$p.key].dot.ForeColor = [System.Drawing.Color]::FromArgb(230, 90, 90)
      $s[$p.key].val.Text = '未运行'
    }
  }
}

# 按钮
function New-Btn([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, $color) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $text
  $b.Location = New-Object System.Drawing.Point($x, $y)
  $b.Size = New-Object System.Drawing.Size($w, $h)
  $b.FlatStyle = 'Flat'
  $b.FlatAppearance.BorderSize = 0
  $b.BackColor = $color
  $b.ForeColor = [System.Drawing.Color]::White
  $b.Cursor = [System.Windows.Forms.Cursors]::Hand
  return $b
}

$green = [System.Drawing.Color]::FromArgb(46, 150, 92)
$red = [System.Drawing.Color]::FromArgb(170, 60, 60)
$blue = [System.Drawing.Color]::FromArgb(46, 100, 170)
$gray = [System.Drawing.Color]::FromArgb(60, 64, 74)

$btnStart = New-Btn '▶ 启动全部' 20 250 150 46 $green
$btnStart.Add_Click({ Run-Task 'QQBotStart'; Add-Log '启动中，约 20~60 秒后全部就绪'; Start-Sleep -Seconds 3; Update-Status })
$form.Controls.Add($btnStart)

$btnStop = New-Btn '■ 停止全部' 185 250 150 46 $red
$btnStop.Add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show('停止会关闭 SnowLuma（QQ 掉线）和 ComfyUI，DSH 保留。确定？', '确认停止', 'YesNo', 'Question')
    if ($r -eq 'Yes') { Run-Task 'QQBotStop'; Start-Sleep -Seconds 3; Add-Log '已停止'; Update-Status }
  })
$form.Controls.Add($btnStop)

$btnRestart = New-Btn '↻ 重启' 350 250 150 46 $gray
$btnRestart.Add_Click({ Run-Task 'QQBotStop'; Start-Sleep -Seconds 4; Run-Task 'QQBotStart'; Add-Log '重启中'; Start-Sleep -Seconds 3; Update-Status })
$form.Controls.Add($btnRestart)

$btnDsh = New-Btn 'DSH 窗口' 20 306 150 40 $blue
$btnDsh.Add_Click({
    $procs = Get-DshProcesses | Where-Object { $_.MainWindowHandle -ne 0 }
    if ($procs) { [Win32]::ShowWindow($procs[0].MainWindowHandle, 9) | Out-Null; [Win32]::SetForegroundWindow($procs[0].MainWindowHandle) | Out-Null }
    elseif (Test-Path 'D:\dsh\DeepSeek Harness.exe') { Start-Process 'D:\dsh\DeepSeek Harness.exe'; Add-Log '已启动 DSH' }
    else { Add-Log '找不到 DSH 可执行文件' }
  })
$form.Controls.Add($btnDsh)

$btnConsole = New-Btn '桥接控制台' 185 306 150 40 $gray
$btnConsole.Add_Click({
    $tok = Get-BridgeToken
    if ($tok) { Set-Clipboard -Value $tok; Add-Log '桥接令牌已复制到剪贴板，登录时粘贴' }
    Start-Process 'http://127.0.0.1:3100'
  })
$form.Controls.Add($btnConsole)

$btnSnow = New-Btn 'SnowLuma' 350 306 150 40 $gray
$btnSnow.Add_Click({ Start-Process 'http://127.0.0.1:5099' })
$form.Controls.Add($btnSnow)

$btnComfy = New-Btn 'ComfyUI' 20 352 150 40 $gray
$btnComfy.Add_Click({ Start-Process 'http://127.0.0.1:8188' })
$form.Controls.Add($btnComfy)

$btnLogs = New-Btn '打开日志' 185 352 150 40 $gray
$btnLogs.Add_Click({ Start-Process 'explorer.exe' -ArgumentList (Join-Path $ROOT 'state') })
$form.Controls.Add($btnLogs)

$btnQuit = New-Btn '退出控制台' 350 352 150 40 $gray
$btnQuit.Add_Click({ $form.Close() })
$form.Controls.Add($btnQuit)

# 日志框
$script:logBox = New-Object System.Windows.Forms.TextBox
$script:logBox.Multiline = $true
$script:logBox.ScrollBars = 'Vertical'
$script:logBox.ReadOnly = $true
$script:logBox.Location = New-Object System.Drawing.Point(20, 404)
$script:logBox.Size = New-Object System.Drawing.Size(505, 100)
$script:logBox.BackColor = [System.Drawing.Color]::FromArgb(16, 18, 22)
$script:logBox.ForeColor = [System.Drawing.Color]::FromArgb(180, 200, 215)
$script:logBox.BorderStyle = 'FixedSingle'
$form.Controls.Add($script:logBox)

Update-Status
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Update-Status })
$timer.Start()

[System.Windows.Forms.Application]::Run($form)
