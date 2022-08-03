#!/usr/bin/env lua

local localhost = '*' -- '127.0.0.1'
local localport = 6760
local upstrmServer = "8.8.8.8" -- "192.168.43.1" -- "8.8.8.8" -- !! 192.168.192.1 ==> tcpNotSupported ## 
local upstrmPort = 53
local sendLocalRsp = true

--[[
  dig -p 6760 @192.168.43.1 google.com
--]]

local function hex2Str(s)
  -- https://stackoverflow.com/q/65476909
  -- string.fromhex() ==> return (data:gsub("%x%x", function(digits) return string.char(tonumber(digits, 16)) end))
  -- return (s:gsub(".", function(char) return string.format("%02x", char:byte()) end))
  return (s:gsub("%x%x", function(digits) return string.char(tonumber(digits,16)) end))
end
local function str2Hex(s)
  local bytes = {}
  for i=1,s:len()  do
    bytes[#bytes+1] = ('%02x'):format(s:byte(i,i))
  end
  return table.concat(bytes, '')
end

local function byte2BitsBE(n) -- https://stackoverflow.com/a/9080080
  -- returns a table of bits, least significant first.
  local t={} -- will contain the bits
  while n>0 do
    r = math.fmod(n,2)
    t[#t+1] = string.format("%d", r)
    n = (n-r)/2
  end
  return table.concat(t, '')..string.rep("0",8-#t)
end

local function charAt(s, idx)
  return string.sub(s,idx,idx)
end
local function charAt2BitsBE(s, idx)
  return byte2BitsBE(charAt(s,idx):byte())
end
local function charAt2Bits(s, idx)
  return string.reverse(charAt2BitsBE(s, idx))
end

local function replaceCharAt(s, p, c)
  return s:sub(1, p-1)..c.. s:sub(p+1)
end

local function ipAddrString2Bytes(s)
  local bAddr = ""
  --a1, a2, a3, a4 = string.match(s, '(%d+)%.(%d+)%.(%d+)%.(%d+)')
  a = {}
  for m in string.gmatch(s..".", '(%d+)%.') do
    a[#a+1] = m
    bAddr = bAddr..string.char(tonumber(m))
  end
  if (#a==4) then
    return bAddr
  end
  bAddr = s:gsub(":","")
  if (bAddr=="") then
    bAddr = "00000000000000000000000000000000"
  elseif (#bAddr==1) then
    bAddr = "0000000000000000000000000000000" .. bAddr
  elseif ( not( #bAddr==32 and string.match(string.rep("%x",32)) ) ) then
    bAddr = "00000000000000000000000000000000"
  end
  return hex2Str(bAddr)
end

local function ipAddrBytes2Str(s)
  local aAddr = ""
  if (#s==4) then
    aAddr = ( charAt(s,1):byte() .. "." .. charAt(s,2):byte()
      .. "." .. charAt(s,3):byte()  .. "." .. charAt(s,4):byte()
    )
  elseif (#s==16) then
    aAddr = ( str2Hex(s:sub(1,2))
      .. ":" .. str2Hex(s:sub(3,4))
      .. ":" .. str2Hex(s:sub(5,6))
      .. ":" .. str2Hex(s:sub(7,8))
      .. ":" .. str2Hex(s:sub(9,10))
      .. ":" .. str2Hex(s:sub(11,12))
      .. ":" .. str2Hex(s:sub(13,14))
      .. ":" .. str2Hex(s:sub(15,16))
    )
  else
    aAddr = str2Hex(s)
  end
  return aAddr
end

local function printDnsMsg(strMsg)
  --msgHdrHex = str2Hex(strMsg:sub(1,12)) ; print(msgHdrHex)
  -- ID:2bytes; Flags+OpCode+RespCode:2bytes; RecordsCount:4*2bytes
  byte3 = charAt2Bits(strMsg,3)
  qryRspFlg = tonumber(byte3:sub(1,1))
  opCode = tonumber(byte3:sub(2,5), 2)

  byte4 = charAt2Bits(strMsg,4)
  rspCode = tonumber(byte4:sub(5,8), 2)
  qCount = tonumber(str2Hex(string.sub(strMsg,5,6)),16)
  aCount = tonumber(str2Hex(string.sub(strMsg,7,8)),16)

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
  qType = tonumber(str2Hex(string.sub(strMsg,byteIdx,byteIdx+1)),16) -- 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
  qClass = tonumber(str2Hex(string.sub(strMsg,byteIdx+2,byteIdx+3)),16) -- normally the value 1 for Internet ('IN')
  byteIdx = byteIdx+4 -- end of q1

  print("qName1: "..qName1)
  --print("qType: "..qType.."\nqClass: "..qClass)

  if (qryRspFlg==1 and qCount==1 and aCount > 0) then
    aNameOffset = charAt2Bits(strMsg,byteIdx)
    --print(aNameOffset)
    -- 4.1.4. Message compression https://datatracker.ietf.org/doc/html/rfc1035
    if aNameOffset:sub(1,2)=="11" and strMsg:sub(byteIdx+2,byteIdx+2):byte()==0 then
      aNameOffset = aNameOffset:sub(3,#aNameOffset+1) .. charAt2Bits(strMsg,byteIdx+1)
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

    aType = tonumber(str2Hex(string.sub(strMsg,byteIdx,byteIdx+1)),16) -- 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
    aClass = tonumber(str2Hex(string.sub(strMsg,byteIdx+2,byteIdx+3)),16) -- normally the value 1 for Internet ('IN')
    byteIdx = byteIdx+4 --
    --print("aType:"..aType)
    --print("aClass:"..aClass)

    aTtl = tonumber(str2Hex(string.sub(strMsg,byteIdx,byteIdx+3)),16)
    byteIdx = byteIdx+4 --
    print("aTtl:"..aTtl)

    aSize = tonumber(str2Hex(string.sub(strMsg,byteIdx,byteIdx+1)),16)
    byteIdx = byteIdx+2 --
    --print("aSize:"..aSize)
    print("aAddr:"..ipAddrBytes2Str(strMsg:sub(byteIdx,byteIdx+aSize-1)))

  end

end

local function createLocalRsp(qryData, hostName, ipv4Addr, ipv6Addr)
  local endOfNameData = string.find(qryData, string.char(0), 13, true) -- true==plainTextSearchOnly/noPatternMatching
  local rspData = string.sub(qryData,1,endOfNameData+4) -- remove all trailing data

  local byte3 = string.char( tonumber("1"..(charAt2Bits(rspData,3):sub(2,8)),2) ) -- set qryRspFlg=1
  local byte4 = string.char( tonumber("1"..(charAt2Bits(rspData,4):sub(2,4)).."0000",2) ) -- set recursionAvl=1, rspCode=0
  --byte3=string.char(tonumber("10000001",2)) ; byte4=string.char(tonumber("10000000",2))
  rspData = replaceCharAt(rspData, 3, byte3)
  rspData = replaceCharAt(rspData, 4, byte4)

  local qType = tonumber(str2Hex(string.sub(rspData,endOfNameData+1,endOfNameData+2)),16) -- 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
  print("qType: "..qType)

  local aType = qType
  local aCount = 1

  local aNameData = hex2Str("c00c") -- this is default !!
  --aNameData = hex2Str("06676f6f676c65c013") -- this is accepted !!
  --aNameData = hex2Str("06676f6f676c6503636f6d") -- but this is not !!??
  --aNameData = "-" ; aNameData = string.char(#aNameData)..aNameData..hex2Str("c00c") -- this is OK

  if (aType==28) then
    rData = ipAddrString2Bytes(ipv6Addr)
  else

    -- !! add CNAME !!
    aCount = aCount + 1
    aType5 = 5
    rData = hostName ; rData = string.char(#rData)..rData..string.char(0)
    answerData0 = (
      hex2Str("c00c") .. string.char(0) .. string.char(aType5) .. hex2Str("00010000003c00")
       .. string.char(#rData) .. rData
    )
    aNameData = answerData0..rData

    rData = ipAddrString2Bytes(ipv4Addr)
  end

  answerData = (
    aNameData .. string.char(0)
     .. string.char(aType) .. hex2Str("00010000003c00")
       .. string.char(#rData) .. rData
  )

  rspData = replaceCharAt(rspData, 8, string.char(aCount)) -- set aCount
  rspData = replaceCharAt(rspData, 10, string.char(0)) -- set authCount
  rspData = replaceCharAt(rspData, 12, string.char(0)) -- set addlCount
  rspData = rspData .. answerData

  return rspData 
end

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
    --print(str2Hex(data))
    print(data)

    if sendLocalRsp then
      localRsp = createLocalRsp(data, "localhost", "127.0.0.1", "::1")
      --print(str2Hex(localRsp))
      print(localRsp)
      udp:sendto(localRsp, clntMsgOrIp, clntPort)
      --goto continue
    else
      udpUpstrm:sendto(data, upstrmServer, upstrmPort)
      upstrmRsp, upstrmMsgOrIp, upstrmPort1 = udpUpstrm:receivefrom()
      if upstrmRsp then
        print(("udpUpstrm:receivefrom %s:%s (%d bytes)"):format(
          upstrmMsgOrIp, upstrmPort1, string.len(upstrmRsp)
        ))
        print(str2Hex(upstrmRsp))
        --print(upstrmRsp)
        printDnsMsg(upstrmRsp)

        msgHdrHex = str2Hex(upstrmRsp:sub(1,12))
        rcode = tonumber(msgHdrHex:sub(8,8), 16)
        if (rcode == 1) then
          print("Request is not a DNS query. Format Error!")
        elseif (rcode ~= 0) then
          print(string.format("Error Response [%d]!", rcode))
        else
          print("Success!")
          --print(str2Hex(upstrmRsp))
        end

        udp:sendto(upstrmRsp, clntMsgOrIp, clntPort)
      else
        print("udpUpstrm:error %s", upstrmMsgOrIp) 
      end
    end
  elseif clntMsgOrIp ~= 'timeout' then
     error("Unknown network error: "..tostring(msg))
  end
  ::continue::
end
