"""GO profile lifecycle through real helper functions and fake radio commands."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'userspace/omdrop-discoverable').read_text()
SOURCE = SOURCE[:SOURCE.rindex('case "${1:-}" in')]

class GoTests(unittest.TestCase):
    def run_case(self, body, **settings):
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, TEST_RUN=tmp, GROUP_OK='1', FAIL_ACTIVE='0',
                       EXISTING_GROUP='0', GROUP_VISIBLE='1', EXISTING_ACTIVE='0')
            env.update(settings)
            harness = r'''
RUN=$TEST_RUN
CONF=$RUN/conf
LIB=$RUN/lib
mkdir -p "$CONF" "$LIB"
OWL_BIN=$LIB/owl
OWL_LOG=$RUN/owl.log
SELF=$RUN/helper
printf '#!/bin/bash\nexit 0\n' > "$OWL_BIN"
chmod +x "$OWL_BIN"
record() { printf '%s\n' "$*" >> "$RUN/commands"; }
log() { record "log $*"; }
need_root() { :; }
sleep() { :; }
sysctl() { record "sysctl $*"; }
ip() { record "ip $*"; }
pkill() { record "pkill $*"; }
mountpoint() { return 0; }
mt76_dir() { echo "$RUN/no-pm"; }
station_iface() { echo wlan0; }
driver_of() { echo another_driver; }
readlink() { echo phy0; }
nmcli() { record "nmcli $*"; [[ "$*" != '-g GENERAL.CON-UUID device show wlan0' ]] || echo --; }
cat() {
  case "${1:-}" in
    /sys/class/net/*/address) echo 02:00:00:00:00:01 ;;
    *) command cat "$@" ;;
  esac
}
iw() {
  record "iw $*"
  case "$*" in
    'phy phy0 info') printf 'Device supports active monitor\n\t * P2P-GO\n' ;;
    'phy phy0 channels') printf '\t* 5220 MHz\n\t* 2437 MHz\n' ;;
    'dev mon1 info') [[ "$EXISTING_ACTIVE" == 1 ]] ;;
    dev)
      # A foreign group's name deliberately resembles the old naming rule.
      printf 'phy#1\n\tInterface p2p-wlan0-9\n\t\ttype P2P-GO\nphy#0\n'
      if [[ "$EXISTING_GROUP" == 1 || ( -f "$RUN/group" && "$GROUP_VISIBLE" == 1 ) ]]; then
        printf '\tInterface arbitrary-go\n\t\ttype P2P-GO\n'
      fi ;;
    'phy phy0 interface add mon1 type monitor flags active') [[ "$FAIL_ACTIVE" != 1 ]] ;;
  esac
}
wpa_supplicant() {
  [[ ! -e /proc/$BASHPID/fd/9 ]] || return 20
  record "wpa_supplicant $*"
  echo 424242 > "$RUN/p2p.pid"
  echo 'daemon startup output'
}
wpa_cli() {
  record "wpa_cli $*"
  if [[ "$GROUP_OK" == 1 ]]; then touch "$RUN/group"; echo OK; else echo FAIL; fi
}
ALIVE=yes
alive() { [[ "${1:-}" == 424242 && "$ALIVE" == yes ]]; }
kill() { record "kill $*"; ALIVE=no; }
setsid() { record "setsid $*"; }
PROF_MODE=go
PROF_MONMAC=station
exec 9> "$RUN/lock"
'''
            result = subprocess.run(['bash', '-c', SOURCE + harness + body],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            return (Path(tmp) / 'commands').read_text() if (Path(tmp) / 'commands').exists() else ''

    def test_start_closes_daemon_lock_and_aliases_both_monitors(self):
        out = self.run_case(r'''
freq=$(exclusive_up wlan0 phy0 2437) || exit 21
[[ "$freq" == 2437 ]] || exit 22
[[ $(stat -c %a "$RUN/p2p.conf") == 600 ]] || exit 23
grep -q 'daemon startup output' "$RUN/p2p-bootstrap.log" || exit 24
[[ $(cat "$RUN/p2p-interface") == arbitrary-go ]] || exit 25
''')
        self.assertIn('ip link set mon0 address 02:00:00:00:00:01', out)
        self.assertIn('ip link set mon1 address 02:00:00:00:00:01', out)
        self.assertIn('p2p_group_add freq=2437', out)
        self.assertNotIn('type ibss', out)

    def test_stop_and_expiry_remove_group_before_restoring_management(self):
        for reason in ('stopped', 'expired'):
            with self.subTest(reason=reason):
                out = self.run_case('exclusive_up wlan0 phy0 2437 >/dev/null || exit 21\n'
                                    f'cmd_stop {reason}\n' + r'''
[[ ! -e "$RUN/p2p.pid" && ! -e "$RUN/go-monitors" && ! -e "$RUN/exclusive" ]] || exit 22
[[ ! -d "$RUN/p2p-control" ]] || exit 23
''')
                self.assertIn('kill 424242', out)
                self.assertIn('iw dev mon0 del', out)
                self.assertIn('iw dev mon1 del', out)
                self.assertLess(out.index('iw dev arbitrary-go del'),
                                out.index('nmcli device set wlan0 managed yes'))

    def test_group_failure_restores_station(self):
        out = self.run_case('exclusive_up wlan0 phy0 2437 && exit 21\ncmd_stop start-failed', GROUP_OK='0')
        self.assertIn('kill 424242', out)
        self.assertIn('nmcli device set wlan0 managed yes', out)

    def test_missing_group_after_ok_is_cleaned_up(self):
        out = self.run_case('exclusive_up wlan0 phy0 2437 && exit 21\ncmd_stop start-failed', GROUP_VISIBLE='0')
        self.assertIn('kill 424242', out)
        self.assertNotIn('iw dev arbitrary-go del', out)

    def test_monitor_failure_removes_partial_setup(self):
        out = self.run_case('exclusive_up wlan0 phy0 2437 && exit 21\ncmd_stop start-failed', FAIL_ACTIVE='1')
        self.assertIn('iw dev mon0 del', out)
        self.assertIn('nmcli device set wlan0 managed yes', out)

    def test_existing_group_is_not_claimed(self):
        out = self.run_case('exclusive_up wlan0 phy0 2437 && exit 21\ncmd_stop start-failed', EXISTING_GROUP='1')
        self.assertNotIn('wpa_supplicant ', out)
        self.assertNotIn('iw dev arbitrary-go del', out)

    def test_existing_active_monitor_is_preserved(self):
        out = self.run_case('exclusive_up wlan0 phy0 2437 && exit 21\ncmd_stop start-failed', EXISTING_ACTIVE='1')
        self.assertNotIn('wpa_supplicant ', out)
        self.assertNotIn('iw dev mon1 del', out)

    def test_missing_supplicant_is_reported_before_radio_setup(self):
        self.run_case(r'''
command() { [[ "$*" != '-v wpa_supplicant' ]] && builtin command "$@"; }
[[ $(go_problem phy0) == *'needs wpa_supplicant and wpa_cli'* ]] || exit 21
''')

    def test_stale_pid_does_not_signal_unrelated_process(self):
        out = self.run_case('echo 424242 > "$RUN/p2p.pid"\nALIVE=no\ngo_down')
        self.assertNotIn('kill ', out)

    def test_profile_override_is_generic_and_selects_active_owl_interface(self):
        out = self.run_case(r'''
PROFILES=$RUN/profiles
printf 'another_driver untested go station no no\n' > "$CONF/owl-profiles"
printf '* untested shared station yes no\n' > "$PROFILES"
echo 1 > "$CONF/allow-untested"
cmd_start 15
wait
''')
        self.assertIn('-i mon1 -c 6 -N -S intersect -F -E', out)
        self.assertNotIn('-S pin', out)

    def test_probe_finds_the_recorded_station_during_go_window(self):
        # Restore the actual station selector, not the harness's fixed result.
        start = SOURCE.index('station_iface()')
        end = SOURCE.index('\ndriver_of()', start)
        self.run_case(SOURCE[start:end] + r'''
echo wlan0 > "$RUN/exclusive"
echo 424242 > "$RUN/p2p.pid"
[[ $(station_iface) == wlan0 ]] || exit 21
''')

    def test_go_channel_selection_is_only_six(self):
        self.run_case('[[ $(tx_channels phy0) == 2437 ]] || exit 21')

    def test_profile_rejects_own_mac_and_unsupported_hardware(self):
        self.run_case(r'''
[[ -z $(go_problem phy0) ]] || exit 21
PROF_MONMAC=own
[[ $(go_problem phy0) == *'mon_mac station'* ]] || exit 22
PROF_MONMAC=station
iw() { :; }
[[ $(go_problem phy0) == *'P2P-GO and active-monitor'* ]] || exit 23
''')

if __name__ == '__main__':
    unittest.main()
