#!/bin/bash
# Assemble build/lib, the runtime directory, laid out the way /usr/lib/omdrop
# will be: omdrop's CLI and send-to-peer both find their helpers beside each
# other, so ours and upstream's have to sit in one directory.
#
# Our helpers come from userspace/. The radio-independent half of omdrop-awdl
# (the AirDrop sender, the BLE advertiser, the mDNS announcer and responder,
# and the modules they import) is fetched at a pinned commit and copied
# unmodified. It is never committed to this repo: omdrop-awdl is GPL-2.0-only,
# and keeping it out of the tree keeps that a packaging decision.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
UPSTREAM_REPO=https://github.com/brentkearney/omdrop-awdl.git
UPSTREAM_COMMIT=${UPSTREAM_COMMIT:-d0d406b7415c923525cda84a970284445ee53f0b}
UP=$ROOT/upstream/omdrop-awdl
LIB=$ROOT/build/lib

# Everything here talks to awdl0 through sockets or to BlueZ over D-Bus; none
# of it touches the Broadcom firmware (that is omdrop-discoverable, awdl-up and
# brcm_iovar.py, which we replace).
FROM_UPSTREAM=(
  send-to-peer          # picks a peer and drives airdrop-send.py
  airdrop-send.py       # the AirDrop client: /Discover, /Ask, /Upload
  awdl-af-parse.py      # imported by airdrop-send.py
  awdl_identity.py      # identity, host name and record data for all of these
  awdl_debug.py         # imported by airdrop-send.py
  ble-airdrop-adv.py    # the BLE Continuity advert that wakes a receiver
  awdl-airdrop-adv.py   # unsolicited _airdrop._tcp announcements on awdl0
  awdl-mdns-respond.py  # answers mDNS queries for our identity on awdl0
)

if [ ! -d "$UP/.git" ]; then
  git clone -q "$UPSTREAM_REPO" "$UP"
fi
git -C "$UP" fetch -q origin || true
git -C "$UP" -c advice.detachedHead=false checkout -q "$UPSTREAM_COMMIT"

rm -rf "$LIB"
mkdir -p "$LIB"
for f in "${FROM_UPSTREAM[@]}"; do
  cp "$UP/userspace/$f" "$LIB/$f"
done
cp "$ROOT"/userspace/* "$LIB/"
chmod 755 "$LIB/send-to-peer" "$LIB/omdrop-discoverable" "$LIB"/*.py

echo "staged $LIB: ${#FROM_UPSTREAM[@]} files from omdrop-awdl@${UPSTREAM_COMMIT:0:7}, $(ls "$ROOT/userspace" | wc -l) of ours"
