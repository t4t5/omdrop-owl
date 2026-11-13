#!/bin/sh
# Capture only this test's AWDL discovery traffic. Run through pkexec.
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TASK_CAPTURE="$TASK_ROOT/target/intel8265-discovery-$(date -u +%Y%m%dT%H%M%SZ).pcap"
echo "Waiting for awdl0; capture: $TASK_CAPTURE"
TASK_ATTEMPTS=0
while [ ! -e /sys/class/net/awdl0 ]; do
    TASK_ATTEMPTS=$((TASK_ATTEMPTS + 1))
    [ "$TASK_ATTEMPTS" -lt 120 ] || { echo 'No AirDrop interface appeared.' >&2; exit 1; }
    sleep 0.25
done
TASK_STATUS=0
timeout --signal=INT 100 /usr/bin/tcpdump -i awdl0 -nn -U -s 0 \
    -w "$TASK_CAPTURE" 'ip6 and (udp port 5353 or tcp)' || TASK_STATUS=$?
chmod 0644 "$TASK_CAPTURE"
if [ "$TASK_STATUS" -eq 1 ] && [ ! -e /sys/class/net/awdl0 ] && [ -s "$TASK_CAPTURE" ]; then
    # The receiver's bounded test normally removes this interface first.
    exit 0
fi
case "$TASK_STATUS" in 0|124) exit 0 ;; *) exit "$TASK_STATUS" ;; esac
