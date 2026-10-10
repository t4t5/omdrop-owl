"""Exercise exclusive-mode recovery with command doubles, never the real radio."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'userspace/omdrop-discoverable').read_text()
FUNCTIONS = SOURCE[SOURCE.index('exclusive_up()'):SOURCE.index('# --------------------------------------------------------------------- status')]

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
iw() {
  echo "iw $*" >> "$RUN/commands"
  if [[ "$*" == 'phy phy0 interface add awdlibss0 type ibss' ]]; then return "$FALLBACK"; fi
  if [[ "$*" == *'ibss join'* && "$JOIN" == 0 ]]; then return 1; fi
  if [[ "$*" == *' link' ]]; then echo 'Joined IBSS 00:25:00:ff:94:73'; fi
}
''' + FUNCTIONS + '\n' + extra + '\ncat "$RUN/commands"\n'
            result = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True)
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

if __name__ == '__main__':
    unittest.main()
