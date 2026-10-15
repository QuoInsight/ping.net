$target = "8.8.8.8"
$timeoutMs = 1000
[int]$summary = 10
[int]$summaryLog = 200

try {
  $route = Find-NetRoute -RemoteIPAddress $target | Select-Object -First 1
  $localIP = ($route | Get-NetIPAddress).IPAddress
} catch {
  # Fallback to first non-loopback IPv4 address if offline
  $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
      $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254*" 
  } | Select-Object -First 1).IPAddress
}

$logFile = "$PSScriptRoot\ping_${target}_${localIP}.$PID.log"
Write-Host "LogFile: $logFile"

$i=0; $fails=0; $totalTime=0; $min=-1; $max=0; $since=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$ping = New-Object System.Net.NetworkInformation.Ping
while ($true) {
  if ($i % $summary -eq 0) {
    Write-Host "Monitoring pings to $target [$summaryMsg]. Press Ctrl+C to stop." -ForegroundColor Cyan
  }
  if (++$i -gt 1) { Start-Sleep -Seconds 1 }

  $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $reply = $ping.Send($target, $timeoutMs)
  $targetAddr = if ($reply.Address) { $reply.Address.ToString() } else { $target }
  if ($reply.Status -eq "Success") {
    $totalTime += $reply.RoundtripTime
    if ($reply.RoundtripTime -gt $max) { $max = $reply.RoundtripTime }
    if ($min -lt 0 -or $reply.RoundtripTime -lt $min) { $min = $reply.RoundtripTime }
    Write-Host "[$timeStamp] Reply from ${targetAddr}: bytes=$($reply.Buffer.Length) time=$($reply.RoundtripTime)ms TTL=$($reply.Options.Ttl)" -ForegroundColor Green
  } else {
    $fails++
    $logMessage = "[$timeStamp] i=$i Ping to $targetAddr failed: " + $reply.Status
    Write-Host $logMessage -ForegroundColor Red
    Add-Content -Path $logFile -Value $logMessage
  }
  $avg = if ($i -eq 0) { 0 } else { [Math]::Round($totalTime/$i) }
  $summaryMsg = "failures=$fails/$i avg=$avg max=$max min=$min since=$since"
  if ($i % $summaryLog -eq 0) {
    $logMessage = "[$timeStamp] $summaryMsg"
    Add-Content -Path $logFile -Value $logMessage
  }
}
