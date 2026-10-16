"""Exercise the supervisor's loop with command doubles, never the real radio."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'userspace/omdrop-discoverable').read_text()
SUPERVISE = SOURCE[SOURCE.index('supervise()'):SOURCE.index('\ncmd_start()')]

class SuperviseTests(unittest.TestCase):
    def run_case(self, until=0, owl=True, mon=True, go=False, active=True):
        """Run the loop until it ends the window; returns what it did."""
        with tempfile.TemporaryDirectory() as tmp:
            stop = Path(tmp, 'stop')
            stop.write_text('#!/bin/sh\necho "$*" >> "$RUN/commands"\n')
            stop.chmod(0o755)
            if go:
                Path(tmp, 'go-monitors').touch()
            Path(tmp, 'until').write_text(f'{until}\n')
            env = dict(os.environ, RUN=tmp, SELF=str(stop), OWL=str(int(owl)), MON_UP=str(int(mon)), ACTIVE_UP=str(int(active)))
            script = r'''
set -uo pipefail
IF=awdl0
MON=mon0
ACTIVE=mon1
LIB=/usr/lib/omdrop
OWL_BIN=$LIB/owl
OWL_LOG=$RUN/owl.log
ADV_FLAGS=137
ADV_INTERVAL=3
ADV_BURST="--count 3 --interval 0.05"
ADV_BURST_EXCLUSIVE="--count 64 --interval 0.0164"
rounds=0
log() { echo "log $*" >> "$RUN/commands"; }
pid_of() { echo 1; }
alive() { [[ "$OWL" == 1 ]]; }
ip() { [[ "$*" == 'link show mon0' && "$MON_UP" == 1 ]] || [[ "$*" == 'link show mon1' && "$ACTIVE_UP" == 1 ]]; }
python3() { echo announce >> "$RUN/commands"; }
# A healthy window never ends by itself: two rounds are enough to see it go on.
sleep() { rounds=$((rounds + 1)); [[ "$rounds" -lt 2 ]] || exit 0; }
''' + SUPERVISE + '\nsupervise\n'
            result = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            commands = Path(tmp, 'commands')
            return commands.read_text() if commands.exists() else ''

    def test_healthy_window_keeps_announcing(self):
        out = self.run_case()
        self.assertEqual(out.count('announce'), 2)
        self.assertNotIn('stop', out)

    def test_expired_window_stops(self):
        out = self.run_case(until=1)
        self.assertIn('stop expired', out)
        self.assertNotIn('announce', out)

    def test_dead_owl_stops(self):
        out = self.run_case(owl=False)
        self.assertIn('stop owl-exited', out)
        self.assertNotIn('announce', out)

    def test_vanished_monitor_interface_stops(self):
        out = self.run_case(mon=False)
        self.assertIn('log mon0 is gone', out)
        self.assertIn('stop radio-lost', out)
        self.assertNotIn('announce', out)

    def test_vanished_go_active_monitor_stops(self):
        out = self.run_case(go=True, active=False)
        self.assertIn('log mon1 is gone', out)
        self.assertIn('stop radio-lost', out)
        self.assertNotIn('announce', out)

if __name__ == '__main__':
    unittest.main()
