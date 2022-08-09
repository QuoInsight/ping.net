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

local socket = require("socket")

local upstrmSckt = socket.udp()
upstrmSckt:settimeout(5)

local svcSckt = socket.udp()
svcSckt:settimeout(5)
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
