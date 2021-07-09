import sys, subprocess
def exeCmdln(cmd, args, stdin) :
  cmdlineArr=[cmd];  cmdlineArr.extend(args)
  p = subprocess.Popen(
    cmdlineArr, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
  )
  return "\n".join(outData.decode() for outData in p.communicate(input=stdin.encode('ascii')))
#

def getConnectedSsidNetsh(macAddr) :
  ssid = ""
  cmdOutput = ""
  try :
    macAddr = macAddr.replace(":","").replace("-","").upper()
    cmdOutput = exeCmdln("netsh.exe", ["wlan", "show", "interfaces"], "")
    foundMacAddr = False
    for line in cmdOutput.split("\n") :
      if (foundMacAddr) :
        line = line.strip()
        idx = (line.index(":")+1) if (":" in line) else 0
        if "BSSID" in line :
          ssid += " BSSID:" + line[idx:].strip().replace(":","")
        elif "SSID" in line :
          ssid += " " + line[idx:].strip()
        elif "Signal" in line :
          ssid += " [" + line[idx:].strip() + "]"
          break
        #
      else :
        foundMacAddr = ( macAddr in line.upper().replace(":","").replace("-","") )
      #
    #
  except :
    pass
  #
  return ssid
#

#print( getConnectedSsidNetsh("") ); quit()

def getIfName(nicGUID):
  ifName = nicGUID
  if (sys.platform=="win32"):
    import winreg 
    try:
      regKey = winreg.OpenKey(
        winreg.ConnectRegistry(None, winreg.HKEY_LOCAL_MACHINE),
        "SYSTEM\\CurrentControlSet\\Control\\Network\\{4d36e972-e325-11ce-bfc1-08002be10318}\\" + nicGUID + "\\Connection"
      )
      ifName = winreg.QueryValueEx(regKey, 'Name')[0]
      ifName = "[" + ifName + "]"
      #ifType = winreg.QueryValueEx(regKey, 'MediaSubType')[0] ## !! MediaSubType==2 for both lan & wlan !!
      # netsh.exe wlan show interfaces
      # netsh.exe interface show interface
      # netsh.exe interface ip show interfaces
      # wmic.exe nic list full
    except :
      pass
    #
  #
  return ifName
#

import urllib.request
def getPublicIP() :
  pubAddr = ""
  try :
    pubAddr = urllib.request.urlopen(
      "http://checkip.amazonaws.com/"
    ).read().decode("utf8").strip()
  except :
    pass
  #
  return pubAddr
#

import socket
import netifaces ## pip install netifaces
def getNicInfo() :
  hostName = socket.gethostname()
  defaultGW = netifaces.gateways().get("default")
  (gwAddr,gwIf) = defaultGW[netifaces.AF_INET]
  addrs = netifaces.ifaddresses(gwIf) ## {793B7B92-2A7D-4399-B444-450C0846479F}
  macAddr = addrs[netifaces.AF_LINK][0]['addr']
  ipAddr = addrs[netifaces.AF_INET][0]['addr']
  sckAddr = socket.gethostbyname(hostName)
  if (ipAddr!=sckAddr) : ipAddr += "/" + sckAddr
  return (
    hostName + " " + getIfName(gwIf) + " MAC:" + macAddr.replace(":","").upper()
     + getConnectedSsidNetsh(macAddr) + "\n IP:" + ipAddr + " GW:" + gwAddr
     + " PUB:" + getPublicIP()
  )
  ## XXXXXXXXX [Wi-Fi] MAC:XXXXXXXXXXXX XXXXXXXXX BSSID:XXXXXXXXXXXX [66%]
  ##  IP:192.168.0.106/XXX.XXX.XXX.XXX GW:192.168.0.2
#

print( getNicInfo() ); quit()
