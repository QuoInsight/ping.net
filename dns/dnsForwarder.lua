#!/usr/bin/env lua

local localhost = '*' -- '127.0.0.1'
local localport = 50053
local upstrmServer = "8.8.8.8" -- "192.168.43.1" -- "8.8.8.8" -- !! 192.168.192.1 ==> tcpNotSupported ## 
local upstrmPort = 53
local sendLocalRsp = false
local printRawMsg = false

--[[
  inspired by https://github.com/tigerlyb/DNS-Proxy-Server-in-Python
  dig -p 50053 @192.168.43.1 google.com
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

local function bytes2Num(bytes)
  return tonumber(str2Hex(bytes),16)
end
local function bytesBE2Num(bytesBE)
  return bytes2Num(bytesBE:reverse())
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

------------------------------------------------------------------------

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

------------------------------------------------------------------------

local function getRdName(rawData, startIdx)
  local idx = startIdx
  local rName = ""
  while true do
    local sz1 = string.sub(rawData,idx,idx):byte()
    idx = idx+1; if sz1==0 then break end
    if sz1<192 then
      rName = rName..rawData:sub(idx,idx+sz1-1).."."
      idx = idx+sz1
    else
      local refNameOffset = byte2BitsBE(sz1):reverse()
      refNameOffset = refNameOffset:sub(3,#refNameOffset) .. charAt2Bits(rawData,idx)
      refNameOffset = tonumber(refNameOffset, 2)
      --print("refNameOffset: "..refNameOffset)
      -- 4.1.4. Message compression https://datatracker.ietf.org/doc/html/rfc1035
      print(" >> "..rName..getRdName(rawData, refNameOffset+1))
      rName = rName.."*" -- we will not follow the reference/pointer and expand the name here,
      -- this allows us to keep the same length in the string output as the raw data !!
      idx = idx+1
      -- if a reference/pointer is found/used, it must either be the only element
      -- or the last element !! no additional null character after this !!
      -- hence, we should return immediately and ends here
      return rName
    end
  end
  return rName
end

local function findEndOfNameData(rawData, startIdx)
  local idx = startIdx
  while true do
    local sz1 = string.sub(rawData,idx,idx):byte()
    if sz1==0 then
      return idx
    elseif sz1<64 then
      idx = idx+sz1+1
      if idx>#rawData then
        return nil -- data error
      end
    else -- elseif sz1>=192 then
      return idx+1
      -- 4.1.4. Message compression https://datatracker.ietf.org/doc/html/rfc1035
      -- if a reference/pointer is found/used, it must either be the only element
      -- or the last element !! no additional null character after this !!
      -- hence, we should return immediately and ends here
    end
  end
  return nil
end

local function getRdType(qnAnsData)
  local endOfNameData = string.find(qnAnsData, string.char(0), 1, true) -- true==plainTextSearchOnly/noPatternMatching
  -- above will assume the name ends with a null character / zero octet,
  -- however this will not work correctly in the answer section when the
  -- name ends with a reference/pointer instead
  local rspData = string.sub(qnAnsData,1,endOfNameData+4) -- remove all trailing data
  return bytes2Num(string.sub(qnAnsData,endOfNameData+1,endOfNameData+2)) -- 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
end

local function printDnsMsg(strMsg)
  --msgHdrHex = str2Hex(strMsg:sub(1,12)) ; print(msgHdrHex)
  -- ID:2bytes; Flags+OpCode+RespCode:2bytes; RecordsCount:4*2bytes
  byte3 = charAt2Bits(strMsg,3)
  qryRspFlg = tonumber(byte3:sub(1,1))
  opCode = tonumber(byte3:sub(2,5), 2)

  byte4 = charAt2Bits(strMsg,4)
  rspCode = tonumber(byte4:sub(5,8), 2)
  qCount = bytes2Num(strMsg:sub(5,6))
  aCount = bytes2Num(strMsg:sub(7,8))

  print(string.format("[Header] qryRspFlg:%d opCode:%d rspCode:%d qCount:%d aCount:%d",
    qryRspFlg, opCode, rspCode, qCount, aCount
  ))

  local byteIdx = 13
  for count = 1,qCount,1 do
    qName1 = getRdName(strMsg, byteIdx);
    byteIdx = byteIdx + #qName1+1 -- this is assuming the name is not expanded
    qType = bytes2Num(strMsg:sub(byteIdx,byteIdx+1)) -- 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
    qClass = bytes2Num(strMsg:sub(byteIdx+2,byteIdx+3)) -- normally the value 1 for Internet ('IN')
    byteIdx = byteIdx+4 -- end of q1

    print("qName"..count..": ["..qName1.."] qType:"..qType.." qClass:"..qClass)
  end

  if (qryRspFlg==1 and qCount>0 and aCount>0) then
    for count = 1,aCount,1 do
      aName1 = getRdName(strMsg, byteIdx);
      --print("byteIdx:"..byteIdx.." #aName1:"..#aName1)
      byteIdx = byteIdx + #aName1+1 -- this is assuming the name is not expanded

      aType = bytes2Num(string.sub(strMsg,byteIdx,byteIdx+1)) -- 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
      aClass = bytes2Num(string.sub(strMsg,byteIdx+2,byteIdx+3)) -- normally the value 1 for Internet ('IN')
      byteIdx = byteIdx+4 --
      print("aType:"..aType.." aClass:"..aClass.." aName"..count..": ["..aName1.."]")

      aTtl = bytes2Num(string.sub(strMsg,byteIdx,byteIdx+3))
      byteIdx = byteIdx+4 --
      aSize = bytes2Num(string.sub(strMsg,byteIdx,byteIdx+1))
      byteIdx = byteIdx+2 --
      print("aTtl:"..aTtl.." aSize:"..aSize)

      aData = strMsg:sub(byteIdx,byteIdx+aSize-1)
      if (aType==5) then
        print("cname: ["..getRdName(strMsg,byteIdx).."]");
      elseif (aType==1 or aType==28) then
        print("ip: ["..ipAddrBytes2Str(aData).."]")
      else
        print("data: ["..str2Hex(aData).."]")
      end
      byteIdx = byteIdx+aSize
    end
  end
end

------------------------------------------------------------------------

local function overrideTTL(strMsg, ttl)
  local rMsg = strMsg
  --msgHdrHex = str2Hex(strMsg:sub(1,12)) ; print(msgHdrHex)
  -- ID:2bytes; Flags+OpCode+RespCode:2bytes; RecordsCount:4*2bytes
  local byte4 = charAt2Bits(strMsg,4)
  local rspCode = tonumber(byte4:sub(5,8), 2)
  local qCount = bytes2Num(strMsg:sub(5,6))
  local aCount = bytes2Num(strMsg:sub(7,8))
  local byteIdx = 13
  for count = 1,qCount,1 do
    endOfNameData = findEndOfNameData(strMsg, byteIdx)
    byteIdx = endOfNameData+1+4 -- end of q1
  end
  if (qCount>0 and aCount > 0) then
    for count = 1,aCount,1 do
      endOfNameData = findEndOfNameData(strMsg, byteIdx)
      byteIdx = endOfNameData+1+4 -- end of a1

      aTtl = bytes2Num(string.sub(strMsg,byteIdx,byteIdx+3))
      rMsg = rMsg:sub(1, byteIdx-1)..hex2Str(string.format("%08x",ttl)).. rMsg:sub(byteIdx+4)
      byteIdx = byteIdx+4 --

      aSize = bytes2Num(string.sub(strMsg,byteIdx,byteIdx+1))
      byteIdx = byteIdx+2 --
      print("updated aTtl:"..aTtl.."-->"..ttl.." aSize:"..aSize)

      byteIdx = byteIdx+aSize
    end
  end
  return rMsg
end

------------------------------------------------------------------------

local function getCustomNameResolution(hostName, clientIpAddr)
  --local macAddr = string.gsub(ipAddr2MAC(clientIpAddr),"[:-]","")
  --local customNameServiceFile = "hosts."..macAddr:lower()
  local ipAddrV4 = nil

  ipAddrV4 = "127.0.0.1"
  return ipAddrV4
end

------------------------------------------------------------------------

local function encodeNameData(qName)
  local qData = ""
  for n1,_ in string.gmatch(qName..'.', "([^%.]+)%.") do
    qData = qData .. string.char(#n1) .. n1
  end
  --print(str2Hex(qData))
  return qData
end

local function createDnsAnswer0(qryId, qName, qType)
  return qryId .. hex2Str("81800001000000000000")
    .. encodeNameData(qName) .. hex2Str("00")
      .. hex2Str(string.format("%04x",qType))
        ..  hex2Str("0001")
end

local function createDnsAnswerTypeA(qryId, hostName, ipAddrV4, ttl)
 --[[
  dig -p 50053 @127.0.0.1 google.com
  data = "8180000100010000000006676f6f676c6503636f6d0000010001c00c00010001000000eb0004acd91a4e"
 --]]
  return qryId .. hex2Str("81800001000100000000")
    .. encodeNameData(hostName)
      .. hex2Str("0000010001c00c00010001")
        .. hex2Str(string.format("%08x",ttl))
          .. hex2Str("0004") .. ipAddrString2Bytes(ipAddrV4)
end

------------------------------------------------------------------------

local function forwardDnsQuery(qryData, udpUpstrm, upstrmServer, upstrmPort)
  udpUpstrm:settimeout(5)

  udpUpstrm:sendto(qryData, upstrmServer, upstrmPort)
  local upstrmRsp, upstrmSrcAddrOrErrMsg, upstrmSrcPort = udpUpstrm:receivefrom()

  if upstrmRsp then
    print(("udpUpstrm:receivefrom %s:%s (%d bytes)"):format(
      upstrmSrcAddrOrErrMsg, upstrmSrcPort, string.len(upstrmRsp)
    ))
  else
    print("udpUpstrm:error %s", upstrmSrcAddrOrErrMsg) 
  end

  udpUpstrm:close()
  return upstrmRsp
end

------------------------------------------------------------------------

local socket = require("socket")

local udp = socket.udp()
udp:settimeout(0)
udp:setsockname(localhost, localport)

print "Beginning server loop."
while true
do
  data, srcAddrOrErrMsg, srcPort = udp:receivefrom()
  if data then
    time = os.date("*t")
    print(("\n%02d:%02d:%02d udp:receivefrom %s:%s (%d bytes)"):format(
      time.hour, time.min, time.sec, srcAddrOrErrMsg, srcPort, string.len(data)
    ))
    if printRawMsg then
      print(str2Hex(data))
      print(data)
    end

    endOfNameData = data:find(string.char(0), 13, true) -- true==plainTextSearchOnly/noPatternMatching
    qName = getRdName(data, 13)
    byteIdx = 13 + #qName+1 -- this is assuming the name is not expanded
    qType = bytes2Num(data:sub(byteIdx,byteIdx+1)) -- 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
    qClass = bytes2Num(data:sub(byteIdx+2,byteIdx+3)) -- normally the value 1 for Internet ('IN')

    print(srcAddrOrErrMsg..": query ["..qName.."]")

    if (sendLocalRsp) then
      if (qType==1) then
        cnrIpAddrV4 = getCustomNameResolution(qName, clientIpAddr)
        rspData = createDnsAnswerTypeA(data:sub(1,2), qName, cnrIpAddrV4, 60)
      else
        rspData = createDnsAnswer0(data:sub(1,2), qName, qType)
      end
    end

    if (not sendLocalRsp) then
      rspData = forwardDnsQuery(data, socket.udp(), upstrmServer, upstrmPort)
      rspData = overrideTTL(rspData, 60) --
    end

    if printRawMsg then
      print(str2Hex(rspData))
      print(rspData)
    end
    printDnsMsg(rspData)

    udp:sendto(rspData, srcAddrOrErrMsg, srcPort)

  elseif srcAddrOrErrMsg ~= 'timeout' then
    error("Unknown network error: "..tostring(srcAddrOrErrMsg))
  end
  ::continue::
end
