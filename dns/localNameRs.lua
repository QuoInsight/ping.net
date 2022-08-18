#!/usr/bin/env lua

if #arg < 1 then
  print("\nUsage: "..arg[0].." <HOST> [CLIENT_IP]\n")
  os.exit()
end

local function printD(txt)
  --print(txt)
end

local function _exeCmd(cmdln)
  local file = assert(io.popen(cmdln, 'r'))
  local output = file:read('*all')
  file:close()
  output = string.gsub(output, "^%s*(.-)%s*$", "%1") --trim
  return output
end

local function qryDNSTypA(name, srv, prt)
  local cmdln = '"'..arg[-1]..'" "/root/qryDnsTypA.lua" '
    ..name..' '..srv..' '..prt
  if (package.config:sub(1,1)=="\\") then
    cmdln = '"'..cmdln..'"'
  end
  return _exeCmd(cmdln)
end

local function getLuaSocketDnsIpAddr(name)
  local socket = require("socket")
  local addr,details = socket.dns.toip(name)
  if addr==nil then
    printD("Error: "..details)
    return "0.0.0.0"
  else
    printD(details) -- printD(dumptable(addrDetails))
    --local addrDetails = socket.dns.getaddrinfo(name)
    --printD(addrDetails)
    return addr
  end
end

local function ipAddr2MAC(ipAddr)
  --[[
    arp | grep -Fi 'A4:12:32:B8:26:B5' | sed 's/\([^ ]\+\).\+/\1/'
    arp | grep -F '192.168.43.222' | awk '{ print $4 }'
  --]]
  if (ipAddr~=nil) then
    local isWindows = (package.config:sub(1,1)=="\\")
    local cmdln = 'cat /proc/net/arp | grep -F "'..ipAddr..' "'
    -- type arp ==> arp is a shell function (/etc/profile)
    if isWindows then cmdln = 'arp -a | findstr "'..ipAddr..' "' end
    for line in _exeCmd(cmdln):gmatch("([^\n]+)") do
      --print(line)
      colCount = 0
      for col in line:gmatch("([^ ]+)%s+") do
        colCount = colCount + 1
        if (isWindows and colCount==2 and not(col:find("%."))) then
          return col
        elseif (colCount==4) then
          return col
        end
      end
    end
  end
  --return "00:00:00:00:00:00"
  return ""
end

local etcHostsFile = "/etc/hosts"
if (package.config:sub(1,1)=="\\") then
  etcHostsFile = os.getenv("SystemRoot").."\\system32\\drivers\\etc\\hosts" 
end

local function loadHostsFile(filePath)
  local cronchk = os.execute("/root/bzbx.lua cronchk "..filePath..".cronchk > /dev/null") / 256
  -- https://stackoverflow.com/a/23827063
  printD("cronchk: "..cronchk)
  if (cronchk==0) then
    --time matches for skipPrCtrl/unblock/allow, hence we will ignore this hosts file
    return nil
  end
  local f1=io.open(filePath,"r")
  if f1==nil then
    return nil
  else
    local hosts = {}
    repeat
      local line = f1:read()
      if line==nil then break end
      if line:match('[^ -~\n\t]') then break end -- non-printable ascii characters
      line = line:gsub("^%s*(.-)%s*$", "%1"):lower() -- trim
      if string.len(line) > 0 and line:sub(1,1)~="#" then
        --local ip, hostname = line:match("^([^%s]+)%s+([^%s]+).*")
        -- [supported format] 127.0.0.1 localhost
        local ip = nil
        for hostEntry,_ in string.gmatch(line..' ', "([^%s]+)%s+") do
          -- [supported format] 127.0.0.1 localhost local x y z
          if (ip==nil) then
            ip = hostEntry
			if (not string.find(ip, "%.")) then
			  --skip non-ipAddrV4
			  break
			end
          else
            hosts[hostEntry] = ip
            hosts[ip] = hostEntry
            printD(hostEntry.." ["..ip.."]")
          end
        end
      end
    until (line==nil)
    io.close(f1)
    return hosts
  end
end

local function lookupNameRs(hostName, hosts)
  local ipAddrV4 = nil
  if (hosts~=nil) then
    ipAddrV4 = hosts[hostName]
    if (ipAddrV4==nil or (not string.find(ipAddrV4, "%."))) then
      local p = 1
	  while true do
        local p2,_ = string.find(hostName, "%.", p)
        if (p2==nil) then
          break
		else
		  p = p2+1
		  printD(" ==> ["..hostName:sub(p).."]")
		  ipAddrV4 = hosts[hostName:sub(p)]
		  if (ipAddrV4~=nil and string.find(ipAddrV4, "%.")) then
		    break
		  end
		end
	  end
	end
  end
  return ipAddrV4
end

local function getLocalNameRs(hostName, clientIpAddr)
  --[[
    getCustomNameResolution | customNameService | resolvedIpAddr | localResIpAddr
    /etc/nsswitch.conf | /etc/hosts | hosts.aabbcceeff | NameServiceSwitch
    files mdns4_minimal [NOTFOUND=return] dns
    - host/nslookup commands will query DNS directly and
      ignore the settings in nsswitch.conf and hosts files
  --]]
  local macAddr = string.gsub(ipAddr2MAC(clientIpAddr),"[:-]",""):lower()
  local customHostsFile = "/tmp/hosts/hosts."..macAddr
  printD("customHostsFile: "..customHostsFile)
  local hosts = loadHostsFile(customHostsFile)
  if (hosts==nil) then
    printD("etcHostsFile: "..etcHostsFile)
    hosts = loadHostsFile(etcHostsFile)
    if (hosts==nil) then
      hosts = {}
    end
  end
  local ipAddrV4 = lookupNameRs(hostName, hosts)
  if (ipAddrV4==nil) then
    printD("qryDNSTypA...")
    ipAddrV4 = qryDNSTypA(hostName, "8.8.8.8", 53)
  end
  return ipAddrV4
end

ipAddrV4 = getLocalNameRs(arg[1]:lower(), arg[2])
print( ipAddrV4 )
os.exit()
