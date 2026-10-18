#!/bin/sh
# Install or update the stall watcher on the router (RUNBOOK "Stall watcher"): runs its test scenarios there
# first and installs only when they all pass. Usage: ./deploy-watcher.sh   (ROUTER=root@host to override)
set -e
cd "$(dirname "$0")/router"
R=${ROUTER:-root@192.168.3.1}
O="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=5"
tar cf - stall-watcher.uc stall-watcher.init tests | ssh $O "$R" '
	set -e
	rm -rf /tmp/sw && mkdir /tmp/sw && tar xf - -C /tmp/sw && cd /tmp/sw
	for f in tests/*.json; do ucode stall-watcher.uc test "$f" | tail -1; done | tee /tmp/sw/results
	if grep -q "^FAIL" /tmp/sw/results; then echo "a scenario failed: nothing installed"; exit 1; fi
	mkdir -p /usr/share/stall-watcher
	cp stall-watcher.uc /usr/share/stall-watcher/stall-watcher.uc
	cp stall-watcher.init /etc/init.d/stall-watcher && chmod +x /etc/init.d/stall-watcher
	/etc/init.d/stall-watcher enable
	/etc/init.d/stall-watcher restart
	sleep 2
	pidof ucode >/dev/null && echo "stall watcher running" || echo "stall watcher NOT running"
	logread -e stall-watcher | tail -2
	rm -rf /tmp/sw'
