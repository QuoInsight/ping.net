#!/bin/sh
echoCgiPrmVal() {
  echo "&$1" | grep "&$2=" | sed -E "s/.*&$2=([^&]*).*/\1/"
}

POST_STRING=$(cat) # opt=`echo "$POST_STRING" | sed 's/opt=//'`
opt=`echoCgiPrmVal "$POST_STRING" "opt"`
[ -z "$opt" ] || ip=`echoCgiPrmVal "$POST_STRING" "ip"`

cat <<EOT
content-type: text/html

<html><head><meta http-equiv=cache-control content=no-cache/><meta http-equiv=expires content=0/><meta http-equiv=pragma<form method=post>
<select name=opt>
  <option value=''>status
  <option value=off>control off
  <option value=on>control on
  <option value=block>block all
  <option value=unblock>unblock
  <option value=cronchk>reset
</select>
<input type=submit>
[ <A href='/cgi-bin/luci/command/cfg0f9944s/-'>tp-link</A> ]
</form>                                                                                                                 <form method=post>                                                                                                      <input type=text name=ip size=15 value="$ip">                                                                           <input type=submit name=opt value=block>                                                                                <input type=submit name=opt value=unblock>                                                                              <hr>                                                                                                                    $POST_STRING [$opt][$ip]                                                                                                </center><pre>                                                                                                          EOT                                                                                                                                                                                                                                             if [ -z "$opt" ]; then                                                                                                    /root/prctl.iptab; /root/prctl.dns; /root/prnNfCnntrck.lua|head                                                       elif [ "$opt" == "block" ] || [ "$opt" == "unblock"  ]; then
  if [ -z "$ip" ]; then
    /root/prctl.iptab "192.168.175.188/32 192.168.175.192/32" "$opt"
  else
    /root/prctl.iptab "$ip/32" "$opt" # "-d"
  fi
else
  /root/parentalCtrl "$opt"
fi

cat <<EOT
</pre></body></html>
EOT

