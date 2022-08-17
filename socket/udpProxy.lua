#!/usr/bin/env lua

local svcAddr = '*' -- '127.0.0.1'
local svcPort = 50053 -- netstat -a -n -o | find "50053"
local upstrmServer = "8.8.8.8"
local upstrmPort = 53

------------------------------------------------------------------------

local function str2Hex(s)
  local bytes = {}
  for i=1,s:len() do
    bytes[#bytes+1] = ('%02x'):format(s:byte(i,i))
  end
  return table.concat(bytes, '')
end

------------------------------------------------------------------------

local function getDeviceLanIpAddr()
  local function _exeCmd(cmdln)
    local file = assert(io.popen(cmdln, 'r'))
    local output = file:read('*all')
    file:close()
    output = string.gsub(output, "^%s*(.-)%s*$", "%1") --trim
    return output
  end
  local cmdln = "ifconfig br-lan | grep -F 'inet addr:' | sed -r 's/^\\s*inet addr:([^ ]+).*/\\1/'"
  return _exeCmd(cmdln)
end

local function getMachineIpAddr()
  addr,details = socket.dns.toip(socket.dns.gethostname())
  return addr
end

local function getInterfaceIpAddr(sckt)
  local pcallOK,addr,port = pcall( function() return sckt:getpeername() end )
  if not pcallOK then sckt:setpeername("12.34.56.78",12345) end
  local addr,port,fmly = sckt:getsockname()
  if pcallOK then
    sckt:setpeername(addr,port)
  else
    sckt:setpeername('*')
  end
  return addr
end

------------------------------------------------------------------------

local socket = require("socket")

local upstrmSckt = socket.udp()
upstrmSckt:settimeout(5)

local svcSckt = socket.udp()
if svcAddr=='*' then svcAddr=getDeviceLanIpAddr() end
-- somehow svcAddr='*'|INADDR_ANY is not reliable and --
-- causing svcSckt:sendto() not received correctly by --
-- some downstream clients (e.g. nslookup/dig/py) !!! --
-- no issue with INADDR_ANY for loopback connections, --
-- or with luasocket udp as remote client !??         --
svcSckt:settimeout(5)
svcSckt:setoption('reuseaddr',true)
svcSckt:setsockname(svcAddr, svcPort)

print "Beginning server loop ..."
while true do
  data, srcAddrOrErrMsg, srcPort = svcSckt:receivefrom()
  if data then
    local time = os.date("*t")
    print(("\n%02d:%02d:%02d [svcSckt:receivefrom] %s:%s (%d bytes)"):format(
      time.hour, time.min, time.sec, srcAddrOrErrMsg, srcPort, string.len(data)
    ))
    print(str2Hex(data))
    print(data)

    upstrmSckt:sendto(data, upstrmServer, upstrmPort)
    upstrmRsp, upstrmSrcAddrOrErrMsg, upstrmSrcPort = upstrmSckt:receivefrom()
    if upstrmRsp then
      print(("[upstrmSckt:receivefrom] %s:%s (%d bytes)"):format(
        upstrmSrcAddrOrErrMsg, upstrmSrcPort, string.len(upstrmRsp)
      ))
      print(str2Hex(upstrmRsp))
      print(upstrmRsp)

      svcSckt:sendto(upstrmRsp, srcAddrOrErrMsg, srcPort)
    else
      print("[upstrmSckt:error] ", upstrmSrcAddrOrErrMsg) 
    end
  elseif srcAddrOrErrMsg=='timeout' then
    --print("timeout")
  else
    error("[svcSckt:error] "..tostring(srcAddrOrErrMsg))
  end
end
