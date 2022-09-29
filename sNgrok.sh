#!/bin/sh
l_hst=localhost
l_prt=22
n_prt=tcp
n_reg=ap
l_key=/etc/dropbear/dropbear_rsa_host_key
nohup=-f

[ -z "$1" ] || l_hst="$1"
[ -z "$2" ] || l_prt="$2"
[ -z "$3" ] || n_prt="$3"
[ -z "$4" ] || n_reg="$4"
[ -z "$5" ] || l_key="$5"

if [ "$n_prt" == "http" ]; then
  n_prt="http --scheme http" ## "http -bind-tls=false"
elif [ "$n_prt" == "https" ]; then
  n_prt="http --scheme https" ## "http -bind-tls=true"
fi

log="/tmp/sNgrok.${l_hst}.${l_prt}.log"
cmdln="ssh -i ${l_key} ${nohup} -y -K 30 -R 0:${l_hst}:${l_prt} tunnel.${n_reg}.ngrok.com ${n_prt}"
echo "$cmdln"

psOutput=$(ps -w | grep 'ssh ' | grep -v 'grep')
IFS=$'\n'
for line in $psOutput ; do
  PID=`echo "$line" | sed -e 's/^ *\([0-9]\+\).*/\1/'` # sed -r 's/^\s*([0-9]+).*/\1/'
  cmdln1=`cat /proc/$PID/cmdline | xargs -0 echo`
  if [ "$cmdln1" == "$cmdln" ]; then
    echo "**found** PID: $PID"
    exit
  fi
done

eval "$cmdln" | while IFS= read -r line; do
  echo ">> $line"
  n_endp=$(echo "$line" | grep '^Forwarding' | sed 's/^[^ ]\+ \+//')
  if [ ! -z "$n_endp" ]; then
    if [ "$l_prt" == "22" ] && [ "$n_prt" == "tcp" ]; then
      n_endp=$(echo "$n_endp" | sed 's/^tcp:\/\///')
      r_hst=$(echo ${n_endp%:*})
      r_prt=$(echo ${n_endp#*:})
      n_endp="ssh root@${r_hst} -p ${r_prt}"
    fi
    date | tee -a "$log"
    echo "$cmdln" >> "$log"
    echo "** endpoint: $n_endp" | tee -a "$log"
    [ "$nohup" == "-f" ] && exit
  fi
done
