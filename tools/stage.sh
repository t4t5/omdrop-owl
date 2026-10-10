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
# OMDROP_STAGE_ROOT exists only for the unit tests, which run unprivileged and
# must not touch a developer's real upstream/ and build/ directories.
STAGE_ROOT=${OMDROP_STAGE_ROOT:-$ROOT}
UPSTREAM_REPO=https://github.com/brentkearney/omdrop-awdl.git
# shellcheck disable=SC1091
. "$ROOT/pins"
UPSTREAM_COMMIT=$OMDROP_AWDL_COMMIT
UP=$STAGE_ROOT/upstream/omdrop-awdl
LIB=$STAGE_ROOT/build/lib

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

OWL_BIN=$STAGE_ROOT/upstream/owl/build/daemon/owl
[ -x "$OWL_BIN" ] || { echo "no OWL build at $OWL_BIN; run tools/build-owl.sh first"; exit 1; }

if [ ! -d "$UP/.git" ]; then
  git clone -q "$UPSTREAM_REPO" "$UP"
fi
git -C "$UP" fetch -q origin || true
git -C "$UP" -c advice.detachedHead=false checkout -q "$UPSTREAM_COMMIT"

# Replace files rather than the directory: running these tools as root (as
# pkexec does) leaves a root-owned __pycache__ here, which a user can't delete
# and Python revalidates against the sources anyway.
mkdir -p "$LIB"
find "$LIB" -maxdepth 1 -type f -delete
for f in "${FROM_UPSTREAM[@]}"; do
  cp "$UP/userspace/$f" "$LIB/$f"
done
cp "$ROOT"/userspace/* "$LIB/"
cp "$OWL_BIN" "$LIB/owl"
chmod 755 "$LIB/send-to-peer" "$LIB/omdrop-discoverable" "$LIB/owl" "$LIB"/*.py

echo "staged $LIB: ${#FROM_UPSTREAM[@]} files from omdrop-awdl@${UPSTREAM_COMMIT:0:7}, $(find "$ROOT/userspace" -maxdepth 1 -type f | wc -l) of ours, and owl"
