#!/bin/bash
export PATH=/usr/bin:/bin:/sbin:/usr/sbin
killall -9 MobileCydia
sleep 3
apt-get -y remove $1 2>/tmp/aptoutput 1>/dev/null
exitcode=$?
rm -rf /tmp/aptoutput &> /dev/null
exit $exitcode
