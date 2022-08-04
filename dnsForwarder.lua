#!/usr/bin/env lua

local localhost = '*' -- '127.0.0.1'
local localport = 6760
local upstrmServer = "8.8.8.8" -- "192.168.43.1" -- "8.8.8.8" -- !! 192.168.192.1 ==> tcpNotSupported ## 
local upstrmPort = 53
local sendLocalRsp = true
local printRawMsg = false

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

local function getRdName(nameData)
  local idx = 1
  local rName = ""
  while true do
    local sz1 = string.sub(nameData,idx,idx):byte()
    idx = idx+1; if sz1==0 then break end
    if sz1<192 then
      rName = rName..nameData:sub(idx,idx+sz1-1).."."
      idx = idx+sz1
    else
     --[[
      refNameOffset = byte2BitsBE(sz1):reverse()
      refNameOffset = aNameOffset:sub(3,#refNameOffset) .. charAt2Bits(nameData,idx)
      refNameOffset = tonumber(refNameOffset, 2)
      --print("refNameOffset: "..refNameOffset)
      -- 4.1.4. Message compression https://datatracker.ietf.org/doc/html/rfc1035
     --]]
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

local function getRdType(qnAnsData)
  local endOfNameData = string.find(qnAnsData, string.char(0), 1, true) -- true==plainTextSearchOnly/noPatternMatching
  local rspData = string.sub(qnAnsData,1,endOfNameData+4) -- remove all trailing data
  return tonumber(str2Hex(string.sub(qnAnsData,endOfNameData+1,endOfNameData+2)),16) -- 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
end

local function printDnsMsg(strMsg)
  --msgHdrHex = str2Hex(strMsg:sub(1,12)) ; print(msgHdrHex)
  -- ID:2bytes; Flags+OpCode+RespCode:2bytes; RecordsCount:4*2bytes
  byte3 = charAt2Bits(strMsg,3)
  qryRspFlg = tonumber(byte3:sub(1,1))
  opCode = tonumber(byte3:sub(2,5), 2)

  byte4 = charAt2Bits(strMsg,4)
  rspCode = tonumber(byte4:sub(5,8), 2)
  qCount = bytes2Num(string.sub(strMsg,5,6))
  aCount = bytes2Num(string.sub(strMsg,7,8))

  print(string.format("[Header] qryRspFlg:%d opCode:%d rspCode:%d qCount:%d aCount:%d",
    qryRspFlg, opCode, rspCode, qCount, aCount
  ))

  qName1 = getRdName(strMsg:sub(13, #strMsg));
  byteIdx = 13 + #qName1+1 -- this is assuming the name is not expanded
  qType = tonumber(str2Hex(string.sub(strMsg,byteIdx,byteIdx+1)),16) -- 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
  qClass = tonumber(str2Hex(string.sub(strMsg,byteIdx+2,byteIdx+3)),16) -- normally the value 1 for Internet ('IN')
  byteIdx = byteIdx+4 -- end of q1

  print("qName1: ["..qName1.."] qType:"..qType.." qClass:"..qClass)

  if (qryRspFlg==1 and qCount==1 and aCount > 0) then
    aName1 = getRdName(strMsg:sub(byteIdx, #strMsg));
    --print("byteIdx:"..byteIdx.." #aName1:"..#aName1)
    byteIdx = byteIdx + #aName1+1 -- this is assuming the name is not expanded

    aType = bytes2Num(string.sub(strMsg,byteIdx,byteIdx+1)) -- 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
    aClass = bytes2Num(string.sub(strMsg,byteIdx+2,byteIdx+3)) -- normally the value 1 for Internet ('IN')
    byteIdx = byteIdx+4 --
    print("aType:"..aType.." aClass:"..aClass.." aName1: ["..aName1.."]")

    aTtl = bytes2Num(string.sub(strMsg,byteIdx,byteIdx+3))
    byteIdx = byteIdx+4 --
    aSize = bytes2Num(string.sub(strMsg,byteIdx,byteIdx+1))
    byteIdx = byteIdx+2 --
    print("aTtl:"..aTtl.." aSize:"..aSize)

    aData = strMsg:sub(byteIdx,byteIdx+aSize-1)
    if (aType==5) then
      print("cname: "..getRdName(aData..string.char(0)));
    elseif (aType==1 or aType==28) then
      print("ip: "..ipAddrBytes2Str(aData))
    else
      print("data: "..str2Hex(aData))
    end
  end
end

local function createLocalRsp(qryData, hostName, ipAddrV4, ipAddrV6)
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
  local rData = ""

  local aNameData = hex2Str("c00c") -- this is default !!
  --aNameData = hex2Str("06676f6f676c65c013") -- this is accepted !!
  --aNameData = hex2Str("06676f6f676c6503636f6d") -- but this is not !!??
  --aNameData = "-" ; aNameData = string.char(#aNameData)..aNameData..hex2Str("c00c") -- this is OK

  if (aType==28) then
    if (ipAddrV6=="" or ipAddrV6=="::") then
      aCount = 0 -- this simply means we do not have any ipAddrV6 record
    else
      rData = ipAddrString2Bytes(ipAddrV6)
    end
  elseif (aType==1) then
    if (ipAddrV4=="" or ipAddrV4=="0.0.0.0") then
      aCount = 0 -- this simply means we do not have any ipAddrV4 record
  else

    -- !! add CNAME !!
    aCount = aCount + 1
    aType5 = 5
    rData = hostName ; rData = string.char(#rData)..rData..string.char(0)
    answerData0 = (
        hex2Str("c00c") .. string.char(0)
         .. string.char(aType5) .. hex2Str("00010000003c00")
          .. string.char(#rData) .. rData
      )
      aNameData = answerData0..rData

      rData = ipAddrString2Bytes(ipAddrV4)
    end
  else
    aCount = 0
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
    if printRawMsg then
      print(str2Hex(data))
      print(data)
    end
    endOfNameData = data:find(string.char(0), 13, true) -- true==plainTextSearchOnly/noPatternMatching
    qName = getRdName(data:sub(13,endOfNameData))
    print(clntMsgOrIp..": query ["..qName.."]")

    if sendLocalRsp then
      if printRawMsg then
        udpUpstrm:sendto(data, upstrmServer, upstrmPort)
        upstrmRsp, upstrmMsgOrIp, upstrmPort1 = udpUpstrm:receivefrom()
        print(str2Hex(upstrmRsp))
      end

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
        if printRawMsg then
          print(str2Hex(upstrmRsp))
          print(upstrmRsp)
        end
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
