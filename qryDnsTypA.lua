#!/usr/bin/env lua

local dnsServer = "8.8.8.8"
local dnsPort = 53
local qType = 1
local hostName = ""

if #arg < 1 then
  print("\nUsage: "..arg[0].." <HOST> [QRY_TYPE [DNS_SERVER [DNS_PORT]]]\n")
  os.exit()
end
if #arg>3 then dnsPort=arg[4] end
if #arg>2 then dnsServer=arg[3] end
if #arg>1 then qType=arg[2] end
hostName = arg[1]

if qType=="A" then qType=1 end
if qType=="AAAA" then qType=28 end
qType = tonumber(qType)

--print(hostName.."["..qType.."]".."@"..dnsServer..":"..dnsPort)

------------------------------------------------------------------------

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

------------------------------------------------------------------------

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

local function getEndOfNameData(rawData, startIdx)
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

------------------------------------------------------------------------

local socket = require("socket")

local function qryDns(qName, qType, srv, prt, sck)
  local function getRnd2Bytes()
    -- max value of 2 bytes == 65535 --
    math.randomseed(os.time())
    local t = socket.gettime() -- print(os.time());  print(t);  print(t%60)
    return string.char(math.floor(0.5+((t%10)/10*255)))
      .. string.char(math.random(0, 255))
  end
  local function formatNameData(qName)
    local qData = ""
    for n1,_ in string.gmatch(qName..'.', "([^%.]+)%.") do
      qData = qData .. string.char(#n1) .. n1
    end
    --print(str2Hex(qData))
    return qData
  end
  local function getAnswer(msgData, qType)
    --msgHdrHex = str2Hex(msgData:sub(1,12)) ; print(msgHdrHex)
    -- ID:2bytes; Flags+OpCode+RespCode:2bytes; RecordsCount:4*2bytes
    local byte4 = charAt2Bits(msgData,4)
    local rspCode = tonumber(byte4:sub(5,8), 2)
    local qCount = bytes2Num(msgData:sub(5,6))
    local aCount = bytes2Num(msgData:sub(7,8))
    --print("aCount: "..aCount)
    local byteIdx = 13
    for count = 1,qCount,1 do
      local endOfNameData = getEndOfNameData(msgData, byteIdx)
      byteIdx = endOfNameData+1+4 -- end of q1
    end
    if (qCount>=1 and aCount > 0) then
      for count = 1,aCount,1 do
        local endOfNameData = getEndOfNameData(msgData, byteIdx)
        byteIdx = endOfNameData+1 -- end of a1
        local aType = bytes2Num(string.sub(msgData,byteIdx,byteIdx+1)) -- 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
        local aClass = bytes2Num(string.sub(msgData,byteIdx+2,byteIdx+3)) -- normally the value 1 for Internet ('IN')
        --print("aType:"..aType.." qType:"..qType)
        byteIdx = byteIdx+8 --
        local aSize = bytes2Num(string.sub(msgData,byteIdx,byteIdx+1))
        byteIdx = byteIdx+2 --
        if (aType==qType) then
          local aData = msgData:sub(byteIdx,byteIdx+aSize-1)
          if (aType==1 or aType==28) then
            return ipAddrBytes2Str(aData)
          else
            return str2Hex(aData)
          end
        end
        byteIdx = byteIdx+aSize
      end
    end
    if (qType==1) then
      return "0.0.0.0"
    elseif (qType==28) then
      return "::"
    else
      return "#"
    end
  end
  sck:settimeout(5);  sck:sendto(
    getRnd2Bytes() .. hex2Str("01000001000000000000")
      .. formatNameData(qName) .. hex2Str("0000")
        .. string.char(qType) .. hex2Str("0001"),
          srv, prt
  )
  local rspData,srcAddrOrErrMsg,srcPort = sck:receivefrom()
  if rspData then
    --print(str2Hex(rspData));  --print(rspData)
    return getAnswer(rspData, qType)
  else
    error("Error: "..tostring(srcAddrOrErrMsg))
  end
end

print( qryDns(hostName, qType, dnsServer, dnsPort, socket.udp()) )
