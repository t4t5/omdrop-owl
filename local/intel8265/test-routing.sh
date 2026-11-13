#!/bin/sh
# Run as root. All network changes stay in temporary network namespaces.
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TASK_HELPER="$TASK_ROOT/local/intel8265/ensure-link-local-route.py"

unshare --net /bin/sh -eu -c '
    ip -6 rule add priority 9000 unreachable
    python3 "$1"
    TASK_FIRST=$(ip -6 -j rule show)
    python3 "$1"
    [ "$TASK_FIRST" = "$(ip -6 -j rule show)" ]
    ip link add awdl0 type dummy
    ip link set awdl0 up
    ip -6 addr add fe80::1/64 dev awdl0 nodad
    ip link add other0 type dummy
    ip link set other0 up
    ip -6 addr add fe80::2/64 dev other0 nodad
    ip -6 route get fe80::abcd oif awdl0
    if ip -6 route get fe80::abcd oif other0 2>/dev/null; then exit 1; fi
    if ip -6 route get 2001:db8::1 oif awdl0 2>/dev/null; then exit 1; fi
    echo "PASS: local AirDrop traffic works; other interfaces and global IPv6 stay blocked; installation is idempotent."
' test-routing "$TASK_HELPER"

unshare --net /bin/sh -eu -c '
    ip -6 rule add priority 8990 unreachable
    TASK_BEFORE=$(ip -6 -j rule show)
    if python3 "$1"; then exit 1; fi
    [ "$TASK_BEFORE" = "$(ip -6 -j rule show)" ]
    echo "PASS: an occupied priority is refused without changing existing rules."
' test-routing "$TASK_HELPER"
