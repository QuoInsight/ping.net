#!/usr/bin/env lua

local function writelog(filepath, s)
  local f = io.open(filepath, "a")
  f:write(s.."\n");  f:close()
  return
end

local target = "8.8.8.8"
local count = 2
local threshold = 100
local log = "/tmp/ping.lua.log"
local ok = false

--if #arg < 1 then
  print("\nUsage: "..arg[0].." [target [count]]\n")
  --os.exit()
--end
if #arg>1 then count=arg[2] end
if #arg>0 then target=arg[1] end

--local ping = "ping " .. target .. " -W 1 -c " .. count .. " -q 2>&1 | tail -1"
local ping = "ping " .. target .. " -W 1 -c " .. count .. " -q"
print(ping)

while true do
  os.execute("sleep 1")
  local d = os.date('*t');
  local datetimestr = ("%04d-%02d-%02d %02d:%02d:%02d"):format(d.year,d.month,d.day,d.hour,d.min,d.sec)
  local f = io.popen(ping);  f:flush();
  local output = f:read("*a");  f:close(); -- print(output)
  --for line in f:lines() do
  --  print(line)
  --end
  --f:close()
  --while true do
  --  line = f:read()
  --  if line==nil then break end
  --  print(line)
  --end
  --f:close()
  if output==nil or output=="" then line="" else line=output:match("[^\r\n]*\n*$"):gsub('[\r\n]+','') end
  avg = line:match("/[%d%.]+/");  if avg==nil then avg=99999 else avg=tonumber(tostring(avg:gsub('/',''))) end
  output = datetimestr .. " [" .. target .. "] " .. avg .. " ms"
  print(output)
  if avg < threshold then
    if not ok then writelog(log,output) end
    ok = true
  else
    if ok then writelog(log,output) end
    ok = false
  end
end
