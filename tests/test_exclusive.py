"""Exercise exclusive-mode recovery with command doubles, never the real radio."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'userspace/omdrop-discoverable').read_text()
FUNCTIONS = SOURCE[SOURCE.index('exclusive_up()'):SOURCE.index('# --------------------------------------------------------------------- status')]
STATION = SOURCE[SOURCE.index('station_iface()'):SOURCE.index('\ndriver_of()')]

class ExclusiveTests(unittest.TestCase):
    def run_case(self, extra='', fallback=True, join=True):
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, RUN=tmp, FALLBACK=str(int(fallback)), JOIN=str(int(join)))
            script = r'''
set -uo pipefail
IBSS=awdlibss0
AWDL_BSSID=00:25:00:ff:94:73
log() { echo "$*" >> "$RUN/commands"; }
nmcli() {
  echo "nmcli $*" >> "$RUN/commands"
  [[ "$*" != '-g GENERAL.CON-UUID device show wlan0' ]] || echo 12345678-1234-1234-1234-123456789abc
}
ip() { echo "ip $*" >> "$RUN/commands"; }
sysctl() { echo "sysctl $*" >> "$RUN/commands"; [[ "$1" != -n ]] || echo 0; }
sleep() { :; }
cat() {
  if [[ "$1" == /sys/class/net/wlan0/address ]]; then
    echo 02:00:00:00:00:01
  else
    command cat "$@"
  fi
}
iw() {
  echo "iw $*" >> "$RUN/commands"
  if [[ "$*" == 'phy phy0 interface add awdlibss0 type ibss' ]]; then return "$FALLBACK"; fi
  if [[ "$*" == *'ibss join'* && "$JOIN" == 0 ]]; then return 1; fi
  if [[ "$*" == *' link' ]]; then echo 'Joined IBSS 00:25:00:ff:94:73'; fi
}
''' + FUNCTIONS + STATION + '\n' + extra + '\ncat "$RUN/commands"\n'
            result = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout

    def test_fallback_reuses_station_and_restores_ipv6_and_connection(self):
        out = self.run_case('exclusive_up wlan0 phy0 2437 || exit 10\nexclusive_down\n[ ! -e "$RUN/exclusive" ] || exit 11')
        self.assertIn('iw dev wlan0 set type ibss', out)
        self.assertIn('iw dev wlan0 ibss join omdrop 2437 HT20', out)
        self.assertIn('iw dev wlan0 set type managed', out)
        self.assertIn('sysctl -qw net.ipv6.conf.wlan0.disable_ipv6=0', out)
        self.assertIn('connection up uuid 12345678-1234-1234-1234-123456789abc ifname wlan0', out)
        self.assertNotIn('iw dev wlan0 del', out)

    def test_failed_join_also_restores_station(self):
        out = self.run_case('exclusive_up wlan0 phy0 2437 && exit 10\nexclusive_down', join=False)
        self.assertIn('iw dev wlan0 set type managed', out)
        self.assertIn('nmcli device set wlan0 managed yes', out)

    def test_original_separate_ibss_path_keeps_station_type(self):
        out = self.run_case('exclusive_up wlan0 phy0 2437 || exit 10\nexclusive_down', fallback=False)
        self.assertIn('iw dev awdlibss0 ibss join omdrop 2437 HT20', out)
        self.assertIn('iw dev awdlibss0 del', out)
        self.assertNotIn('iw dev wlan0 set type', out)

    def test_idle_stop_does_not_touch_network(self):
        out = self.run_case('touch "$RUN/commands"\nexclusive_down')
        self.assertEqual(out, '')

    def test_conversion_failure_is_recoverable(self):
        out = self.run_case('''
iw_original=$(declare -f iw)
eval "${iw_original/iw ()/mock_iw ()}"
iw() { if [[ "$*" == 'dev wlan0 set type ibss' ]]; then return 1; fi; mock_iw "$@"; }
exclusive_up wlan0 phy0 2437 && exit 10
exclusive_down
''')
        self.assertIn('iw dev wlan0 set type managed', out)


    def test_active_window_probe_finds_converted_station(self):
        out = self.run_case('exclusive_up wlan0 phy0 2437 || exit 10\n[[ $(station_iface) == wlan0 ]] || exit 11\nexclusive_down')
        self.assertIn('iw dev wlan0 set type ibss', out)

    def test_restore_failure_keeps_state_for_next_stop(self):
        out = self.run_case('''exclusive_up wlan0 phy0 2437 || exit 10
# A failed type restoration must not discard the saved original settings.
iw() { echo "iw $*" >> "$RUN/commands"; [[ "$*" != 'dev wlan0 set type managed' ]]; }
exclusive_down && exit 11
[[ -e "$RUN/exclusive" && -e "$RUN/converted" && -e "$RUN/ipv6" && -e "$RUN/connection" ]] || exit 12
''')
        self.assertNotIn('nmcli device set wlan0 managed yes', out)

    def test_reconnect_retries_after_networkmanager_observes_type_change(self):
        out = self.run_case('''exclusive_up wlan0 phy0 2437 || exit 10
attempts=0
nmcli() {
  echo "nmcli $*" >> "$RUN/commands"
  if [[ "$*" == '-w 10 connection up uuid '* ]]; then
    attempts=$((attempts + 1))
    [[ "$attempts" -ge 2 ]]
  fi
}
exclusive_down || exit 11
[[ "$attempts" == 2 ]] || exit 12
''')
        self.assertEqual(out.count('nmcli -w 10 connection up uuid'), 2)

    def test_disconnected_station_does_not_activate_an_arbitrary_connection(self):
        out = self.run_case('''exclusive_up wlan0 phy0 2437 || exit 10
printf '%s' -- > "$RUN/connection"
exclusive_down || exit 11
''')
        self.assertNotIn('connection up uuid', out)
        self.assertIn('nmcli device set wlan0 managed yes', out)

    def test_reconnect_retries_are_bounded(self):
        out = self.run_case('''exclusive_up wlan0 phy0 2437 || exit 10
attempts=0
nmcli() {
  echo "nmcli $*" >> "$RUN/commands"
  if [[ "$*" == '-w 10 connection up uuid '* ]]; then
    attempts=$((attempts + 1)); return 1
  fi
}
exclusive_down || exit 11
[[ "$attempts" == 10 ]] || exit 12
''')
        self.assertIn('did not reconnect', out)

if __name__ == '__main__':
    unittest.main()
