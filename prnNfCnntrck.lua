#!/usr/bin/env lua
-- http://openwrt.lan/cgi-bin/luci/admin/status/realtime/connections
--[[
  ==luci-mod-status==
  .\luci-master\modules\luci-mod-status
    .\root\usr\share\luci\menu.d
      .\luci-mod-status.json
      "admin/status/realtime": {
        "title": "Realtime Graphs",
        "order": 7,
        "action": {
          "type": "alias",
          "path": "admin/status/realtime/load"
        },
        "depends": {
          "acl": [ "luci-mod-status-realtime" ]
        }
      },
      "admin/status/realtime/connections": {
        "title": "Connections",
        "order": 4,
        "action": {
          "type": "view",
          "path": "status/connections"
        }
      }
  ==RealtimeStats==
  .\luci-master\modules\luci-mod-status
    .\htdocs\luci-static\resources\view\status
      .\connections.js
      ==> .\luci-base\htdocs\luci-static\resources\rpc.js
      callLuciConntrackList ==> [luci]getConntrackList ==> `ubus -v list luci`
                            ==> ubus call luci getConntrackList
        updateConntrack: function(conn) {
          callNetworkRrdnsLookup ==> [network.rrdns]lookup ==> `ubus -v list network.rrdns`
                                 ==> ubus call network.rrdns lookup '{"addrs":["127.0.0.1","8.8.8.8"],"timeout":"250"}'
      callLuciRealtimeStats('conntrack') ==> [luci]getRealtimeStats for plotting the graph
  .\luci-master\modules\luci-base
    .\root\usr\libexec\rpcd\luci
      .\luci
      #!/usr/bin/env lua
      getConntrackList ==> luci.sys.net.conntrack ==> 
      getRealtimeStats ==> luci-bwc -c  <== data for plotting the graph
    .\luasrc
      .\sys.lua
      module "luci.sys"
      function net.conntrack(callback) ==> "/proc/net/nf_conntrack"

--]]
-- vi /usr/lib/lua/luci/sys.lua

gIpAddrs = {}

function _exeCmd(cmdln)
  local file = assert(io.popen(cmdln, 'r'))
  local output = file:read('*all')
  file:close()
  output = string.gsub(output, "^%s*(.-)%s*$", "%1") --trim
  return output
end

function getLocalhostAddrs()
  local hostname = (require "luci.sys").hostname() -- os.getenv("HOSTNAME") -- not working
  local cmdln = "ubus call network.interface dump"
  local output = _exeCmd(cmdln)
  local jsonc = require "luci.jsonc"
  local ifcfg = jsonc.parse(output)
  local ipAddrs = {}
  for _,ifc in pairs(ifcfg["interface"]) do
    --print( ifc["interface"].."/"..tostring(ifc["device"]).."/" )
    if ifc["ipv4-address"] ~= nil and #ifc["ipv4-address"] > 0 then
      --print( ifc["ipv4-address"][1]["address"] )
      ipAddrs[ ifc["ipv4-address"][1]["address"] ] = hostname.."."..tostring(ifc["device"])
    end
    if ifc["ipv6-address"] ~= nil and #ifc["ipv6-address"] > 0 then
      --print( ifc["ipv6-address"][1]["address"] )
      ipAddrs[ ifc["ipv6-address"][1]["address"] ] = hostname.."."..tostring(ifc["device"])
    end
  end
  return ipAddrs
  --[[
  local cmdln = "ifconfig | grep 'inet addr:'" -- | "ip -4 addr show"
  local output = _exeCmd(cmdln)
  for addr in string.gmatch(output, 'inet addr:([^ ]+)') do
    print(addr)
  end
 --]]
end

function rrdnsLookup(ipAddrs)
  local cmdln = "ubus call network.rrdns lookup '" .. '{"addrs":["'
  for ip,_ in pairs(ipAddrs) do
    cmdln = cmdln .. ip .. '","'
  end
  cmdln = cmdln .. '"],"timeout":"5000","limit":"1000"}' .. "'"
  --print(cmdln)
  local output = _exeCmd(cmdln)
  --print(output)
  local jsonc = require "luci.jsonc"
  local lookup = jsonc.parse(output)
  local localhostAddrs = getLocalhostAddrs()
  for ip,_ in pairs(ipAddrs) do
    if lookup[ip] == nil then
      if localhostAddrs[ip] == nil then
        lookup[ip] = "-"
      else
        lookup[ip] = localhostAddrs[ip]
      end
    end
  end
  return lookup
end

--gIpAddrs["127.0.0.1"] = 1 ; gIpAddrs = rrdnsLookup(gIpAddrs)
--for k,v in pairs(gIpAddrs) do print(v.." ["..k.."]"); end
--os.exit()

function parseConntrack(line)
  local i = 0
  local c = {bytes=0,packets=0,timeout=0,sport="",dport=""}
  local key, val
  for val in string.gmatch(line, '([^ ]+)') do
    i = i + 1
    --print("#"..i..": "..s)
    --[[
      #1: ipv4 | ipv6 ["layer3"]
      #2: network layer protocol number.
      #3: tcp | udp 
      #4: transmission layer protocol number.
      #5: seconds until the entry is invalidated.
                       [udp] [tcp]
      connection state  -     #6     ESTABLISHED
      src=              #6    #7
      dst=              #7    #8
      sport=            #8    #9
      dport=            #9    #10
      packets=          #10
    --]]
    key = nil
    if i == 1 then
      key = "layer3" -- ipv4 | ipv6
    elseif i == 3 then
      key = "layer4" -- tcp | udp
    elseif i == 5 then
      key = "timeout"
    elseif i > 5 then
      key, val = val:match("(%w+)=(%S+)")
      --if val:startsWith('bytes') then .... end
      if key == "src" or key == "dst" or key == "sport" or key == "dport" then
        if c[key] ~= nil and c[key] ~= "" then
          key = nil
        elseif key == "src" or key == "dst" then
          gIpAddrs[val] = 1
        end
      end
    end
    if key ~= nil and key ~= "" then 
      if key == "bytes" or key == "packets" then
        c[key] = c[key] + tonumber(val,10)
      else
        c[key] = val
      end
    end
  end
  return c
end

conntrack = {}
f1 = io.open("/proc/net/nf_conntrack","r")
repeat
  line = f1:read()
  if line==nil then break end
  table.insert(conntrack, parseConntrack(line))
until (line==nil)
io.close(f1)

table.sort(conntrack, function(a, b)
  return a["bytes"] > b["bytes"]
end)

gIpAddrs = rrdnsLookup(gIpAddrs)
for _,c in pairs(conntrack) do
  if c["bytes"] > 524288000 then
    c["bytes"] = string.format("%.2f GB", c["bytes"]/1073741824)
  elseif c["bytes"] > 204800 then
    c["bytes"] = string.format("%.2f MB", c["bytes"]/1048576)
  elseif c["bytes"] > 1024 then
    c["bytes"] = string.format("%.2f KB", c["bytes"]/1024)
  else
    c["bytes"] = string.format("%d bytes", c["bytes"])
  end
  print(
    tostring(gIpAddrs[c["src"]]).." "..c["src"]..":"..c["sport"].."\t"
     ..c["dst"]..":"..c["dport"].."\t"..c["layer4"].."\t"
      ..c["bytes"].." "..tostring(gIpAddrs[c["dst"]])
  )
  --break
end
