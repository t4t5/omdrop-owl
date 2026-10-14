"""Exercise exclusive mode with command doubles, never the real radio."""
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
            # Whoever runs the tests through sudo must not make them call the real runuser.
            env.pop('SUDO_UID', None)
            env.pop('PKEXEC_UID', None)
            script = r'''
set -uo pipefail
IBSS=awdlibss0
MON=mon0
AWDL_BSSID=00:25:00:ff:94:73
RECONNECT_WAIT=3
log() { echo "log $*" >> "$RUN/commands"; }
knob() { :; }
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
''' + FUNCTIONS + STATION + '\n' + extra + '\ntouch "$RUN/commands"; cat "$RUN/commands"\n'
            result = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout

    def test_separate_ibss_path_leaves_station_to_networkmanager(self):
        out = self.run_case('exclusive_up wlan0 phy0 2437 || exit 10\nexclusive_down', fallback=False)
        self.assertIn('iw dev awdlibss0 ibss join omdrop 2437 HT20', out)
        self.assertIn('iw dev awdlibss0 del', out)
        self.assertIn('nmcli device set wlan0 managed yes', out)
        self.assertNotIn('set type', out)
        self.assertNotIn('connection up', out)
        self.assertNotIn('device disconnect', out)

    def test_fallback_converts_station_and_restores_ipv6_and_connection(self):
        out = self.run_case('exclusive_up wlan0 phy0 2437 || exit 10\nexclusive_down\n'
                            '[ ! -e "$RUN/exclusive" ] && [ ! -e "$RUN/converted" ] || exit 11')
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

    def test_failed_conversion_is_still_undone(self):
        out = self.run_case('''
iw_original=$(declare -f iw)
eval "${iw_original/iw ()/mock_iw ()}"
iw() { if [[ "$*" == 'dev wlan0 set type ibss' ]]; then return 1; fi; mock_iw "$@"; }
exclusive_up wlan0 phy0 2437 && exit 10
exclusive_down
''')
        self.assertIn('iw dev wlan0 set type managed', out)

    def test_idle_stop_does_not_touch_the_station(self):
        out = self.run_case('exclusive_down')
        self.assertNotIn('nmcli', out)
        self.assertNotIn('ip ', out)

    def test_probe_finds_converted_station_during_window(self):
        self.run_case('exclusive_up wlan0 phy0 2437 || exit 10\n[[ $(station_iface) == wlan0 ]] || exit 11')

    def test_failed_type_restore_keeps_state_for_next_try(self):
        out = self.run_case('''exclusive_up wlan0 phy0 2437 || exit 10
iw() { echo "iw $*" >> "$RUN/commands"; [[ "$*" != 'dev wlan0 set type managed' ]]; }
exclusive_down && exit 11
[[ -e "$RUN/exclusive" && -e "$RUN/converted" && -e "$RUN/connection" ]] || exit 12
''')
        self.assertNotIn('nmcli device set wlan0 managed yes', out)

    def test_reconnect_retries_while_networkmanager_catches_up(self):
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
        self.assertNotIn("didn't reconnect", out)

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
[[ "$attempts" == 3 ]] || exit 12
''')
        self.assertIn("didn't reconnect", out)

    def test_disconnected_station_does_not_activate_an_arbitrary_connection(self):
        out = self.run_case('''exclusive_up wlan0 phy0 2437 || exit 10
printf '%s' -- > "$RUN/connection"
exclusive_down || exit 11
''')
        self.assertNotIn('connection up uuid', out)
        self.assertIn('nmcli device set wlan0 managed yes', out)

    def test_active_monitor_makes_station_a_monitor_and_back(self):
        out = self.run_case('''PROF_MODE=active-monitor
exclusive_up wlan0 phy0 2437 || exit 10
[[ $(station_iface) == wlan0 ]] || exit 11
exclusive_down || exit 12
[ ! -e "$RUN/exclusive" ] && [ ! -e "$RUN/monitor" ] || exit 13
''')
        self.assertIn('iw dev wlan0 set type monitor', out)
        self.assertIn('iw phy phy0 interface add mon0 type monitor flags active', out)
        self.assertIn('ip link set mon0 address 02:00:00:00:00:01', out)
        self.assertIn('iw dev mon0 set freq 2437 HT20', out)
        self.assertNotIn('type ibss', out)
        self.assertIn('iw dev wlan0 set type managed', out)
        self.assertIn('connection up uuid 12345678-1234-1234-1234-123456789abc ifname wlan0', out)

    def test_failed_active_monitor_is_still_undone(self):
        out = self.run_case('''PROF_MODE=active-monitor
iw_original=$(declare -f iw)
eval "${iw_original/iw ()/mock_iw ()}"
iw() { if [[ "$*" == 'phy phy0 interface add mon0 type monitor flags active' ]]; then return 1; fi; mock_iw "$@"; }
exclusive_up wlan0 phy0 2437 && exit 10
exclusive_down || exit 11
[ ! -e "$RUN/monitor" ] || exit 12
''')
        self.assertIn('iw dev wlan0 set type managed', out)
        self.assertIn('nmcli device set wlan0 managed yes', out)

    def test_unreconnected_station_gets_its_recorded_connection_up(self):
        # A connection with autoconnect off: NetworkManager never brings it back (#51).
        out = self.run_case('''exclusive_up wlan0 phy0 2437 || exit 10
nmcli() { echo "nmcli $*" >> "$RUN/commands"; }
exclusive_down || exit 11
''', fallback=False)
        self.assertNotIn('set type', out)
        # Recorded at start, then polled for RECONNECT_WAIT seconds.
        self.assertEqual(out.count('nmcli -g GENERAL.CON-UUID device show wlan0'), 4)
        self.assertIn('connection up uuid 12345678-1234-1234-1234-123456789abc ifname wlan0', out)
        self.assertLess(out.index('nmcli device set wlan0 managed yes'), out.index('connection up uuid'))

    def test_networkmanager_reconnecting_late_is_left_alone(self):
        out = self.run_case('''exclusive_up wlan0 phy0 2437 || exit 10
nmcli() {
  echo "nmcli $*" >> "$RUN/commands"
  if [[ "$*" == '-g GENERAL.CON-UUID device show wlan0' ]]; then
    echo poll >> "$RUN/polls"
    [[ $(wc -l < "$RUN/polls") -lt 2 ]] || echo 12345678-1234-1234-1234-123456789abc
  fi
}
exclusive_down || exit 11
[[ $(wc -l < "$RUN/polls") == 2 ]] || exit 12
''', fallback=False)
        self.assertNotIn('connection up', out)

    def test_unreconnected_station_retries_are_bounded(self):
        out = self.run_case('''exclusive_up wlan0 phy0 2437 || exit 10
attempts=0
nmcli() {
  echo "nmcli $*" >> "$RUN/commands"
  if [[ "$*" == '-w 10 connection up uuid '* ]]; then
    attempts=$((attempts + 1)); return 1
  fi
}
exclusive_down || exit 11
[[ "$attempts" == 3 ]] || exit 12
''', fallback=False)
        self.assertIn("didn't reconnect", out)

    def test_disconnected_unconverted_station_is_not_waited_for(self):
        out = self.run_case('''exclusive_up wlan0 phy0 2437 || exit 10
printf '%s' -- > "$RUN/connection"
nmcli() { echo "nmcli $*" >> "$RUN/commands"; }
exclusive_down || exit 11
''', fallback=False)
        self.assertEqual(out.count('GENERAL.CON-UUID'), 1)
        self.assertNotIn('connection up uuid', out)

    CALLER = '''exclusive_up wlan0 phy0 2437 || exit 10
nmcli() { echo "nmcli $*" >> "$RUN/commands"; }
id() { [[ "$*" == '-nu 1000' ]] && echo alice; }
runuser() { echo "runuser $*" >> "$RUN/commands"; return "$RUNUSER_RC"; }
PKEXEC_UID=1000
'''

    def test_reconnect_asks_as_the_caller_for_their_stored_password(self):
        # psk-flags 1 (KWallet, GNOME Keyring): only the caller's secret agent has the password.
        out = self.run_case(self.CALLER + 'RUNUSER_RC=0\nexclusive_down || exit 11', fallback=False)
        self.assertIn('runuser -u alice -- nmcli -w 10 connection up uuid '
                      '12345678-1234-1234-1234-123456789abc ifname wlan0', out)
        self.assertNotIn('\nnmcli -w 10 connection up', out)

    def test_reconnect_falls_back_to_root_for_a_system_password(self):
        out = self.run_case(self.CALLER + 'RUNUSER_RC=1\nexclusive_down || exit 11', fallback=False)
        self.assertIn('runuser -u alice', out)
        self.assertIn('\nnmcli -w 10 connection up uuid 12345678-1234-1234-1234-123456789abc ifname wlan0', out)

    def test_reconnect_asks_as_the_sudo_user_too(self):
        # tools/test-card.sh runs the helper through sudo, not pkexec.
        out = self.run_case(self.CALLER.replace('PKEXEC_UID=1000', 'SUDO_UID=1000')
                            + 'RUNUSER_RC=0\nexclusive_down || exit 11', fallback=False)
        self.assertIn('runuser -u alice -- nmcli -w 10 connection up uuid', out)

    def test_root_caller_reconnects_without_runuser(self):
        out = self.run_case(self.CALLER.replace('PKEXEC_UID=1000', 'PKEXEC_UID=0')
                            + 'RUNUSER_RC=0\nexclusive_down || exit 11', fallback=False)
        self.assertNotIn('runuser', out)
        self.assertIn('nmcli -w 10 connection up uuid', out)

if __name__ == '__main__':
    unittest.main()
