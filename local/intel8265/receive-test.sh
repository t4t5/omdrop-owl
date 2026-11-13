#!/bin/bash
# Run from a local terminal: normal Wi-Fi is unavailable during this test.
set -u
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TASK_RADIO_LOG="$TASK_ROOT/target/intel8265-visible-radio.log"
TASK_RADIO_PID=

cleanup() {
    if [ -n "$TASK_RADIO_PID" ]; then
        kill -INT "$TASK_RADIO_PID" 2>/dev/null || true
        wait "$TASK_RADIO_PID" 2>/dev/null || true
        TASK_RADIO_PID=
    fi
}
trap cleanup EXIT

echo 'Owly: receive a test file from your Mac'
echo 'Normal Wi-Fi will disconnect during this 90-second test.'
echo 'On the Mac: select a small file, then Share > AirDrop > Moein Linux.'
echo 'When this terminal asks "accept? [y/N]", type y and press Enter.'
echo 'Press Ctrl+C to stop the receiver early.'
echo
/usr/bin/owly radio up --for 110 > "$TASK_RADIO_LOG" 2>&1 &
TASK_RADIO_PID=$!
TASK_ATTEMPTS=0
# The interface appears before the D-Bus lease becomes ready. Starting the
# receiver in that gap loses the radio's discovery announcement bursts.
while [ ! -e /sys/class/net/awdl0 ] || ! /usr/bin/owly radio peers >/dev/null 2>&1; do
    TASK_ATTEMPTS=$((TASK_ATTEMPTS + 1))
    if ! kill -0 "$TASK_RADIO_PID" 2>/dev/null || [ "$TASK_ATTEMPTS" -ge 60 ]; then
        cat "$TASK_RADIO_LOG"
        exit 1
    fi
    sleep 0.25
done
RUST_LOG=debug timeout --foreground --signal=INT 90 /usr/bin/owly receive \
    --name 'Moein Linux' --dir /home/moein/Downloads
cleanup
echo
echo 'Test ended. Normal Wi-Fi is reconnecting.'
read -r -p 'Press Enter to close this window.'
