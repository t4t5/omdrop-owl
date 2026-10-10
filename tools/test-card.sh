#!/bin/bash
# Test omdrop-owl on this computer's Wi-Fi card: the steps of README, "Adding
# your card", with a report directory to attach to the pull request or issue.
#
#   sudo tools/test-card.sh [--lib DIR] [--watch SECONDS] [--file FILE]
#
#   --lib     the helpers to test: default /usr/lib/omdrop when installed,
#             else build/lib (tools/build-owl.sh and tools/stage.sh)
#   --watch   how long to watch Wi-Fi after teardown (default 300)
#   --file    what to send to the phone (default: a generated test image)
#
# It runs probe, opens a window, waits for the phone, sends it a file, closes
# the window and then watches the station for the drop the MT7925 shows
# (README, "Known issues"). Ctrl-C at any point closes the window.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB= WATCH=300 FILE=
while [ $# -gt 0 ]; do
  case "$1" in
    --lib) LIB=$2; shift 2 ;;
    --watch) WATCH=$2; shift 2 ;;
    --file) FILE=$2; shift 2 ;;
    *) sed -n '2,15s/^# \{0,1\}//p' "$0"; exit 2 ;;
  esac
done
[ "$(id -u)" = 0 ] || { echo "run as root: sudo $0 $*"; exit 2; }
if [ -z "$LIB" ]; then
  if [ -x /usr/lib/omdrop/omdrop-discoverable ]; then LIB=/usr/lib/omdrop; else LIB=$ROOT/build/lib; fi
fi
H=$LIB/omdrop-discoverable
[ -x "$H" ] || { echo "no helper at $H: install the package, or run tools/build-owl.sh and tools/stage.sh"; exit 2; }
RUN=/run/omdrop-owl
CONF=/etc/omdrop

# The station and its driver, the same way the helper finds them.
STA=$(head -1 "$CONF/infra-iface" 2>/dev/null | tr -d '[:space:]')
if [ -z "$STA" ]; then
  for d in /sys/class/net/*/phy80211; do
    n=$(basename "$(dirname "$d")")
    [ "$n" = awdl0 ] || [ "$n" = mon0 ] && continue
    iw dev "$n" info 2>/dev/null | grep -q 'type managed' && { STA=$n; break; }
  done
fi
[ -n "$STA" ] || { echo "no managed Wi-Fi interface found"; exit 1; }
DRV=$(basename "$(readlink -f "/sys/class/net/$STA/device/driver")")

START=$(date +%s)
OUT=$PWD/owl-test-$DRV-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
exec > >(tee -a "$OUT/console.log") 2>&1
RESULTS=()
result() { RESULTS+=("$1: $2"); printf '  -> %s: %s\n' "$1" "$2"; }
step() { printf '\n== %s\n' "$*"; }
ask() {  # PROMPT -> y, n or s
  local a
  while true; do
    read -rp "$1 [y/n/s(kip)] " a < /dev/tty
    case "$a" in y|Y) echo y; return ;; n|N) echo n; return ;; s|S) echo s; return ;; esac
  done
}
yn() { case "$1" in y) echo yes ;; n) echo no ;; *) echo skipped ;; esac; }

# A ping log, from `ping -O`, as "<sent> <received> <longest gap in s>".
gaps() {
  awk 'match($0, /icmp_seq=[0-9]+/) { s = substr($0, RSTART + 9, RLENGTH - 9) + 0
                                        if (s > tx) tx = s; if (/bytes from/) ok[s] = 1 }
       /packets transmitted/ { tx = $1 }
       END { for (i = 1; i <= tx; i++) if (i in ok) { rx++; run = 0 } else if (++run > max) max = run
             printf "%d %d %d\n", tx, rx, max }' "$1"
}

OPEN=0 PINGER= WATCHER=
cleanup() {
  [ -n "$PINGER" ] && kill -INT "$PINGER" 2>/dev/null
  [ -n "$WATCHER" ] && kill "$WATCHER" 2>/dev/null
  if [ "$OPEN" = 1 ]; then echo; echo "closing the window"; "$H" stop >/dev/null 2>&1; OPEN=0; fi
}
collect() {
  cp "$RUN"/log "$OUT/helper.log" 2>/dev/null
  cp "$RUN"/owl.log "$RUN"/announce.log "$RUN"/profile "$OUT/" 2>/dev/null
  journalctl -k --since "@$START" --no-pager > "$OUT/kernel.log" 2>/dev/null
  {
    echo "omdrop-owl card test, $(date -Is)"
    echo "card: $(lspci -s "$(basename "$(readlink -f "/sys/class/net/$STA/device")")" 2>/dev/null | cut -d' ' -f2-)"
    echo "driver: $DRV, kernel $(uname -r), $(. /etc/os-release && echo "$PRETTY_NAME")"
    echo "profile: $(cat "$RUN/profile" 2>/dev/null)"
    printf '%s\n' "${RESULTS[@]}"
  } > "$OUT/summary.txt"
  [ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER": "$OUT"
}
trap 'cleanup; collect' EXIT
trap 'exit 130' INT TERM

step "System"
{
  uname -a
  . /etc/os-release && echo "$PRETTY_NAME"
  lspci -nnk 2>/dev/null | grep -iA3 'network\|wireless'
  command -v ethtool >/dev/null && ethtool -i "$STA"
  iw dev "$STA" link
  iw phy "$(basename "$(readlink -f "/sys/class/net/$STA/phy80211")")" info
} > "$OUT/system.txt" 2>&1
echo "station $STA, driver $DRV, helpers in $LIB"
echo "report: $OUT"

step "Probe"
P=$("$H" probe)
echo "$P"
if echo "$P" | grep -q allow-untested; then
  if [ "$(ask "Opt in to running on an untested card ($CONF/allow-untested)?")" = y ]; then
    mkdir -p "$CONF" && echo 1 > "$CONF/allow-untested"
    P=$("$H" probe)
    echo "$P"
  fi
fi
[ "$P" = ready ] || { result probe "not ready"; exit 1; }
result probe ready

GW=$(ip -4 route show default dev "$STA" | awk '{print $3; exit}')
[ -n "$GW" ] || { result wifi "no default route on $STA"; exit 1; }

step "Baseline: ping $GW for 10 s"
ping -O -i 1 -c 10 -W 1 -I "$STA" "$GW" > "$OUT/ping-baseline.log" 2>&1
read -r tx rx gap <<< "$(gaps "$OUT/ping-baseline.log")"
result baseline "$rx/$tx replies"

step "Start"
t0=$(date +%s%N)
"$H" start 0
rc=$?
dt=$(( ($(date +%s%N) - t0) / 1000000 ))
OPEN=1
if [ "$rc" != 0 ]; then
  result start "exit $rc after ${dt} ms: $(tail -1 "$RUN/log" 2>/dev/null)"
  exit 1
fi
result start "ok in ${dt} ms"
ip -br link show dev awdl0; ip -br link show dev mon0
ping -D -O -i 1 -W 1 -I "$STA" "$GW" > "$OUT/ping-window.log" 2>&1 &
PINGER=$!
while sleep 2; do echo "$(date +%T) $("$H" status --json)"; done > "$OUT/status.log" 2>&1 &
WATCHER=$!

step "Find the phone"
cat <<'EOF'
On the iPhone: Control Center > AirDrop > Everyone for 10 Minutes. Then open
the share sheet on a photo and keep the screen on.
EOF
peers=
for i in $(seq 90); do
  peers=$("$H" peers 2>/dev/null)
  [ -n "$peers" ] && break
  printf '\r  waiting for an AWDL peer... %2d s' $(( i * 2 ))
  sleep 2
done
echo
if [ -n "$peers" ]; then
  echo "$peers"
  result "phone heard (OWL synced)" yes
else
  result "phone heard (OWL synced)" "no, in 180 s"
fi

# The phone lists this computer only once something answers its /Discover,
# which is omdrop's receiver: without omdrop, neither question can pass.
if command -v omdrop >/dev/null; then
  a=$(ask "Does this computer show up in the iPhone's AirDrop share sheet?")
  result "shown on the phone" "$(yn "$a")"
  a=$(ask "Send a photo from the iPhone to this computer. Did it arrive?")
  result "phone -> computer" "$(yn "$a")"
else
  result "phone -> computer" "skipped (omdrop isn't installed, so nothing receives)"
fi

if [ -n "$peers" ]; then
  if [ -z "$FILE" ]; then
    FILE=$OUT/omdrop-owl-test.png
    python3 - "$FILE" "$DRV" <<'EOF'
import sys, time
from PIL import Image, ImageDraw
im = Image.new("RGB", (800, 400), (40, 60, 90))
ImageDraw.Draw(im).text((40, 180), f"omdrop-owl test, {sys.argv[2]}, {time.ctime()}", fill="white")
im.save(sys.argv[1])
EOF
  fi
  step "Send $(basename "$FILE") to the phone"
  echo "Accept it on the iPhone when asked."
  t0=$(date +%s)
  "$LIB/send-to-peer" --wait 60 "$FILE"
  rc=$?
  a=$(ask "Did it arrive on the iPhone?")
  result "computer -> phone" "$(yn "$a") (send-to-peer exit $rc, $(( $(date +%s) - t0 )) s)"
fi

step "Stop"
kill "$WATCHER" 2>/dev/null; WATCHER=
kill -INT "$PINGER" 2>/dev/null; wait "$PINGER" 2>/dev/null; PINGER=
read -r tx rx gap <<< "$(gaps "$OUT/ping-window.log")"
result "Wi-Fi during the window" "$rx/$tx replies, longest gap ${gap} s"
t0=$(date +%s%N)
"$H" stop
rc=$?
OPEN=0
result stop "exit $rc in $(( ($(date +%s%N) - t0) / 1000000 )) ms"

step "Watch Wi-Fi for $WATCH s after teardown (Ctrl-C ends the watch early)"
# In the background, so Ctrl-C ends only the ping and its summary still lands.
ping -D -O -i 1 -W 1 -c "$WATCH" -I "$STA" "$GW" > "$OUT/ping-after.log" 2>&1 &
PINGER=$!
trap 'kill -INT "$PINGER" 2>/dev/null' INT
while kill -0 "$PINGER" 2>/dev/null; do
  read -r tx rx gap <<< "$(gaps "$OUT/ping-after.log")"
  printf '\r  %d s: %d missed, longest gap %d s ' "$(grep -c icmp_seq "$OUT/ping-after.log")" \
    "$(grep -c 'no answer' "$OUT/ping-after.log")" "$gap"
  sleep 1
done
wait "$PINGER" 2>/dev/null; PINGER=
trap 'exit 130' INT
echo
read -r tx rx gap <<< "$(gaps "$OUT/ping-after.log")"
result "Wi-Fi after teardown" "$rx/$tx replies, longest gap ${gap} s"
if [ "${gap:-0}" -ge 5 ]; then
  echo "  The station stopped receiving after teardown: keep \"reconnect yes\"."
fi

step "Summary"
printf '  %s\n' "${RESULTS[@]}"
echo
echo "Report in $OUT. Attach it when you open the pull request or issue."
