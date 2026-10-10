# Shared fixtures for the omdrop-discoverable tests: an isolated lib dir with
# the script under test, a fake /sys/class/net, stub commands first on PATH,
# and writable OMDROP_RUN/OMDROP_CONF/OMDROP_DEBUGFS. The script must behave
# with its production paths when those variables are unset; everything here
# goes through the documented test overrides.

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# This bats build does not ship `fail`; provide the usual semantics.
fail() { echo "$*" >&2; exit 1; }

setup() {
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/omdrop-owl-test.XXXXXX")
  LIB=$TMP/lib NET=$TMP/net RUND=$TMP/run CONF=$TMP/conf DEBUGFS=$TMP/debugfs
  STUBS=$REPO/tests/stubs
  mkdir -p "$LIB" "$NET" "$RUND" "$CONF" "$DEBUGFS"
  cp "$REPO/userspace/omdrop-discoverable" "$LIB/omdrop-discoverable"
  chmod +x "$LIB/omdrop-discoverable"
  cp "$REPO/tests/fixtures/owl-profiles" "$LIB/owl-profiles"
  printf '#!/bin/bash\nexit 0\n' > "$LIB/owl"
  chmod +x "$LIB/owl"
  mkwifi
}

teardown() {
  [ -n "${OWLPID:-}" ] && kill "$OWLPID" 2>/dev/null
  [ -n "${SUPPID:-}" ] && kill "$SUPPID" 2>/dev/null
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
  return 0
}

# A station interface with driver mt7925e, like /sys/class/net presents it:
# driver and phy80211 are symlinks whose target's basename is the name.
mkwifi() {
  # A distinctive phy name: readlink of the fake $NET yields "phyFAKE", so a
  # test asserting that basename proves the helper used $NET, not real sysfs.
  mkdir -p "$NET/wlan0/device" "$NET/drivers/mt7925e" "$NET/phyFAKE"
  ln -s "$NET/drivers/mt7925e" "$NET/wlan0/device/driver"
  ln -s "$NET/phyFAKE" "$NET/wlan0/phy80211"
  echo aa:bb:cc:dd:ee:ff > "$NET/wlan0/address"
}

# Rebrand the station's driver: driver_of reads the symlink target's basename.
mkdriver() {
  mkdir -p "$NET/drivers/$1"
  ln -sfn "$NET/drivers/$1" "$NET/wlan0/device/driver"
}

run_helper() {
  PATH="$STUBS:$PATH" OMDROP_RUN="$RUND" OMDROP_NET_DIR="$NET" \
    OMDROP_CONF="$CONF" OMDROP_DEBUGFS="$DEBUGFS" TEST_TMP="$TMP" \
    "$LIB/omdrop-discoverable" "$@"
}

# A live process whose /proc cmdline contains $LIB/owl, like OWL would be.
# The loop keeps bash as the running image: bash exec-optimizes a simple
# `bash -c 'sleep N'` and the $0 (and with it the fake cmdline) would be lost.
fake_owl_running() {
  bash -c 'for i in 1 2 3 4 5 6; do sleep 5; done' "$LIB/owl" -i mon0 -c 6 -S intersect >/dev/null 2>&1 &
  OWLPID=$!
  echo $OWLPID > "$RUND/owl.pid"
}

# A live process whose /proc cmdline contains __supervise.
fake_supervisor_running() {
  bash -c 'for i in 1 2 3 4 5 6; do sleep 5; done' "$LIB/omdrop-discoverable" __supervise >/dev/null 2>&1 &
  SUPPID=$!
  echo $SUPPID > "$RUND/supervisor.pid"
}
