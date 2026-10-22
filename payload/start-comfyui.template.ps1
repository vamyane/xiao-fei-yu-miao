# ComfyUI 启动（独立进程）
$ErrorActionPreference = 'SilentlyContinue'
$root = '{{COMFY_DIR}}\ComfyUI_windows_portable'
$logDir = Join-Path $root 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
function Test-Port([int]$p) { return [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) }
if (-not (Test-Port 8188)) {
  Start-Process -FilePath (Join-Path $root 'python_embeded\python.exe') `
    -ArgumentList '-s','ComfyUI\main.py','--windows-standalone-build','--listen','127.0.0.1','--port','8188' `
    -WorkingDirectory $root `
    -RedirectStandardOutput (Join-Path $logDir 'comfyui.out.log') `
    -RedirectStandardError (Join-Path $logDir 'comfyui.err.log') `
    -WindowStyle Hidden
  Write-Output 'ComfyUI: starting'
} else { Write-Output 'ComfyUI: already running' }
