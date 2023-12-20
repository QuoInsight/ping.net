## powershell -command "Get-ExecutionPolicy" #[Restricted|AllSigned|RemoteSigned|Unrestricted|Bypass]# Set-ExecutionPolicy RemoteSigned ##
#Write-Host "Hello, `$Host.version: $($host.version) " # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables?view=powershell-7.4#host

$hst = "info.cern.ch"
$prt = "80"
$cmd= "GET" + [char]0x20 + "/ HTTP/1.0`r`nHost: info.cern.ch`r`n`r`n"
## https://lazyadmin.nl/powershell/concatenate-string/

$ErrorActionPreference = "Stop"
$tcpConnection = New-Object System.Net.Sockets.TcpClient($hst, $prt)
if ($tcpConnection.Connected) {
  Write-Host ">> Connected to ${hst}:${prt}"
}

$tcpStream = $tcpConnection.GetStream()
$reader = New-Object System.IO.StreamReader($tcpStream)
$writer = New-Object System.IO.StreamWriter($tcpStream)
$writer.AutoFlush = $true

Write-Host ">> $cmd"
$writer.WriteLine($cmd) | Out-Null
while ($tcpStream.DataAvailable -or $reader.Peek() -ne -1 ) {
  $reader.ReadLine()
}

# while ($tcpConnection.Connected) {
#   while ($tcpStream.DataAvailable -or $reader.Peek() -ne -1 ) {
#     $reader.ReadLine()
#   }
#   if ($tcpConnection.Connected) {
#     Write-Host -NoNewline "prompt> "
#     $cmd= Read-Host
#     if ($cmd-eq "escape") {
#       break
#     }
#     $writer.WriteLine($cmd) | Out-Null
#     Start-Sleep -Milliseconds 10
#   }
# }

$reader.Close()
$writer.Close()
$tcpConnection.Close()
Write-Host ">> Connection Closed"
