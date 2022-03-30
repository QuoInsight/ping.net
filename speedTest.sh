#!/bin/sh

# echo "$(curl -m 5 -N -w '%{speed_download}' --limit-rate 1g -o /dev/null 'https://speedtest2.u.com.my:8080/download?size=104857600' | sed 's/$/*8\/1048576\n/' | bc) Mbps"
# wget --no-cache -o /dev/stdout -O /dev/null https://file-examples-com.github.io/uploads/2017/10/file_example_JPG_1MB.jpg
# wget --progress=dot:mega --no-cache -o /dev/stdout --output-document=/dev/null \
# 'https://speedtest-sv3.kpnhospital.com.prod.hosts.ooklaserver.net:8080/download?size=10485760'

## curl shows the speed in bytes/second instead of bits/second !!!
## 1Mbps==128K | 3Mbps==384K | 5Mbps==640K | 10Mbps==1.25M/1280K

#if [[ "$1" =~ '^[0-9]+$' ]]; then  ## this works for bash/ash only, [[]] not supported by sh/bourne shell
if (echo "$1" | grep -q -E '^[0-9]+$'); then  ## this works for all bash/ash/sh
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
  "kris") url='http://speedtest2.mykris.net:8080/download?size=104857600' ;;
  "u"|"") url='https://speedtest2.u.com.my:8080/download?size=104857600' ;;
  "-")  ## more URL at http://c.speedtest.net/speedtest-servers-static.php
    url=`curl -s http://c.speedtest.net/speedtest-servers-static.php | grep -E -m 1 'host="(\S+)"' | sed -n -r 's/^.+host="(\S+)".*/\1/p'`
    url="http://$url/download?size=104857600"
  ;;
esac
cmdln="curl -m $maxTime -N -w '%{speed_download}' --limit-rate 1g -o /dev/null '$url'"
echo $cmdln
echo "$(eval $cmdln | sed 's/$/*8\/1048576\n/' | bc) Mbps"
