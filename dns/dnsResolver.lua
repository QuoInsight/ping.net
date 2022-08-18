#!/usr/bin/env lua

local svcAddr = '*' -- '127.0.0.1'
local svcPort = 50053
local printRawMsg = false

if #arg>=2 then svcAddr=arg[2] end
if #arg>=1 then svcPort=arg[1] end

------------------------------------------------------------------------

--[[
  inspired by https://github.com/tigerlyb/DNS-Proxy-Server-in-Python
  dig -p 50053 @192.168.43.1 google.com
--]]

------------------------------------------------------------------------

local function _exeCmd(cmdln)
  local file = assert(io.popen(cmdln, 'r'))
  local output = file:read('*all')
  file:close()
  output = string.gsub(output, "^%s*(.-)%s*$", "%1") --trim
  return output
end

local function getLanIpAddr()
  local cmdln = "ifconfig br-lan | grep -F 'inet addr:' | sed -r 's/^\\s*inet addr:([^ ]+).*/\\1/'"
  return _exeCmd(cmdln)
end

------------------------------------------------------------------------

local function hex2Str(s)
  return (s:gsub("%x%x", function(digits) return string.char(tonumber(digits,16)) end))
end
local function str2Hex(s)
  local bytes = {}
  for i=1,s:len() do
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
      -- 4.1.4. Message compression https://datatracker.ietf.org/doc/html/rfc1035
      print(" >> "..rName..getRdName(rawData, refNameOffset+1))
      rName = rName.."*" -- we will not follow the reference/pointer and expand the name here,
      -- this allows us to keep the same length in the string output as the raw data !!
      idx = idx+1
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
    end
  end
  return nil
end

------------------------------------------------------------------------

local function getCustomNameResolution(hostName, clientIpAddr)
  if charAt(hostName, #hostName)=="." then hostName=hostName:sub(1,#hostName-1) end
  local cmdln = '/root/localNameRs.lua '..hostName..' '..clientIpAddr
  print(cmdln)
  return _exeCmd(cmdln)
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
  return qryId .. hex2Str("81800001000100000000")
    .. encodeNameData(hostName)
      .. hex2Str("0000010001c00c00010001")
        .. hex2Str(string.format("%08x",ttl))
          .. hex2Str("0004") .. ipAddrString2Bytes(ipAddrV4)
end

------------------------------------------------------------------------

local socket = require("socket")

local udp = socket.udp()
if svcAddr=='*' then svcAddr=getLanIpAddr() end
udp:settimeout(0)
udp:setsockname(svcAddr, svcPort)

print("Beginning server loop ["..svcAddr..":"..svcPort.."] ...")
while true do
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
    qType = bytes2Num(data:sub(byteIdx,byteIdx+1)) -- 1:A(ipv4)|28:AAAA(ipv6)|
    qClass = bytes2Num(data:sub(byteIdx+2,byteIdx+3)) -- normally the value 1 for Internet ('IN')

    print(srcAddrOrErrMsg..": query ["..qName.."]")

    if (qType==1) then
      cnrIpAddrV4 = getCustomNameResolution(qName, srcAddrOrErrMsg)
    print(cnrIpAddrV4)
      rspData = createDnsAnswerTypeA(data:sub(1,2), qName, cnrIpAddrV4, 60)
    else
      rspData = createDnsAnswer0(data:sub(1,2), qName, qType)
    end

    if printRawMsg then
      print(str2Hex(rspData))
      print(rspData)
    end

    udp:sendto(rspData, srcAddrOrErrMsg, srcPort)
  print("sent")

  elseif srcAddrOrErrMsg ~= 'timeout' then
    error("Unknown network error: "..tostring(srcAddrOrErrMsg))
  end
end
