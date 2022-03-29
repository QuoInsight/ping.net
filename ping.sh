#!/bin/sh
TARGET="8.8.8.8"
PING="ping $TARGET -W 1 -c 1 -q 2>&1 | tail -1"
LOG=/tmp/ping.log

chkResult() {
  r=1; (echo "$1" | grep -e '100% packet loss' -e 'Invalid' -e 'address') && r=0
  #echo "1: $1";  echo "r: $r"
  return $r
}

date | tee -a $LOG
result=`eval $PING`
chkResult "$result"; r0=$?
echo "$result" | tee -a $LOG
while true; do
  sleep 1
  result=`eval $PING`
  chkResult "$result"; r1=$?
  if [ $r1 != $r0 ]; then  ## this works for all bash/ash/sh
    date | tee -a $LOG
    echo "$result" | tee -a $LOG
  else
    echo "$result"
  fi
  r0=$r1
done
