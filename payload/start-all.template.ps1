# qq-bridge 一键启动 / 端口同步：DSH + SnowLuma + ComfyUI + 桥接
# 幂等；由任务计划程序 QQBotStart 调用（独立于 DSH 进程）
$ErrorActionPreference = 'SilentlyContinue'

function Test-Port([int]$p) {
  return [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)
}

function Get-DshProcess {
  return @(Get-Process | Where-Object { $_.ProcessName -like 'DeepSeek Harness*' })
}

function Wait-Port([int]$p, [int]$seconds = 30) {
  for ($i = 0; $i -lt $seconds; $i++) { if (Test-Port $p) { return $true }; Start-Sleep -Seconds 1 }
  return (Test-Port $p)
}

# ---------- 0) DSH（机器人的"大脑"，必须运行；窗口可以最小化到托盘）----------
if (-not (Get-DshProcess)) {
  if (Test-Path '{{DSH_EXE}}') {
    Start-Process -FilePath '{{DSH_EXE}}' -WorkingDirectory '{{DSH_DIR}}'
    Write-Output 'DSH: started'
    Start-Sleep -Seconds 6
  } else {
    Write-Output 'DSH: executable not found'
  }
} else {
  Write-Output 'DSH: already running'
}

# ---------- 1) SnowLuma ----------
if (-not (Test-Port 5099)) {
  Start-Process -FilePath '{{SNOWLUMA_DIR}}\node.exe' -ArgumentList 'index.mjs' -WorkingDirectory '{{SNOWLUMA_DIR}}' `
    -RedirectStandardOutput '{{SNOWLUMA_DIR}}\logs\stdout.log' -RedirectStandardError '{{SNOWLUMA_DIR}}\logs\stderr.log' -WindowStyle Hidden
  Wait-Port 5099 40 | Out-Null
  Write-Output "SnowLuma: started"
} else {
  Write-Output "SnowLuma: already running"
}

# ---------- 2) ComfyUI ----------
if (-not (Test-Port 8188)) {
  $comfyStart = '{{COMFY_DIR}}\start-comfyui.ps1'
  if (Test-Path $comfyStart) {
    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $comfyStart
    Wait-Port 8188 90 | Out-Null
    Write-Output "ComfyUI: starting"
  } else {
    Write-Output "ComfyUI: not installed"
  }
} else {
  Write-Output "ComfyUI: already running"
}

# ---------- 3) 找 DSH Web 端口（扫描 DeepSeek Harness 进程监听的端口）----------
$dshPids = @(Get-DshProcess | Select-Object -ExpandProperty Id)
$candidatePorts = @()
if ($dshPids.Count -gt 0) {
  foreach ($ln in (netstat -ano | Select-String 'LISTENING')) {
    if ($ln.Line -match '^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$') {
      $port = [int]$Matches[1]; $procId = [int]$Matches[2]
      if ($dshPids -contains $procId) { $candidatePorts += $port }
    }
  }
}
$candidatePorts += @(12817, 14326, 3080)
$dshPort = $null
for ($attempt = 0; $attempt -lt 45 -and -not $dshPort; $attempt++) {
  foreach ($p in ($candidatePorts | Sort-Object -Unique)) {
    try {
      $r = Invoke-WebRequest -Uri "http://127.0.0.1:$p/" -UseBasicParsing -TimeoutSec 2
      if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { $dshPort = $p; break }
    } catch {
      if ($_.Exception.Response) { $dshPort = $p; break }
    }
  }
  if (-not $dshPort) { Start-Sleep -Seconds 2 }
}

if (-not $dshPort) {
  Write-Output "DSH: web port not found (bridge not started)"
  exit 1
}
Write-Output "DSH: port $dshPort"

# ---------- 4) 同步桥接配置；DSH 端口变了就重启桥接 ----------
$desiredBase = "http://127.0.0.1:$dshPort"
$currentBase = $null
try { $currentBase = (Get-Content '{{INSTALL_DIR}}\config.json' -Raw -Encoding UTF8 | ConvertFrom-Json).dsh.baseUrl } catch {}

if ($currentBase -ne $desiredBase -and (Test-Port 3100)) {
  $conn = Get-NetTCPConnection -LocalPort 3100 -State Listen -ErrorAction SilentlyContinue
  if ($conn) { Stop-Process -Id $conn.OwningProcess -Force; Start-Sleep -Seconds 2 }
  Write-Output "bridge: stopped (DSH port changed $currentBase -> $desiredBase)"
}

node -e "const fs=require('fs');const p='D:/qq-bridge/config.json';const c=JSON.parse(fs.readFileSync(p,'utf8'));c.dsh.baseUrl='$desiredBase';fs.writeFileSync(p,JSON.stringify(c,null,2))"
Write-Output "bridge config -> $desiredBase"

# ---------- 5) 桥接 ----------
if (-not (Test-Port 3100)) {
  Start-Process -FilePath '{{NODE_EXE}}' -ArgumentList 'src/bridge.js' -WorkingDirectory '{{INSTALL_DIR}}' `
    -RedirectStandardOutput '{{INSTALL_DIR}}\state\stdout.log' -RedirectStandardError '{{INSTALL_DIR}}\state\stderr.log' -WindowStyle Hidden
  Wait-Port 3100 20 | Out-Null
  Write-Output "bridge: started"
} else {
  Write-Output "bridge: already running"
}

