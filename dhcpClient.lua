
-- https://github.com/playma/simple_dhcp/blob/master/dhcp_client.py

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

------------------------------------------------------------------------

local function charAt(s, idx)
  return string.sub(s,idx,idx)
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
    bAddr = string.rep("0",32)
  elseif (#bAddr==1) then
    bAddr = string.rep("0",32) .. bAddr
  elseif ( not( #bAddr==32 and string.match(string.rep("%x",32)) ) ) then
    bAddr = string.rep("0",32)
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

local function _exeCmd(cmdln)
  local file = assert(io.popen(cmdln, 'r'))
  local output = file:read('*all')
  file:close()
  output = string.gsub(output, "^%s*(.-)%s*$", "%1") --trim
  return output
end

local function getMacAddrBytes()
  -- https://www.digitalcitizen.life/4-ways-learn-mac-address-windows-7-windows-81/
  local cmdln = "wmic nic where NetConnectionID='Wi-Fi' get MACAddress"
  local output = _exeCmd(cmdln)
  for line in output:gmatch("[^\n]+") do
    if line:match("%w%w:%w%w:%w%w:%w%w:%w%w:%w%w") then
      return hex2Str(line:gsub(":",""))
    end
  end
  return string.rep(string.char(0),12)
end

------------------------------------------------------------------------

local function printDhcpMsg(strMsg)
  dhcpMsgTypes = {
    [1]='DISCOVER', [2]='OFFER', [3]='REQUEST', [4]='DECLINE',
    [5]='ACK', [6]='NACK', [7]='RELEASE', [8]='INFORM'
  }
  msgTyp = charAt(strMsg,1):byte()
  hwAddrSz = charAt(strMsg,3):byte()
  print("dhcpType: "..dhcpMsgTypes[msgTyp])
  print("clientIpAddr: "..ipAddrBytes2Str(strMsg:sub(13,16)))
  print("yourIpAddr: "..ipAddrBytes2Str(strMsg:sub(17,20)))
  print("serverIpAddr: "..ipAddrBytes2Str(strMsg:sub(21,24)))
  print("gatewayIpAddr: "..ipAddrBytes2Str(strMsg:sub(25,28)))
  print("clientHwAddr: "..ipAddrBytes2Str(strMsg:sub(29,29+hwAddrSz-1)))
  print("magicCookie: "..str2Hex(strMsg:sub(237,240)))
  print("msgDetails: "..str2Hex(strMsg:sub(241,243)))
  optTypes = { -- https://en.wikipedia.org/wiki/Dynamic_Host_Configuration_Protocol#Options
    [0]="Pad", [1]="Subnet mask", [2]="Time offset", [3]="Router", [4]="Time server", [5]="Name server", [6]="Domain name server", [7]="Log server", [8]="Cookie server", [9]="LPR Server", [10]="Impress server", [11]="Resource location server", [12]="Host name", [13]="Boot file size", [14]="Merit dump file", [15]="Domain name", [16]="Swap server", [17]="Root path", [18]="Extensions path", [19]="IP forwarding enable/disable", [20]="Non-local source routing enable/disable", [21]="Policy filter", [22]="Maximum datagram reassembly size", [23]="Default IP time-to-live", [24]="Path MTU aging timeout", [25]="Path MTU plateau table", [26]="Interface MTU", [27]="All subnets are local", [28]="Broadcast address", [29]="Perform mask discovery", [30]="Mask supplier", [31]="Perform router discovery", [32]="Router solicitation address", [33]="Static route", [34]="Trailer encapsulation option", [35]="ARP cache timeout", [36]="Ethernet encapsulation", [37]="TCP default TTL", [38]="TCP keepalive interval", [39]="TCP keepalive garbage", [40]="Network information service domain", [41]="Network information servers", [42]="Network Time Protocol (NTP) servers", [43]="Vendor-specific information", [44]="NetBIOS over TCP/IP name server", [45]="NetBIOS over TCP/IP datagram Distribution Server", [46]="NetBIOS over TCP/IP node type", [47]="NetBIOS over TCP/IP scope", [48]="X Window System font server", [49]="X Window System display manager", [50]="Requested IP address", [51]="IP address lease time", [52]="Option overload", [53]="DHCP message type", [54]="Server identifier", [55]="Parameter request list", [56]="Message", [57]="Maximum DHCP message size", [58]="Renewal (T1) time value", [59]="Rebinding (T2) time value", [60]="Vendor class identifier", [61]="Client-identifier", [64]="Network Information Service+ domain", [65]="Network Information Service+ servers", [66]="TFTP server name", [67]="Bootfile name", [68]="Mobile IP home agent", [69]="Simple Mail Transfer Protocol (SMTP) server", [70]="Post Office Protocol (POP3) server", [71]="Network News Transfer Protocol (NNTP) server", [72]="Default World Wide Web (WWW) server", [73]="Default Finger protocol server", [74]="Default Internet Relay Chat (IRC) server", [75]="StreetTalk server", [76]="StreetTalk Directory Assistance (STDA) server", [255]="End" 
  }; optTypIpv4 = {
    [1]=1, [3]=1, [4]=1, [5]=1, [6]=1, [7]=1, [8]=1, [9]=1, [10]=1, [11]=1, [16]=1, [28]=1, [32]=1, [41]=1, [42]=1, [44]=1, [45]=1, [48]=1, [49]=1, [50]=1, [54]=1, [65]=1, [68]=1, [69]=1, [70]=1, [71]=1, [72]=1, [73]=1, [74]=1, [75]=1, [76]=1 
  }
  idx = 244
  while idx < #strMsg do
    optTyp = charAt(strMsg,idx):byte()
    optSz = charAt(strMsg,idx+1):byte()
    optData = ""
    local idx1 = idx + 2
    local idx2 = idx1 + optSz-1
    if optTypIpv4[optTyp]==1 then
      while idx1 < idx2 do
        local idx12 = idx1 + 3
        if #optData > 0 then optData=optData.." , " end
        optData = optData .. ipAddrBytes2Str(strMsg:sub(idx1,idx12))
        idx1 = idx12 + 1
      end
    else
      optData = str2Hex(strMsg:sub(idx1,idx2))
    end
    print("#"..optTyp.."#"..optTypes[optTyp].."#"..optSz.." : ["..optData.."]")
    idx = idx2 + 1
  end
end
------------------------------------------------------------------------

data = hex2Str(
    "020106003903f32600000000".."00000000".."c0a8c06a".."c0a8c001".."00000000"
  .."34e12d960ae600000000000000000000"..string.rep(string.char(0),192)
  .."63825363350102".."3604c0a8c001330400001c203a0400000e103b040000189c0104ffffff001c04c0a8c0ff0608c0a8c001c0a8c0010304c0a8c001"
  .."ff00000000"
)

--printDhcpMsg(data); os.exit()

macAddrBytes = getMacAddrBytes()
print("\nmacAddr: "..str2Hex(macAddrBytes))

print("Start DHCP client ...")

local socket = require("socket")
local udp = socket.udp()

local dhcpDiscover = hex2Str("0101")..string.char(string.len(macAddrBytes))
  ..string.char(0)..hex2Str("3903F326")..hex2Str("00000000")
  ..ipAddrString2Bytes("0.0.0.0") -- CIADDR (Client ipAddr) -- as reported by client
  ..ipAddrString2Bytes("0.0.0.0") -- YIADDR (Your ipAddr) -- as captured by the server
  ..ipAddrString2Bytes("0.0.0.0") -- SIADDR (Server ipAddr)
  ..ipAddrString2Bytes("0.0.0.0") -- GIADDR (Gateway ipAddr)
  ..macAddrBytes..string.rep(string.char(0),10) -- CHADDR (CientHardware macAddr)
  ..string.rep(string.char(0),192) -- overflow space for additional options; BOOTP legacy.
  ..hex2Str("63825363") -- Magic cookie
  ..hex2Str("350101") -- DHCPDISCOVER message
  --..hex2Str("3204")..ipAddrString2Bytes("192.168.192.1") -- preferred server
  --..hex2Str("370401030f06") -- request 4 more items: 1nm,3gw,15dn,6dns
  ..string.char(255) -- endmark

udp:settimeout(2)
udp:setoption('broadcast', true)
udp:setoption('dontroute', true)
udp:setsockname("0.0.0.0", 68) -- srcClientPort
udp:sendto(dhcpDiscover, "255.255.255.255", 67) -- dstServerPort
print("dhcpDiscover sent")

data, srcAddrOrErrMsg, srcPort = udp:receivefrom()
if data then
  print(("\nudp:receivefrom %s:%s (%d bytes)"):format(
    srcAddrOrErrMsg, srcPort, string.len(data)
  ))
  print(str2Hex(data))
  printDhcpMsg(data)
elseif srcAddrOrErrMsg ~= 'timeout' then
  error("error: "..tostring(srcAddrOrErrMsg))
end

print("OK")
