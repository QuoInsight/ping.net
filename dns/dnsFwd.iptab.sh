#!/bin/sh
[ -z "$1" ] && {
  iptables -t nat -S | grep "PREROUTING.*--dport 53"
  echo ""
  echo "usage: $0 '<macAddrs>' [enable|disable [custDns:port]]"
  echo ""
  exit
}
macAddrs="$1"
action="$2"
custDns="$3"

fwdDns() {
  local lanAddr=`ifconfig br-lan | grep -F 'inet addr:' | sed -r 's/^\s*inet addr:([^ ]+).*/\1/'`
  local macAddr="$1";(echo "$macAddr"|grep -q ':')||macAddr=`echo "$1"|sed 's/\(..\)/\1:/g'|sed s'/:$/\1/'`
  local action=${2:-enable}; local custDns=${3-$lanAddr:50053}; macAddr=`echo "$macAddr"|awk '{print tolower($0)}'`
  local iptab="PREROUTING -p udp -m mac --mac-source $macAddr -m udp --dport 53 -j DNAT --to-destination $custDns"

  # for some reason, it is not working correctly with '-j REDIRECT --to-port 50053' or '-j DNAT --to-destination 127.0.0.1:50053'
  # somehow the DNS traffic is not routed/redirected to [./dnsRslv.lua 50053 127.0.0.1], but works OK with lanAddr:50053

  if [ "$action" == "disable" ] || [ "$action" == "delete" ] || [ "$action" == "off" ]; then
    cmdln="iptables -t nat -D $iptab"
    echo "$cmdln";eval "$cmdln"
  elif ( iptables -t nat -S | grep -F "$iptab" ) ; then
    echo "skipped. rule exists"
  else
    cmdln="iptables -t nat -I $iptab"
    echo "$cmdln";eval "$cmdln"
    return 1
  fi
  return 0
}

fwdDns2() {
  local macAddrs="$1"
  local action="$2"
  local custDnsRslvr="$3"
  local returnCode=0
  for ipAddr in $macAddrs; do
    fwdDns $ipAddr $action $custDns || returnCode=1
  done
  return $returnCode
}

returnCode=0; fwdDns2 "$macAddrs" "$action" "$custDns" || returnCode=1 

exit $returnCode
