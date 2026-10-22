$ErrorActionPreference = 'SilentlyContinue'
foreach ($port in 3100, 8188, 5099, 3000, 3001) {
  $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($conn) {
    Stop-Process -Id $conn.OwningProcess -Force
    Write-Output "stopped pid $($conn.OwningProcess) (port $port)"
  }
}
Write-Output 'stop done'
