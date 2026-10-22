# 小肥鱼喵 · 一键部署核心脚本（由安装器调用，也可单独运行）
# 说明：DSH 与 SnowLuma 需用户自行安装并同意官方协议，本脚本只检测/配置，不代装。
param(
  [string]$InstallDir = 'D:\qq-bridge',
  [string]$MainQQ = '',
  [string]$BotQQ = '',
  [string]$SnowLumaDir = 'D:\SnowLuma',
  [string]$ComfyDir = 'D:\ComfyUI',
  [switch]$WithComfyUI,
  [switch]$DryRun,
  [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:KitDir = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $script:KitDir 'payload'))) { $script:KitDir = $PSScriptRoot }
$script:Payload = Join-Path $script:KitDir 'payload'
$script:LogFile = if ($LogPath) { $LogPath } else { Join-Path $script:KitDir 'install.log' }
$script:Errors = @()

function Write-Log {
  param([string]$Message, [string]$Level = 'INFO')
  $line = ('[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message)
  $color = switch ($Level) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } default { 'Gray' } }
  Write-Host $line -ForegroundColor $color
  try { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 } catch {}
}

function Fail {
  param([string]$Message)
  Write-Log $Message 'ERROR'
  Write-Host 'DEPLOY_FAIL'
  exit 1
}

function Test-Port {
  param([int]$Port)
  return [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

function Wait-Port {
  param([int]$Port, [int]$Seconds = 60)
  for ($i = 0; $i -lt $Seconds; $i++) { if (Test-Port $Port) { return $true }; Start-Sleep -Seconds 1 }
  return (Test-Port $Port)
}

function Test-Url {
  param([string]$Url)
  try {
    $r = Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec 12 -UseBasicParsing
    return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500)
  } catch {
    if ($_.Exception.Response) { return $true }
    return $false
  }
}

function Download-File {
  param([string]$Url, [string]$OutFile, [string]$Desc = '')
  $name = if ($Desc) { $Desc } else { Split-Path $OutFile -Leaf }
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      Write-Log ("下载 {0}（第 {1} 次）：{2}" -f $name, $attempt, $Url)
      $dir = Split-Path $OutFile -Parent
      if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
      Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec 1800 -UseBasicParsing
      if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt 1000) { return }
      throw '文件过小'
    } catch {
      Write-Log ("下载失败：{0}" -f $_.Exception.Message) 'WARN'
      if ($attempt -eq 3) { throw }
      Start-Sleep -Seconds 2
    }
  }
}

function Get-DshPort {
  param([int]$WaitSeconds = 0)
  $deadline = (Get-Date).AddSeconds($WaitSeconds)
  do {
    $pids = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'DeepSeek Harness*' } | Select-Object -ExpandProperty Id)
    if ($pids.Count -gt 0) {
      foreach ($ln in (netstat -ano | Select-String 'LISTENING')) {
        if ($ln.Line -match '^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$') {
          $port = [int]$Matches[1]; $procId = [int]$Matches[2]
          if ($pids -contains $procId) {
            try {
              $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port/" -UseBasicParsing -TimeoutSec 1
              if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { return $port }
            } catch { if ($_.Exception.Response) { return $port } }
          }
        }
      }
    }
    if ($WaitSeconds -gt 0) { Start-Sleep -Seconds 2 }
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Find-DshExe {
  $candidates = @()
  $candidates += 'D:\dsh\DeepSeek Harness.exe'
  if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\DeepSeek Harness.exe') }
  if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'DeepSeek Harness\DeepSeek Harness.exe') }
  if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'DeepSeek Harness\DeepSeek Harness.exe') }
  foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
  foreach ($hive in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
    try {
      $item = Get-ItemProperty $hive -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*DeepSeek Harness*' } | Select-Object -First 1
      if ($item) {
        $icon = $item.DisplayIcon
        if ($icon) {
          $path = ($icon -split ',')[0].Trim('"')
          if (Test-Path $path) { return $path }
        }
        $loc = $item.InstallLocation
        if ($loc) {
          $exe = Join-Path $loc 'DeepSeek Harness.exe'
          if (Test-Path $exe) { return $exe }
        }
      }
    } catch {}
  }
  return $null
}

function Get-OneBotToken {
  try {
    $file = Get-ChildItem (Join-Path $SnowLumaDir 'config') -Filter 'onebot_*.json' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $file) { return $null }
    $j = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    return $j.networks.httpServers[0].accessToken
  } catch { return $null }
}

function Get-QQOnline {
  $token = Get-OneBotToken
  if (-not $token) { return $null }
  try {
    $r = Invoke-RestMethod -Uri 'http://127.0.0.1:3000/get_login_info' -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 3
    if ($r.status -eq 'ok' -and $r.retcode -eq 0 -and $r.data) { return $r.data }
  } catch {}
  return $null
}

function Write-Report {
  $lines = @()
  $lines += '# 小肥鱼喵 · 部署完成报告'
  $lines += ''
  $lines += ('- 时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
  $lines += ('- 安装目录：`' + $InstallDir + '`')
  $lines += ('- SnowLuma：`' + $SnowLumaDir + '`')
  $lines += ('- ComfyUI：`' + $ComfyDir + '`' + $(if ($WithComfyUI) { '（已安装）' } else { '（未安装，可后续由 AI 指令补装）' }))
  $lines += ('- DSH：`' + (Split-Path $script:DshExe -Parent) + '`')
  $lines += ('- 主号 QQ：' + $MainQQ)
  $lines += ('- 机器人小号：' + $BotQQ)
  $lines += ('- DSH 端口：' + $script:DshPort)
  $lines += ''
  $lines += '## 常用入口'
  $lines += ('- 桌面：小肥鱼喵（控制台 App）')
  $lines += '- 桥接控制台：http://127.0.0.1:3100'
  $lines += '- SnowLuma 面板：http://127.0.0.1:5099'
  $lines += '- ComfyUI：http://127.0.0.1:8188'
  $lines += ''
  $lines += '## 下一步'
  $lines += '1. 打开 DSH，在设置里粘贴 DeepSeek API Key（安装器已把它复制到剪贴板）。'
  $lines += '2. 打开「小肥鱼喵」App，确认状态为「已上线」。'
  $lines += '3. 用自己的 QQ 给机器人小号发消息测试；群聊需要先把它拉进群。'
  $lines += '4. 把 `docs\给AI的安装指令.md` 的内容发给你的 DSH Agent，让它做最后验收和排错。'
  $lines += ''
  $lines += '## 已知限制'
  $lines += '- DSH 与 SnowLuma 为第三方软件，需用户自行安装并同意其协议；本安装器不代为打包/部署。'
  $lines += '- 第三方协议端登录存在 QQ 风控/封号风险，请使用小号。'
  $content = $lines -join "`r`n"
  Set-Content -Path (Join-Path $InstallDir '部署完成报告.md') -Value $content -Encoding UTF8
}

# ---------------- 主流程 ----------------
Write-Log '================ 小肥鱼喵 一键部署 ================'
if ($InstallDir -notmatch '^[A-Za-z]:\\') { Fail '安装目录必须是绝对路径（如 D:\qq-bridge）' }
if ($MainQQ -and $MainQQ -notmatch '^\d{5,12}$') { Fail '主号 QQ 格式不正确' }
if (-not (Test-Path $script:Payload)) { Fail ('安装包不完整：缺少 payload 目录（' + $script:Payload + '）') }

$drive = ($InstallDir -split ':')[0] + ':\'
$freeGB = 0
try { $freeGB = [math]::Round((Get-PSDrive -Name ($drive.TrimEnd('\').TrimEnd(':')) -ErrorAction Stop).Free / 1GB, 1) } catch {}
Write-Log ("目标磁盘可用空间：" + $freeGB + " GB")
if ($DryRun) {
  Write-Log '[DryRun] 只检查不安装'
} else {
  if ($freeGB -lt 5) { Fail '目标磁盘空间不足（至少 5GB）' }
  if ($WithComfyUI -and $freeGB -lt 16) { Fail '勾选了 ComfyUI，至少需要 16GB 空间' }
}

Write-Log '检查网络（npmmirror / GitHub 镜像 / hf-mirror）...'
$checks = [ordered]@{
  'npmmirror' = 'https://registry.npmmirror.com/'
  'ghproxy' = 'https://ghproxy.net/'
  'hf-mirror' = 'https://hf-mirror.com/'
}
foreach ($k in $checks.Keys) {
  if (Test-Url $checks[$k]) { Write-Log ("网络 " + $k + " 可达") 'OK' } else { Write-Log ("网络 " + $k + " 不可达（可能影响下载）") 'WARN' }
}

# 1) Node
$nodeExe = $null
$cmdNode = Get-Command node -ErrorAction SilentlyContinue
if ($cmdNode) {
  try {
    $ver = (& $cmdNode.Source --version).TrimStart('v')
    $major = [int]($ver -split '\.')[0]
    $minor = [int]($ver -split '\.')[1]
    if ($major -gt 22 -or ($major -eq 22 -and $minor -ge 13)) { $nodeExe = $cmdNode.Source; Write-Log ("使用已安装 Node：" + $ver) 'OK' }
    else { Write-Log ("Node " + $ver + " 过旧（需要 >=22.13），将安装便携版") 'WARN' }
  } catch {}
}
if (-not $nodeExe) {
  $nodeDir = Join-Path $InstallDir 'runtime\node'
  $nodeExeCand = Join-Path $nodeDir 'node.exe'
  if (Test-Path $nodeExeCand) { $nodeExe = $nodeExeCand; Write-Log '使用安装包内置 Node' 'OK' }
  elseif ($DryRun) { Write-Log '[DryRun] 将下载 Node 便携版（约 36MB）' }
  else {
    $zip = Join-Path $env:TEMP 'node-win-x64.zip'
    Download-File 'https://npmmirror.com/mirrors/node/v22.22.2/node-v22.22.2-win-x64.zip' $zip 'Node.js 便携版'
    $tmp = Join-Path $env:TEMP 'node-extract'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Path $nodeDir -Force | Out-Null
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    Copy-Item (Join-Path $inner.FullName '*') $nodeDir -Recurse -Force
    Remove-Item $tmp -Recurse -Force
    $nodeExe = $nodeExeCand
    Write-Log 'Node 便携版安装完成' 'OK'
  }
}
if ($nodeExe) { $env:PATH = (Split-Path $nodeExe -Parent) + ';' + $env:PATH }

# 2) 桥接
$bridgeMarker = Join-Path $InstallDir 'src\bridge.js'
if (Test-Path $bridgeMarker) {
  Write-Log '检测到已有桥接目录，保留现有代码与数据' 'WARN'
} elseif ($DryRun) {
  Write-Log ('[DryRun] 将安装桥接与 App 到 ' + $InstallDir)
} else {
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  Copy-Item (Join-Path $script:Payload 'qq-bridge\*') $InstallDir -Recurse -Force
  Write-Log '桥接源码已复制（MIT License）' 'OK'
}
if (-not $DryRun) {
  # 覆盖关键补丁（媒体 MCP / 预设 / 守卫）
  Copy-Item (Join-Path $script:Payload 'patches\mcp-media.js') (Join-Path $InstallDir 'src\mcp-media.js') -Force
  Copy-Item (Join-Path $script:Payload 'patches\qq-tool-restrict.mjs') (Join-Path $InstallDir 'plugins\qq-agent-presets\qq-tool-restrict.mjs') -Force
  Copy-Item (Join-Path $script:Payload 'patches\qq-chat-v2.patch.yml') (Join-Path $InstallDir 'plugins\qq-agent-presets\presets\qq-chat-v2.patch.yml') -Force
  Copy-Item (Join-Path $script:Payload 'patches\qq-chat.patch.yml') (Join-Path $InstallDir 'plugins\qq-agent-presets\presets\qq-chat.patch.yml') -Force
  Copy-Item (Join-Path $script:Payload 'patches\qq-chat.agent.cordis.yml') (Join-Path $InstallDir 'dsh\agent-presets\qq-chat\agent.cordis.yml') -Force
  Copy-Item (Join-Path $script:Payload 'patches\qq-chat-v2.agent.cordis.yml') (Join-Path $InstallDir 'dsh\agent-presets\qq-chat-v2\agent.cordis.yml') -Force
  Copy-Item (Join-Path $script:Payload 'app\*') (Join-Path $InstallDir 'app') -Recurse -Force
  New-Item -ItemType Directory -Path (Join-Path $InstallDir 'state') -Force | Out-Null
  Write-Log '媒体/预设补丁与 App 已应用' 'OK'
}

# 3) npm 依赖
if (-not $DryRun) {
  $npmCli = Join-Path (Split-Path $nodeExe -Parent) 'node_modules\npm\bin\npm-cli.js'
  Push-Location $InstallDir
  try {
    if (Test-Path $npmCli) { & $nodeExe $npmCli install --no-audit --no-fund --registry https://registry.npmmirror.com }
    else { & npm install --no-audit --no-fund --registry https://registry.npmmirror.com }
    if ($LASTEXITCODE -ne 0) { throw ('npm install 失败，退出码 ' + $LASTEXITCODE) }
    Write-Log '桥接依赖安装完成' 'OK'
  } finally { Pop-Location }
}

# 4) ffmpeg（撒娇后期需要）
$ffmpeg = $null; $ffprobe = $null
$cmdFfmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($cmdFfmpeg) {
  $ffmpeg = $cmdFfmpeg.Source
  $cand = Join-Path (Split-Path $ffmpeg -Parent) 'ffprobe.exe'
  if (Test-Path $cand) { $ffprobe = $cand }
  Write-Log '检测到系统 ffmpeg' 'OK'
}
if (-not $ffmpeg -and -not $DryRun) {
  try {
    $zip = Join-Path $env:TEMP 'ffmpeg-essentials.zip'
    Download-File 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' $zip 'ffmpeg'
    $dst = Join-Path $InstallDir 'tools\ffmpeg'
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $dst -Force
    $exe = Get-ChildItem $dst -Recurse -Filter 'ffmpeg.exe' | Select-Object -First 1
    $pex = Get-ChildItem $dst -Recurse -Filter 'ffprobe.exe' | Select-Object -First 1
    if ($exe) { $ffmpeg = $exe.FullName; if ($pex) { $ffprobe = $pex.FullName }; Write-Log 'ffmpeg 安装完成' 'OK' }
  } catch {
    Write-Log ('ffmpeg 安装失败（撒娇后期将自动降级关闭）：' + $_.Exception.Message) 'WARN'
  }
}

# 5) DSH
$dshExe = Find-DshExe
if (-not $dshExe) { Fail '未检测到 DSH（DeepSeek Harness）。请先从官方安装 DSH 桌面版，登录/配置 API Key 后再运行本安装器。' }
$script:DshExe = $dshExe
$dshDir = Split-Path $dshExe -Parent
Write-Log ('检测到 DSH：' + $dshExe) 'OK'
$dshProcs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'DeepSeek Harness*' })
if ($dshProcs.Count -eq 0 -and -not $DryRun) {
  Write-Log '启动 DSH…'
  Start-Process -FilePath $dshExe -WorkingDirectory $dshDir
  Start-Sleep -Seconds 5
}
$dshPort = Get-DshPort 180
if (-not $dshPort -and -not $DryRun) { Fail 'DSH 已安装但 Web 服务未就绪：请手动打开 DSH 完成登录/初始化，再重试。' }
if ($DryRun -and -not $dshPort) { Write-Log '[DryRun] DSH 未运行（将尝试启动）' }
$script:DshPort = $dshPort

# 6) SnowLuma
if (-not (Test-Port 5099)) {
  Write-Log '未检测到 SnowLuma（5099）。请手动双击 SnowLuma 的 launcher.bat 并扫码登录，正在等待（最多 5 分钟）…' 'WARN'
  if (-not $DryRun) {
    if (-not (Wait-Port 5099 300)) { Fail 'SnowLuma 未启动。请在浏览器打开 http://127.0.0.1:5099 完成扫码登录后重试安装。' }
  }
}
if (Test-Port 5099) { Write-Log 'SnowLuma 运行中' 'OK' }

# 7) 生成配置
if (-not $DryRun) {
  $installF = $InstallDir -replace '\\', '/'
  $slF = $SnowLumaDir -replace '\\', '/'
  $comfyF = $ComfyDir -replace '\\', '/'
  $ffp = if ($ffmpeg) { $ffmpeg -replace '\\', '/' } else { '' }
  $ffpr = if ($ffprobe) { $ffprobe -replace '\\', '/' } else { '' }
  $tpl = Get-Content (Join-Path $script:Payload 'config.template.json') -Raw -Encoding UTF8
  $tpl = $tpl.Replace('{{DSH_PORT}}', [string]$dshPort)
  $tpl = $tpl.Replace('{{MAIN_QQ}}', $MainQQ)
  $tpl = $tpl.Replace('{{SNOWLUMA_DIR}}', $slF)
  $tpl = $tpl.Replace('{{INSTALL_DIR}}', $installF)
  $tpl = $tpl.Replace('{{COMFY_DIR}}', $comfyF)
  $tpl = $tpl.Replace('{{FFMPEG_PATH}}', $ffp)
  $tpl = $tpl.Replace('{{FFPROBE_PATH}}', $ffpr)
  $cfgPath = Join-Path $InstallDir 'config.json'
  if (Test-Path $cfgPath) { Copy-Item $cfgPath ($cfgPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force }
  Set-Content -Path $cfgPath -Value $tpl -Encoding UTF8
  Write-Log '桥接配置 config.json 已生成' 'OK'

  # 8) DSH profile 安装预设 + MCP
  $profileRoot = Join-Path $env:USERPROFILE '.dsh\profiles'
  if (-not (Test-Path $profileRoot)) { Fail '未找到 DSH profile（' + $profileRoot + '），请先启动一次 DSH 完成初始化。' }
  $profiles = Get-ChildItem $profileRoot -Directory
  $profileName = if ($profiles | Where-Object { $_.Name -eq 'desktop' }) { 'desktop' } elseif ($profiles) { $profiles[0].Name } else { Fail 'DSH profile 为空，请先启动 DSH。' }
  Push-Location $InstallDir
  try {
    & $nodeExe 'scripts\setup-dsh.mjs' $profileName
    Write-Log ('DSH 预设与 MCP 已安装（profile: ' + $profileName + '）') 'OK'
  } catch { Write-Log ('setup-dsh 失败（可稍后让 AI 修复）：' + $_.Exception.Message) 'WARN' } finally { Pop-Location }

  # 9) 媒体 MCP 条目
  $patchFile = Join-Path $profileRoot (Join-Path $profileName 'cordis.patch.yml')
  if (Test-Path $patchFile) {
    $patchText = Get-Content $patchFile -Raw -Encoding UTF8
    if ($patchText -notmatch 'mcp-media') {
      $nodeF = $nodeExe -replace '\\', '\\'
      $mediaPath = (Join-Path $InstallDir 'src\mcp-media.js') -replace '\\', '\\'
      $block = @"

- insert:
    - id: mcp-media
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: media
        transport: stdio
        command: '$nodeF'
        args:
          - '$mediaPath'
        toolCallTimeoutMs: 300600
"@
      Add-Content -Path $patchFile -Value $block -Encoding UTF8
      Write-Log '媒体工具（画图/语音/发图）已挂载到 DSH' 'OK'
    } else { Write-Log '媒体工具已存在，跳过' }
  } else {
    Write-Log '未找到 cordis.patch.yml（DSH 可能未初始化），稍后按 AI 指令修复' 'WARN'
  }

  # 10) 启动脚本 + 计划任务 + 快捷方式
  $startTpl = Get-Content (Join-Path $script:Payload 'start-all.template.ps1') -Raw -Encoding UTF8
  $startTpl = $startTpl.Replace('{{SNOWLUMA_DIR}}', $SnowLumaDir).Replace('{{INSTALL_DIR}}', $InstallDir).Replace('{{DSH_EXE}}', $dshExe).Replace('{{DSH_DIR}}', $dshDir).Replace('{{NODE_EXE}}', $nodeExe).Replace('{{COMFY_DIR}}', $ComfyDir)
  Set-Content -Path (Join-Path $InstallDir 'start-all.ps1') -Value $startTpl -Encoding UTF8
  Copy-Item (Join-Path $script:Payload 'stop-all.template.ps1') (Join-Path $InstallDir 'stop-all.ps1') -Force
  $comfyTpl = Get-Content (Join-Path $script:Payload 'start-comfyui.template.ps1') -Raw -Encoding UTF8
  $comfyTpl = $comfyTpl.Replace('{{COMFY_DIR}}', $ComfyDir)
  if ($WithComfyUI) { Set-Content -Path (Join-Path $ComfyDir 'start-comfyui.ps1') -Value $comfyTpl -Encoding UTF8 }

  $startPs = Join-Path $InstallDir 'start-all.ps1'
  $stopPs = Join-Path $InstallDir 'stop-all.ps1'
  # 隐藏启动器：wscript 是 GUI 子系统，任务计划触发时不会闪控制台窗口
  $hiddenVbs = Join-Path $InstallDir 'run-hidden.vbs'
  Copy-Item (Join-Path $script:Payload 'run-hidden.vbs') $hiddenVbs -Force
  $startTr = ('wscript.exe "' + $hiddenVbs + '" "' + $startPs + '"')
  $stopTr = ('wscript.exe "' + $hiddenVbs + '" "' + $stopPs + '"')
  & schtasks.exe /Create /TN 'QQBotStart' /TR $startTr /SC ONCE /ST 00:00 /F | Out-Null
  & schtasks.exe /Create /TN 'QQBotStop' /TR $stopTr /SC ONCE /ST 00:00 /F | Out-Null
  & schtasks.exe /Create /TN 'qq-bridge-autosync' /TR $startTr /SC MINUTE /MO 5 /F | Out-Null
  Write-Log '计划任务 QQBotStart / QQBotStop / 自动同步（静默）已创建' 'OK'

  $ws = New-Object -ComObject WScript.Shell
  $appExe = Join-Path $InstallDir 'app\小肥鱼喵.exe'
  $desktop = [Environment]::GetFolderPath('Desktop')
  $lnk = $ws.CreateShortcut((Join-Path $desktop '小肥鱼喵.lnk'))
  $lnk.TargetPath = $appExe; $lnk.WorkingDirectory = (Join-Path $InstallDir 'app'); $lnk.IconLocation = "$appExe,0"; $lnk.Description = '小肥鱼喵 · QQ 智能体控制台'; $lnk.Save()
  $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\qq-bridge.lnk'
  $lnk2 = $ws.CreateShortcut($startup)
  $lnk2.TargetPath = 'C:\Windows\System32\wscript.exe'; $lnk2.Arguments = '"' + $hiddenVbs + '" "' + $startPs + '"'; $lnk2.WorkingDirectory = $InstallDir; $lnk2.Description = '开机自动启动小肥鱼喵（静默）'; $lnk2.Save()
  Write-Log '桌面与开机自启快捷方式已创建' 'OK'

  # 11) 可选 ComfyUI
  if ($WithComfyUI) {
    try {
      $comfyRoot = Join-Path $ComfyDir 'ComfyUI_windows_portable'
      if (-not (Test-Path $comfyRoot)) {
        $comfyZip = Join-Path $env:TEMP 'ComfyUI_portable.7z'
        Download-File 'https://ghproxy.net/https://github.com/Comfy-Org/ComfyUI/releases/download/v0.42.1/ComfyUI_windows_portable_nvidia.7z' $comfyZip 'ComfyUI 便携包（约 1.9GB）'
        New-Item -ItemType Directory -Path $ComfyDir -Force | Out-Null
        $sevenZip = Join-Path $script:Payload 'tools\7zr.exe'
        & $sevenZip x $comfyZip ('-o' + $ComfyDir) -y | Out-Null
      }
      $ckptDir = Join-Path $comfyRoot 'ComfyUI\models\checkpoints'
      New-Item -ItemType Directory -Path $ckptDir -Force | Out-Null
      $ckpt = Join-Path $ckptDir 'Counterfeit-V2.5_fp16.safetensors'
      if (-not (Test-Path $ckpt)) {
        Download-File 'https://hf-mirror.com/gsdf/Counterfeit-V2.5/resolve/main/Counterfeit-V2.5_fp16.safetensors' $ckpt '画图模型（约 2GB）'
      }
      & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ComfyDir 'start-comfyui.ps1') | Out-Null
      if (Wait-Port 8188 180) { Write-Log 'ComfyUI 已启动' 'OK' } else { Write-Log 'ComfyUI 启动超时（可稍后用 App 启动）' 'WARN' }
    } catch {
      Write-Log ('ComfyUI 安装失败（聊天仍可用，可稍后让 AI 补装）：' + $_.Exception.Message) 'WARN'
    }
  }

  # 12) 启动 & 等待上线
  & schtasks.exe /Run /TN 'QQBotStart' | Out-Null
  $deadline = (Get-Date).AddSeconds(240)
  $online = $false
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 4
    if ((Test-Port 5099) -and (Test-Port 3100) -and (Test-Port 3000) -and (Get-QQOnline)) { $online = $true; break }
    if (-not (Test-Port 5099)) { & schtasks.exe /Run /TN 'QQBotStart' | Out-Null }
  }
  if ($online) { Write-Log '小肥鱼喵已上线！' 'OK' } else { Write-Log '服务尚未完全就绪，请打开 App 查看状态或按 AI 指令排查' 'WARN' }

  $docsDst = Join-Path $InstallDir 'docs'
  New-Item -ItemType Directory -Path $docsDst -Force | Out-Null
  Copy-Item (Join-Path $script:Payload 'docs\*') $docsDst -Recurse -Force -ErrorAction SilentlyContinue
  $aiDoc = Join-Path $docsDst '给AI的安装指令.md'
  if (Test-Path $aiDoc) {
    $ai = Get-Content $aiDoc -Raw -Encoding UTF8
    $ai = $ai.Replace('{{INSTALL_DIR}}', $InstallDir).Replace('{{SNOWLUMA_DIR}}', $SnowLumaDir).Replace('{{MAIN_QQ}}', $MainQQ).Replace('{{DSH_PORT}}', [string]$dshPort)
    Set-Content -Path $aiDoc -Value $ai -Encoding UTF8
  }
  Write-Report
  Write-Log ('部署报告：' + (Join-Path $InstallDir '部署完成报告.md')) 'OK'
}

Write-Log '================ 部署结束 ================'
Write-Host 'DEPLOY_OK'
exit 0
