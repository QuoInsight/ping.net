#!/bin/sh
if [[ "$1" =~ '^[0-9]+$' ]]; then
  maxTime=$1
else
  maxTime=5
fi
echo "$(curl -m $maxTime -N -w '%{speed_download}' --limit-rate 1g -o /dev/null 'https://speedtest2.u.com.my:8080/download?size=104857600' | sed 's/$/*8\/1048576\n/' | bc) Mbps"
