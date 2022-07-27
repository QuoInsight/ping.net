#!/usr/bin/env lua

local localhost = '*' -- '127.0.0.1'
local localport = 6760
local upstrmServer = "8.8.8.8" -- "192.168.43.1" -- "8.8.8.8" -- !! 192.168.192.1 ==> tcpNotSupported ## 
local upstrmPort = 53

--[[
  dig -p 6760 @192.168.43.1 google.com
--]]

local function strToHex(s)
  -- https://stackoverflow.com/q/65476909
  -- string.fromhex() ==> return (data:gsub("%x%x", function(digits) return string.char(tonumber(digits, 16)) end))
  -- return (s:gsub(".", function(char) return string.format("%02x", char:byte()) end))
  local bytes = {}
  for i=1,s:len()  do
    bytes[#bytes+1] = ('%02x'):format(s:byte(i,i))
  end
  return table.concat(bytes, '')
end

local function numToBits(n) -- https://stackoverflow.com/a/9080080
  -- returns a table of bits, least significant first.
  local t={} -- will contain the bits
  while n>0 do
    r = math.fmod(n,2)
    t[#t+1] = string.format("%d", r)
    n = (n-r)/2
  end
  return table.concat(t, '')
end

local function charAt(s, idx)
  return string.sub(s,idx,idx)
end

local function charAtToBits(s, idx)
  return string.reverse(numToBits(charAt(s,idx):byte()))
end

local function printDnsMsg(strMsg)
  --msgHdrHex = strToHex(strMsg:sub(1,12)) ; print(msgHdrHex)
  -- ID:2bytes; Flags+OpCode+RespCode:2bytes; RecordsCount:4*2bytes
  byte3 = charAtToBits(strMsg,3)
  qryRspFlg = tonumber(byte3:sub(1,1))
  opCode = tonumber(byte3:sub(2,5), 2)

  byte4 = charAtToBits(strMsg,4)
  rspCode = tonumber(byte4:sub(5,8), 2)
  qCount = tonumber(strToHex(string.sub(strMsg,5,6)),16)
  aCount = tonumber(strToHex(string.sub(strMsg,7,8)),16)

  print(string.format("[Header] qryRspFlg:%d opCode:%d rspCode:%d qCount:%d aCount:%d",
    qryRspFlg, opCode, rspCode, qCount, aCount
  ))

  byteIdx = 13
  qName1 = ""
  while true
  do
    sz1 = string.sub(strMsg,byteIdx,byteIdx):byte();  byteIdx = byteIdx + 1;
    if sz1==0 then break end
    byteIdx2 = byteIdx + sz1 - 1
    qName1 = qName1 .. strMsg:sub(byteIdx,byteIdx2) .. "."
    byteIdx = byteIdx2 + 1
  end
  qType = tonumber(strToHex(string.sub(strMsg,byteIdx,byteIdx+1)),16) -- 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
  qClass = tonumber(strToHex(string.sub(strMsg,byteIdx+2,byteIdx+3)),16) -- normally the value 1 for Internet ('IN')
  byteIdx = byteIdx+4 -- end of q1

  print("qName1: "..qName1)
  --print("qType: "..qType.."\nqClass: "..qClass)

  if (qryRspFlg==1 and qCount==1 and aCount > 0) then
    aNameOffset = charAtToBits(strMsg,byteIdx)
    --print(aNameOffset)
    -- 4.1.4. Message compression https://datatracker.ietf.org/doc/html/rfc1035
    if aNameOffset:sub(1,2)=="11" and strMsg:sub(byteIdx+2,byteIdx+2):byte()==0 then
      aNameOffset = aNameOffset:sub(3,#aNameOffset+1) .. charAtToBits(strMsg,byteIdx+1)
      aNameOffset = tonumber(aNameOffset, 2)
      --print("aNameOffset:"..aNameOffset)
      -- we will simply use qName1 above and advance 2 bytes below to the next data
      aName1 = qName1
      byteIdx = byteIdx + 2
    else
      aNameOffset = 0
      aName1 = ""
      while true
      do
        sz1 = string.sub(strMsg,byteIdx,byteIdx):byte();  byteIdx = byteIdx + 1;
        if sz1==0 then break end
        byteIdx2 = byteIdx + sz1 - 1
        aName1 = aName1 .. strMsgsub(byteIdx,byteIdx2) .. "."
        byteIdx = byteIdx2 + 1
      end
    end

    aType = tonumber(strToHex(string.sub(strMsg,byteIdx,byteIdx+1)),16) -- 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
    aClass = tonumber(strToHex(string.sub(strMsg,byteIdx+2,byteIdx+3)),16) -- normally the value 1 for Internet ('IN')
    byteIdx = byteIdx+4 --
    --print("aType:"..aType)
    --print("aClass:"..aClass)

    aTtl = tonumber(strToHex(string.sub(strMsg,byteIdx,byteIdx+3)),16)
    byteIdx = byteIdx+4 --
    print("aTtl:"..aTtl)

    aSize = tonumber(strToHex(string.sub(strMsg,byteIdx,byteIdx+1)),16)
    byteIdx = byteIdx+2 --
    --print("aSize:"..aSize)

    if aSize==4 then
      aAddr = ( charAt(strMsg,byteIdx):byte() .. "." .. charAt(strMsg,byteIdx+1):byte()
        .. "." .. charAt(strMsg,byteIdx+2):byte()  .. "." .. charAt(strMsg,byteIdx+3):byte()
      )
    elseif aSize==16 then
      aAddr = ( strToHex(strMsg:sub(byteIdx,byteIdx+1))
        .. ":" .. strToHex(strMsg:sub(byteIdx+2,byteIdx+3))
        .. ":" .. strToHex(strMsg:sub(byteIdx+4,byteIdx+5))
        .. ":" .. strToHex(strMsg:sub(byteIdx+6,byteIdx+7))
        .. ":" .. strToHex(strMsg:sub(byteIdx+8,byteIdx+9))
        .. ":" .. strToHex(strMsg:sub(byteIdx+10,byteIdx+11))
        .. ":" .. strToHex(strMsg:sub(byteIdx+12,byteIdx+13))
        .. ":" .. strToHex(strMsg:sub(byteIdx+14,byteIdx+15))
      )
    else
      aAddr = "?"
    end
    print("aAddr:"..aAddr)

  end

end

--[[
data = "32c10100000100000000000006676f6f676c6503636f6d00001c0001"
data = "a9d58180000100010000000006676f6f676c6503636f6d0000010001c00c00010001000000eb0004acd91a4e"
data = (data:gsub("%x%x", function(digits) return string.char(tonumber(digits, 16)) end))
print(data) -- 
--print(strToHex(string.sub(data,1,12)))
printDnsMsg(data)
os.exit()
--]]

local socket = require("socket")

local udpUpstrm = socket.udp()
udpUpstrm:settimeout(5)

local udp = socket.udp()
udp:settimeout(0)
udp:setsockname(localhost, localport)

print "Beginning server loop."
while true
do
  data, clntMsgOrIp, clntPort = udp:receivefrom()
  if data then
    time = os.date("*t")
    print(("\n%02d:%02d:%02d udp:receivefrom %s:%s (%d bytes)"):format(
      time.hour, time.min, time.sec, clntMsgOrIp, clntPort, string.len(data)
    ))
    print(data) -- string.fromhex()
    --print(strToHex(data))
    --print(data:gsub(".", function(char) return string.format("%02x", char:byte()) end))

    udpUpstrm:sendto(data, upstrmServer, upstrmPort)
    upstrmAnswer, upstrmMsgOrIp, upstrmPort1 = udpUpstrm:receivefrom()
    if upstrmAnswer then
      print(("udpUpstrm:receivefrom %s:%s (%d bytes)"):format(
        upstrmMsgOrIp, upstrmPort1, string.len(upstrmAnswer)
      ))
      print(upstrmAnswer)
      printDnsMsg(upstrmAnswer)

      msgHdrHex = strToHex(upstrmAnswer:sub(1,12))
      rcode = tonumber(msgHdrHex:sub(8,8), 16)
      if (rcode == 1) then
        print("Request is not a DNS query. Format Error!")
      elseif (rcode ~= 0) then
        print(string.format("Error Response [%d]!", rcode))
      else
        print("Success!")
        --print(strToHex(upstrmAnswer))
      end

      udp:sendto(upstrmAnswer, clntMsgOrIp, clntPort)
    else
      print("udpUpstrm:error %s", upstrmMsgOrIp) 
    end
  elseif clntMsgOrIp ~= 'timeout' then
     error("Unknown network error: "..tostring(msg))
  end
end
