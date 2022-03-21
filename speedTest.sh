#!/bin/sh
#echo "$(curl -m 5 -N -w '%{speed_download}' --limit-rate 1g -o /dev/null 'https://speedtest2.u.com.my:8080/download?size=104857600' | sed 's/$/*8\/1048576\n/' | bc) Mbps"

if [[ "$1" =~ '^[0-9]+$' ]]; then
  maxTime=$1
  if [ "$2" != "" ]; then
    url=$2
  fi  
else
  maxTime=5
  if [ "$1" != "" ]; then 
    url=$1
  fi
fi
case "$url" in
  "tm") url='https://speedtest-northern.tm.com.my:8080/download?size=104857600' ;;
  "th") url='https://speedtest-hyi1.3bb.co.th.prod.hosts.ooklaserver.net:8080/download?size=104857600' ;;
  "u"|"") url='https://speedtest2.u.com.my:8080/download?size=104857600' ;;
esac
cmdln="curl -m $maxTime -N -w '%{speed_download}' --limit-rate 1g -o /dev/null '$url'"
echo "$(eval $cmdln | sed 's/$/*8\/1048576\n/' | bc) Mbps"
