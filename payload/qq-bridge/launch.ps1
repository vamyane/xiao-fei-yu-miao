# 小肥鱼喵 · 启动/停止状态窗口
# 用法：powershell -STA -File launch.ps1 -Action start|stop|status [-NoGui]
param(
  [string]$Action = 'status',
  [switch]$NoGui
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'SilentlyContinue'
$ROOT = 'D:\qq-bridge'

function Test-Port([int]$p) {
  return [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)
}

function Get-DshPort {
  $procs = @(Get-Process | Where-Object { $_.ProcessName -like 'DeepSeek Harness*' })
  if (-not $procs) { return $null }
  $pids = @($procs | Select-Object -ExpandProperty Id)
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

function Get-OneBotToken {
  $file = Get-ChildItem 'D:\SnowLuma\config' -Filter 'onebot_*.json' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $file) { return $null }
  try {
    $j = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    return $j.networks.httpServers[0].accessToken
  } catch { return $null }
}

function Get-QQInfo {
  $token = Get-OneBotToken
  if (-not $token) { return $null }
  try {
    $r = Invoke-RestMethod -Uri 'http://127.0.0.1:3000/get_login_info' -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 3
    if ($r.status -eq 'ok' -and $r.retcode -eq 0 -and $r.data) { return $r.data }
  } catch {}
  return $null
}

function Get-Status {
  $dshPort = Get-DshPort
  $qq = Get-QQInfo
  return [ordered]@{
    'DSH（大脑）'       = @{ ok = [bool]$dshPort; detail = $(if ($dshPort) { "端口 $dshPort" } else { '未运行' }) }
    'SnowLuma（QQ 网关）' = @{ ok = (Test-Port 5099); detail = $(if (Test-Port 5099) { '运行中' } else { '未运行' }) }
    'qq-bridge（桥接）'  = @{ ok = (Test-Port 3100); detail = $(if (Test-Port 3100) { '运行中' } else { '未运行' }) }
    'ComfyUI（画图）'    = @{ ok = (Test-Port 8188); detail = $(if (Test-Port 8188) { '运行中' } else { '未运行' }) }
    'QQ 账号'           = @{ ok = [bool]$qq; detail = $(if ($qq) { "$($qq.nickname)（$($qq.user_id)）已在线" } else { '未登录/离线' }) }
  }
}

# 无界面模式（给调试/计划任务用）
if ($NoGui) {
  if ($Action -eq 'start') { & schtasks.exe /Run /TN 'QQBotStart' | Out-Null }
  if ($Action -eq 'stop') { & schtasks.exe /Run /TN 'QQBotStop' | Out-Null }
  Start-Sleep -Seconds 5
  $st = Get-Status
  foreach ($k in $st.Keys) { "{0}: {1} {2}" -f $k, $(if ($st[$k].ok) { '[OK]' } else { '[--]' }), $st[$k].detail }
  exit 0
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = if ($Action -eq 'start') { '小肥鱼喵 · 正在启动' } elseif ($Action -eq 'stop') { '小肥鱼喵 · 正在停止' } else { '小肥鱼喵 · 运行状态' }
$form.Size = New-Object System.Drawing.Size(540, 400)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 26, 32)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = '小肥鱼喵 · QQ 机器人'
$title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 16, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(120, 210, 255)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20, 14)
$form.Controls.Add($title)

$headline = New-Object System.Windows.Forms.Label
$headline.Text = if ($Action -eq 'start') { '正在启动服务，请稍候…' } elseif ($Action -eq 'stop') { '正在停止服务…' } else { '当前运行状态' }
$headline.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11, [System.Drawing.FontStyle]::Bold)
$headline.ForeColor = [System.Drawing.Color]::FromArgb(230, 200, 110)
$headline.AutoSize = $true
$headline.Location = New-Object System.Drawing.Point(22, 56)
$form.Controls.Add($headline)

$statusLabels = @{}
$y = 92
foreach ($name in @('DSH（大脑）', 'SnowLuma（QQ 网关）', 'qq-bridge（桥接）', 'ComfyUI（画图）', 'QQ 账号')) {
  $dot = New-Object System.Windows.Forms.Label
  $dot.Text = '●'
  $dot.ForeColor = [System.Drawing.Color]::Gray
  $dot.AutoSize = $true
  $dot.Location = New-Object System.Drawing.Point(24, $y)
  $form.Controls.Add($dot)

  $nameLbl = New-Object System.Windows.Forms.Label
  $nameLbl.Text = $name
  $nameLbl.AutoSize = $true
  $nameLbl.Location = New-Object System.Drawing.Point(46, $y)
  $form.Controls.Add($nameLbl)

  $detail = New-Object System.Windows.Forms.Label
  $detail.Text = '检测中…'
  $detail.AutoSize = $true
  $detail.ForeColor = [System.Drawing.Color]::FromArgb(160, 170, 185)
  $detail.Location = New-Object System.Drawing.Point(235, $y)
  $form.Controls.Add($detail)

  $statusLabels[$name] = @{ dot = $dot; detail = $detail }
  $y += 34
}

$hint = New-Object System.Windows.Forms.Label
$hint.Text = ''
$hint.AutoSize = $false
$hint.Size = New-Object System.Drawing.Size(495, 44)
$hint.ForeColor = [System.Drawing.Color]::FromArgb(150, 160, 175)
$hint.Location = New-Object System.Drawing.Point(22, $y + 4)
$form.Controls.Add($hint)

function Refresh-Status {
  $st = Get-Status
  foreach ($k in $st.Keys) {
    $item = $st[$k]
    if ($item.ok) {
      $statusLabels[$k].dot.ForeColor = [System.Drawing.Color]::FromArgb(80, 220, 120)
    } else {
      $statusLabels[$k].dot.ForeColor = [System.Drawing.Color]::FromArgb(230, 90, 90)
    }
    $statusLabels[$k].detail.Text = $item.detail
  }
  return $st
}

# 底部按钮
$green = [System.Drawing.Color]::FromArgb(46, 150, 92)
$gray = [System.Drawing.Color]::FromArgb(60, 64, 74)
$blue = [System.Drawing.Color]::FromArgb(46, 100, 170)

function New-Btn([string]$text, [int]$x, [int]$y, [int]$w, $color) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $text
  $b.Location = New-Object System.Drawing.Point($x, $y)
  $b.Size = New-Object System.Drawing.Size($w, 38)
  $b.FlatStyle = 'Flat'
  $b.FlatAppearance.BorderSize = 0
  $b.BackColor = $color
  $b.ForeColor = [System.Drawing.Color]::White
  $b.Cursor = [System.Windows.Forms.Cursors]::Hand
  return $b
}

$btnConsole = New-Btn '打开控制台' 22 ($y + 56) 150 $green
$btnConsole.Add_Click({ Start-Process 'http://127.0.0.1:3100' })
$form.Controls.Add($btnConsole)

$btnPanel = New-Btn '打开管理面板' 186 ($y + 56) 150 $blue
$btnPanel.Add_Click({ Start-Process 'powershell.exe' -ArgumentList '-NoProfile','-STA','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File','D:\qq-bridge\bot-control.ps1' })
$form.Controls.Add($btnPanel)

$btnClose = New-Btn '关闭' 350 ($y + 56) 150 $gray
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

# 触发动作
if ($Action -eq 'start') {
  & schtasks.exe /Run /TN 'QQBotStart' | Out-Null
} elseif ($Action -eq 'stop') {
  & schtasks.exe /Run /TN 'QQBotStop' | Out-Null
}

$script:deadline = (Get-Date).AddSeconds(150)
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({
  $st = Refresh-Status
  $coreOk = $st['DSH（大脑）'].ok -and $st['SnowLuma（QQ 网关）'].ok -and $st['qq-bridge（桥接）'].ok -and $st['QQ 账号'].ok
  $allOff = (-not $st['SnowLuma（QQ 网关）'].ok) -and (-not $st['qq-bridge（桥接）'].ok) -and (-not $st['ComfyUI（画图）'].ok)

  if ($Action -eq 'start') {
    if ($coreOk) {
      $headline.Text = '✅ 启动成功，小肥鱼喵已上线'
      $headline.ForeColor = [System.Drawing.Color]::FromArgb(90, 230, 130)
      $hint.Text = 'QQ 私聊/群聊已生效；关闭本窗口不影响运行。'
      $timer.Stop()
    } elseif ((Get-Date) -gt $script:deadline) {
      $headline.Text = '⚠️ 部分服务未就绪'
      $headline.ForeColor = [System.Drawing.Color]::FromArgb(230, 150, 90)
      $hint.Text = '卡住的服务见上方红点；点「打开控制台」看桥接日志，或重试一次。'
      $timer.Stop()
    }
  } elseif ($Action -eq 'stop') {
    if ($allOff) {
      $headline.Text = '✅ 已停止（DSH 保留运行）'
      $headline.ForeColor = [System.Drawing.Color]::FromArgb(90, 230, 130)
      $hint.Text = 'QQ 网关、桥接、ComfyUI 已关闭；DSH 仍在后台。'
      $timer.Stop()
    } elseif ((Get-Date) -gt $script:deadline) {
      $headline.Text = '⚠️ 停止超时'
      $headline.ForeColor = [System.Drawing.Color]::FromArgb(230, 150, 90)
      $hint.Text = '可能仍有进程未退出，点「打开控制台」检查。'
      $timer.Stop()
    }
  } else {
    if ((Get-Date) -gt $script:deadline) { $timer.Stop() }
  }
})
$timer.Start()
Refresh-Status | Out-Null

[System.Windows.Forms.Application]::Run($form)
