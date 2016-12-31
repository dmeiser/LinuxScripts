#!/bin/bash

# Usage:
# Intended to be used as a cron job with flock, which is a core Linux utility.
# I use it with the following, which will run every minute of every day:
# * * * * * flock -n /tmp/check.lock /path/to/check.sh

# This will find the first five hops, find rows that have IPs, take anything
# from hop 2 to 9 (eg - past my router and modem) then grab the IP address of the
# first hop outside our network. Modify for what suits your needs.
firsthop=`traceroute 8.8.8.8 -n -m 5 | grep -E "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | grep -m 1 -E "^\s?\b[3-9]{1,2}" | tr -s " " | cut -d" " -f3`

failures=0

# I have 0 faith that the firsthop script will always return due
# to my provider, so I'm using a fall back to OpenDNS primary.
if [ -z $firsthop ];
then
	firsthop="208.67.220.220"
fi

echo "First hop is: $firsthop"

# I am using 3 tests from 3 providers to see if it's an issue with
# the firsthop or multiple servers. Here's the servers I'm using:
# 	1. My first hop or OpenDNS primary
# 	2. Google Public DNS primary
# 	3. Dyn Public DNS primary
# I use IPs on the off chance that there's a DNS issue.
tests=($firsthop "8.8.8.8" "216.146.35.35")

for test in "${tests[@]}";
do
	echo "Testing $test"
	ping -c 1 $test

	if [ $? -ne 0 ];
	then
		let "failures += 1"
	fi
done

if [ $failures -eq 3 ];
then
  # If /tmp/lastfailure doesn't exist, create it.
	if ! [ -f /tmp/lastfailure ];
	then
		date +%s --date "7 hours ago" > /tmp/lastfailure
	fi

	# Get last failure time and find out how many minutes ago it was
	# if it was less than 30 minutes ago, we probably have something
	# else going on. Restart every 30 minutes until something happens.
	let lastfailure=" (`date +%s`-`tail -n1 /tmp/lastfailure`)/60 "
	if [ $lastfailure -ge 30 ];
	then
		date +%s >> /tmp/lastfailure
		echo "Last failure was $lastfailure minutes ago. Restarting."
		# Turn the HS100 off, wait 30 seconds, then turn it back on
		# Wait 10 minutes because it takes a while for my internet
		# to come back up.
		# Shout out to ggeorgovassilis for the hs100.sh scripts:
		# https://github.com/ggeorgovassilis/linuxscripts/blob/master/tp-link-hs100-smartplug/hs100.sh
		./hs100.sh 192.168.1.60 9999 off
		sleep 10s
		./hs100.sh 192.168.1.60 9999 on
	else
		echo "Last failure was $lastfailure minutes ago. Not restarting."
	fi
else
	if [ $failures -ne 0 ];
	then
		echo "There were $failures failures. There's an issue, but the internet isn't down."
	else
		echo "There are no issues."
	fi
fi
