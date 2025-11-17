#!/bin/sh -f
#date >> /tmp/cgi.log
## default "index file" not supported in cgi-bin
echo "Content-Type: text/html"
echo ""
echo "<h3>OK: $(date)</h3><pre>"
pwd ; echo -e "$0\n" ; cgidir=`dirname "$0"`
find "$cgidir" -maxdepth 1 -perm -111 ! -exec test -d {} \; -print0 | sort -z | xargs -0r ls -d | sed "s|$cgidir/||g" | sed -e 's|.*|<a href="&">&</a>|'
# if -xtype and -printf supported ... ! -xtype d -printf "<a href='%f'>%f</a><br>\0" | sort -z ## |tr '\0' '\n'|grep -v -e{'ngrok','rx'}
echo "</pre>"
exit 0
