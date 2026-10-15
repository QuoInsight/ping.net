$hst = "info.cern.ch"
$prt = 80
$cmd= "GET" + [char]0x20 + "/ HTTP/1.0`r`nHost: info.cern.ch`r`n`r`n"
$timeoutMs = 10000
[int]$sleep = 3
[int]$summary = 10
[int]$summaryLog = 200

try {
  $socket = New-Object System.Net.Sockets.UdpClient
  $socket.Connect($hst, $prt)
  $localIP = $socket.Client.LocalEndPoint.Address.IPAddressToString
  $socket.Close()
} catch {
  # Fallback to first non-loopback IPv4 address if offline
  $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
      $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254*" 
  } | Select-Object -First 1).IPAddress
}

$logFile = "$PSScriptRoot\tcpSocket_failures_$localIP.$PID.log"
Write-Host "LogFile: $logFile"

$i=0; $fails=0; $totalTime=0; $min=-1; $max=0; $since=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
while ($true) {
  if ($i % $summary -eq 0) {
    Write-Host "Monitoring netIPC connection to ${hst}:${prt} [$summaryMsg] Press Ctrl+C to stop." -ForegroundColor Cyan
  }
  if (++$i -gt 1) { Start-Sleep -Seconds $sleep }

  $timeStamp1 = Get-Date
  $timeStamp = $timeStamp1.ToString('yyyy-MM-dd HH:mm:ss')
  $logMessage = ""
  try {
    $ErrorActionPreference = "Stop"
    #$tcpConnection = New-Object System.Net.Sockets.TcpClient($hst, $prt) ## typical timeout 21-45s
      $tcpConnection = New-Object System.Net.Sockets.TcpClient
      $asyncResult = $tcpConnection.BeginConnect($hst, $prt, $null, $null)
      $waitHandle = $asyncResult.AsyncWaitHandle
      if (-not $waitHandle.WaitOne($timeoutMs, $false)) {
        $tcpConnection.Close()
        throw "Connection timed out after ${timeoutMs}ms when connecting to ${hst}:${prt}"
      }
      $tcpConnection.EndConnect($asyncResult)
    if ($tcpConnection.Connected) {
      #Write-Host ">> Connected to ${hst}:${prt}"
      $tcpStream = $tcpConnection.GetStream()
        $tcpStream.ReadTimeout = $timeoutMs ## Default: Infinite
        $tcpStream.WriteTimeout = $timeoutMs ## Default: Infinite
      $reader = New-Object System.IO.StreamReader($tcpStream)
      $writer = New-Object System.IO.StreamWriter($tcpStream)
      $writer.AutoFlush = $true
      #Write-Host ">> $cmd"
      $writer.WriteLine($cmd) | Out-Null
      ##while ($tcpStream.DataAvailable -or $reader.Peek() -ne -1 ) { $reader.ReadLine() }
      #while ($null -ne ($line = $reader.ReadLine())) { Write-Host $line }
      $lines = while ($null -ne ($line = $reader.ReadLine())) { $line }
      Write-Host $lines[0] ## show first line only
    }
  } catch {
    # Handles connection failures, timeouts, and network errors
    $fails++
    $logMessage = "[$timeStamp] i=$i Error encountered: $_"
    Write-Host $logMessage -ForegroundColor Red
    Add-Content -Path $logFile -Value $logMessage
  } finally {
    # Ensures cleanup happens even if an error occurs
    if ($null -ne $waitHandle -and $null -ne $waitHandle.SafeWaitHandle -and -not $waitHandle.SafeWaitHandle.IsClosed) {
      $waitHandle.Close()
    }
    if ($null -ne $reader) { $reader.Close() }
    if ($null -ne $writer) { $writer.Close() }
    if ($null -ne $tcpConnection) {
      $tcpConnection.Close() 
      #Write-Host ">> Connection Closed" -ForegroundColor Yellow
    }
  }
  $timeStamp2 = Get-Date
  $duration = [Math]::Round(($timeStamp2-$timeStamp1).TotalSeconds*1000)
  $totalTime += $duration
  if ($duration -gt $max) { $max = $duration }
  if ($min -lt 0 -or $duration -lt $min) { $min = $duration }
  Write-Host "[$timeStamp] i=$i time=${duration}ms"
  if ($duration -gt $timeoutMs) {
    if ($logMessage -eq "") { $fails++ } ## avoid double count
    $timeStamp = $timeStamp2.ToString('yyyy-MM-dd HH:mm:ss') ## Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timeStamp] Last attempt i=$i totalTime=${duration}ms exceeded ${timeoutMs}ms"
    Write-Host $logMessage -ForegroundColor Red
    Add-Content -Path $logFile -Value $logMessage
  }
  $avg = if ($i -eq 0) { 0 } else { [Math]::Round($totalTime/$i) }
  $summaryMsg = "failures=$fails/$i avg=$avg max=$max min=$min since=$since"
  if ($i % $summaryLog -eq 0) {
    Add-Content -Path $logFile -Value "[$timeStamp] $summaryMsg"
  }
}
