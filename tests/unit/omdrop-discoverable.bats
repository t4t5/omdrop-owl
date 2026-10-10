#!/usr/bin/env bats
# The omdrop-discoverable contract: usage and exit codes (0/2/3/4/5), the
# status/peers/probe surfaces, and the start/stop state machine, all against
# stubbed iw/ip and a fake /sys/class/net.

load ../helpers

# ---------------------------------------------------------------- usage/root

@test "no arguments is a usage error (exit 2)" {
  run run_helper
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "start without seconds is a usage error (exit 2)" {
  run run_helper start
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "start rejects a non-numeric window (exit 2)" {
  run run_helper start soon
  [ "$status" -eq 2 ]
}

@test "an unknown command is a usage error (exit 2)" {
  run run_helper frobnicate
  [ "$status" -eq 2 ]
}

@test "start without root refuses (exit 2)" {
  TEST_FAKE_UID=1000 run run_helper start 10
  [ "$status" -eq 2 ]
  [[ "$output" == *"root"* ]]
}

# ------------------------------------------------------------------- probe
# probe is the unprivileged surface: no root, no side effects.

@test "probe with no Wi-Fi hardware reports it" {
  rm -rf "$NET"
  mkdir -p "$NET"
  run run_helper probe --json
  [ "$status" -eq 0 ]
  python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["backend"] == "owl"
assert d["hardware"] is False
assert d["missing"][0]["id"] == "hardware"
assert "no Wi-Fi interface" in d["missing"][0]["say"]' "$output"
}

@test "probe on an untested card suggests opting in" {
  mkdriver otherdrv
  run run_helper probe --json
  [ "$status" -eq 0 ]
  python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["hardware"] is False
assert d["missing"][0]["id"] == "hardware"
assert "allow-untested" in d["missing"][0]["say"]' "$output"
}

@test "probe with allow-untested on an AWDL channel is ready" {
  mkdriver otherdrv
  echo 1 > "$CONF/allow-untested"
  run run_helper probe --json
  [ "$status" -eq 0 ]
  python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["hardware"] is True
assert d["missing"] == []' "$output"
  run run_helper probe
  [ "$status" -eq 0 ]
  [ "$output" = ready ]
}

@test "probe reports a non-AWDL channel" {
  mkdriver otherdrv
  echo 1 > "$CONF/allow-untested"
  TEST_FREQ=5180.0 run run_helper probe --json
  [ "$status" -eq 0 ]
  python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["missing"][0]["id"] == "radio"
assert "5180" in d["missing"][0]["say"]' "$output"
}

@test "probe reports a disconnected station" {
  mkdriver otherdrv
  echo 1 > "$CONF/allow-untested"
  TEST_NO_LINK=1 run run_helper probe --json
  [ "$status" -eq 0 ]
  python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["missing"][0]["id"] == "radio"
assert "isn'"'"'t connected" in d["missing"][0]["say"]' "$output"
}

@test "probe prefers the conf-dir owl-profiles table" {
  mkdriver otherdrv
  # Without the override this card would fall back to the untested row: the
  # override table is read first, and its otherdrv row is what makes this ready.
  printf 'otherdrv tested shared station no no fictional override\n' > "$CONF/owl-profiles"
  run run_helper probe --json
  [ "$status" -eq 0 ]
  python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["hardware"] is True
assert d["missing"] == []' "$output"
}

@test "probe reports its version and contract" {
  run run_helper probe --json
  [ "$status" -eq 0 ]
  python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["version"] == "0.1.0"
assert d["contract"] == "0.8.1"' "$output"
}

# ------------------------------------------------------------------- start

@test "start without a Wi-Fi interface is exit 4" {
  rm -rf "$NET"
  mkdir -p "$NET"
  run run_helper start 10
  [ "$status" -eq 4 ]
  [[ "$output" == *"no Wi-Fi interface"* ]]
}

@test "start on an untested card without allow-untested is exit 4" {
  mkdriver otherdrv
  run run_helper start 10
  [ "$status" -eq 4 ]
  [[ "$output" == *"allow-untested"* ]]
}

@test "start on a card without any profile is exit 4" {
  rm "$LIB/owl-profiles"
  run run_helper start 10
  [ "$status" -eq 4 ]
  [[ "$output" == *"profile"* ]]
}

@test "start with Wi-Fi not passing traffic is exit 3" {
  TEST_NO_GW=1 run run_helper start 10
  [ "$status" -eq 3 ]
  [[ "$output" == *"Connect to Wi-Fi"* ]]
}

@test "start on a foreign channel is exit 3" {
  TEST_FREQ=5180.0 run run_helper start 10
  [ "$status" -eq 3 ]
  [[ "$output" == *"5180"* ]]
}

@test "start on an AWDL channel succeeds and records its state" {
  run run_helper start 10
  [ "$status" -eq 0 ]
  grep -Fq "$LIB/owl -i mon0 -c 6 -N -S intersect" "$TMP/setsid.log"
  # The monitor vif was created on the phy read from the fake $NET: asserting
  # the phyFAKE basename would fail had that path been hardcoded to real sysfs.
  grep -Fq "phy phyFAKE interface add mon0" "$TMP/iw.log"
  [ "$(cat "$RUND/station")" = wlan0 ]
  [ "$(cat "$RUND/profile")" = "mt7925e shared station yes no" ]
  read -r until_ts < "$RUND/until"
  local now; now=$(date +%s)
  [ "$until_ts" -gt "$now" ] && [ "$(( until_ts - now ))" -le 11 ]
}

@test "start passes the station MAC to OWL with mon_mac=own" {
  printf 'mt7925e tested shared own yes no MediaTek MT7925\n' > "$CONF/owl-profiles"
  run run_helper start 10
  [ "$status" -eq 0 ]
  grep -Fq -- "-m aa:bb:cc:dd:ee:ff" "$TMP/setsid.log"
  # The monitor interface carries a locally-administered MAC of its own.
  grep -Fq "link set mon0 address 02:bb:cc:dd:ee:ff" "$TMP/ip.log"
}

@test "a second start while discoverable extends the window (exit 5)" {
  fake_supervisor_running
  echo $(( $(date +%s) + 60 )) > "$RUND/until"
  run run_helper start 30
  [ "$status" -eq 5 ]
  read -r until_ts < "$RUND/until"
  local now; now=$(date +%s)
  [ "$(( until_ts - now ))" -ge 25 ] && [ "$(( until_ts - now ))" -le 31 ]
}

@test "start with a zero window records until=0" {
  run run_helper start 0
  [ "$status" -eq 0 ]
  [ "$(cat "$RUND/until")" = 0 ]
}

# -------------------------------------------------------------------- stop

@test "stop tears down and records the reason" {
  fake_owl_running
  echo wlan0 > "$RUND/station"
  echo 0 > "$CONF/reconnect-after"
  run run_helper stop
  [ "$status" -eq 0 ]
  [ ! -e "$RUND/owl.pid" ]
  [ ! -e "$RUND/until" ]
  [ "$(cat "$RUND/reason")" = stopped ]
  # cmd_stop killed the live owl process: reap it (143 = terminated by SIGTERM),
  # then the pid no longer exists.
  wait "$OWLPID" 2>/dev/null || true
  ! kill -0 "$OWLPID" 2>/dev/null
}

@test "stop keeps an explicit reason" {
  echo 0 > "$CONF/reconnect-after"
  run run_helper stop expired
  [ "$status" -eq 0 ]
  [ "$(cat "$RUND/reason")" = expired ]
}

@test "stop reconnects when the profile says so" {
  echo wlan0 > "$RUND/station"
  echo 1 > "$CONF/reconnect-after"
  run run_helper stop
  [ "$status" -eq 0 ]
  grep -Fq "device connect wlan0" "$TMP/nmcli.log"
}

@test "stop skips the reconnect when the profile says no" {
  echo wlan0 > "$RUND/station"
  echo "otherdrv shared station no no" > "$RUND/profile"
  run run_helper stop
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/nmcli.log" ]
}

@test "stop restores mt76 power management" {
  mkdir -p "$DEBUGFS/ieee80211/phyFAKE/mt76"
  printf '2\n' > "$DEBUGFS/ieee80211/phyFAKE/mt76/runtime-pm"
  printf '15\n' > "$DEBUGFS/ieee80211/phyFAKE/mt76/deep-sleep"
  echo wlan0 > "$RUND/station"
  echo "2 15" > "$RUND/pm"
  echo 0 > "$CONF/reconnect-after"
  run run_helper stop
  [ "$status" -eq 0 ]
  [ "$(cat "$DEBUGFS/ieee80211/phyFAKE/mt76/runtime-pm")" = 2 ]
  [ "$(cat "$DEBUGFS/ieee80211/phyFAKE/mt76/deep-sleep")" = 15 ]
}

@test "stop without root refuses (exit 2)" {
  TEST_FAKE_UID=1000 run run_helper stop
  [ "$status" -eq 2 ]
}

# ------------------------------------------------------------------ status

@test "status when nothing runs: not visible" {
  run run_helper status
  [ "$status" -eq 0 ]
  [[ "$output" == "visible=false remaining=null reason= rx_proven=false" ]]
}

@test "status --json when nothing runs" {
  run run_helper status --json
  [ "$status" -eq 0 ]
  python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["visible"] is False
assert d["remaining"] is None
assert d["rx_proven"] is False' "$output"
}

@test "status reports a live window and rx proven by OWL" {
  fake_owl_running
  fake_supervisor_running
  echo $(( $(date +%s) + 60 )) > "$RUND/until"
  mkdir -p "$RUND"
  echo "INFO add peer 86:8:4:8a:2b:f4 (iPhone)" > "$RUND/owl.log"
  run run_helper status --json
  [ "$status" -eq 0 ]
  python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["visible"] is True
assert 50 <= d["remaining"] <= 60
assert d["rx_proven"] is True' "$output"
}

@test "status of a window without peers: rx not proven" {
  fake_owl_running
  fake_supervisor_running
  echo $(( $(date +%s) + 60 )) > "$RUND/until"
  : > "$RUND/owl.log"
  run run_helper status --json
  [ "$status" -eq 0 ]
  python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["visible"] is True
assert d["rx_proven"] is False' "$output"
}

# ------------------------------------------------------------------- peers

@test "peers without an OWL log is exit 4" {
  run run_helper peers
  [ "$status" -eq 4 ]
  [[ "$output" == *"no OWL log"* ]]
}

@test "peers pads unpadded MACs and honors removals" {
  {
    echo "INFO add peer 86:8:4:8a:2b:f4 (iPhone)"
    echo "INFO add peer aa:b:cc:dd:e:ff (old)"
    echo "INFO remove peer aa:b:cc:dd:e:ff (old)"
    echo "INFO add peer f6:1:22:33:44:55 (iPad)"
  } > "$RUND/owl.log"
  run run_helper peers
  [ "$status" -eq 0 ]
  [ "$(sort <<< "$output")" = "$(printf '86:08:04:8a:2b:f4 rssi=?\nf6:01:22:33:44:55 rssi=?')" ]
}
