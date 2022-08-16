#!/usr/bin/env lua

local svcAddr = '*' -- '127.0.0.1' -- http://127.0.0.01:8080
local svcPort = 8080 -- netstat -a -n -o | find "8080"
local upstrmServer = "192.168.43.1"
local upstrmPort = 80
local httpContent = true

------------------------------------------------------------------------

local function str2Hex(s)
  local bytes = {}
  for i=1,s:len() do
    bytes[#bytes+1] = ('%02x'):format(s:byte(i,i))
  end
  return table.concat(bytes, '')
end

local function printHeadTail(data, excerptLength, showHex)
  local tailEnd = #data
  local tailStart = (tailEnd-excerptLength)
  if tailStart<1 then tailStart=1 end
  local tailData = data:sub(tailStart,tailEnd)
  if tailStart>1 then
    --tailData = data:sub(1,tailEnd-tailStart) .. string.rep(string.char(0),4) .. tailData
    tailData = data:sub(1,tailEnd-tailStart) .. "<<<>>>" .. tailData
  end
  if showHex then tailData=str2Hex(tailData) end
  print(tailData)
end

local function scktReceiveData(sckt, chnkSz, nTimeout, dataType)
  local count = 0
  local dataAll = ""
  repeat
    count = count + 1
    local rcvData,rcvErr,rcvPartial = sckt:receive(chnkSz)
    -- default :receive('*l'): read text line !!
    -- :receive('*a') not working here ??!
    sckt:settimeout(nTimeout) -- shorten timeout for subsequent data
    dataAll = dataAll .. (rcvData or rcvPartial)
    if (rcvErr~=nil) then
      print("count:"..count.." rcvErr:"..rcvErr)
      break
    --elseif (rcvData:sub(-1):byte()==10) then
    --  print("count:"..count.." <eof>"..)
    --  break
    end
  until (rcvErr~=nil)
  return dataAll
end

------------------------------------------------------------------------

local socket = require("socket")

local svcSckt = assert(socket.bind(svcAddr, svcPort))
local svcAddr1,svcPort1 = svcSckt:getsockname()
svcSckt:settimeout(10)

print("Beginning server loop ["..svcAddr1..":"..svcPort1.."] ...")
while true do
  local clientSckt,err = svcSckt:accept()
  if clientSckt then
    local time = os.date("*t")
    print(("\n%02d:%02d:%02d [svcSckt:accept] %s"):format(
      time.hour, time.min, time.sec, clientSckt:getpeername()
    ))
    clientSckt:settimeout(3)
    local data =  scktReceiveData(clientSckt, 64, 1, "HTTP")
    if data then
      local clientAddr,clientPort = clientSckt:getsockname()
      print(("[clientSckt:receive] (%d bytes)"):format(
        string.len(data)
      ))
      --print(str2Hex(data));  --print(data)
      --printHeadTail(data, 50, true)
      printHeadTail(data, 35, false)

      -- data = "GET / HTTP/1.1\r\n\r\n"

      local upstrmSckt = assert(socket.tcp())
      upstrmSckt:settimeout(5)
      upstrmSckt:connect(upstrmServer, upstrmPort)
      upstrmSckt:send(data.."\r\n\r\n")
      local upstrmRsp = scktReceiveData(upstrmSckt, 128, 1, "HTTP")
      upstrmSckt:close()

      local time = os.date("*t")
      print(("%02d:%02d:%02d [upstrmSckt:receivefrom] %s:%s (%d bytes)"):format(
        time.hour, time.min, time.sec, upstrmServer, upstrmPort, string.len(upstrmRsp)
      ))
      --print(str2Hex(upstrmRsp));  --print(upstrmRsp)
      --printHeadTail(upstrmRsp, 50, true)
      printHeadTail(upstrmRsp, 35, false)
      
      --upstrmRsp = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\n\nOK"

      clientSckt:send(upstrmRsp.."\r\n\r\n")
    elseif err=='timeout' then
      --print("timeout")
    else
      error("[clientSckt:error] "..tostring(err))
    end
    clientSckt:close()
  elseif err=='timeout' then
    --print("timeout")
  else
    error("[svcSckt:error] "..tostring(err))
  end
end
