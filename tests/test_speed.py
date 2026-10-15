"""Exercise the channel choice and OWL's speed options with command doubles, never the real radio."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'userspace/omdrop-discoverable').read_text()
KNOB = re.search(r'^knob\(\).*$', SOURCE, re.M).group()
FUNCTIONS = SOURCE[SOURCE.index('tx_channels()'):SOURCE.index('\n# Take the station off the air')]

# `iw phy channels` for a card whose regulatory domain leaves 36 receive-only
# and, with NO_IR_44, 44 too.
IW = r'''
iw() {
  printf '%s\n' 'Band 1:' '	* 2437 MHz [6]' '	  Maximum TX power: 20.0 dBm' \
    'Band 2:' '	* 5180 MHz [36]' '	  No IR' '	* 5220 MHz [44]' '	  Maximum TX power: 23.0 dBm'
  [[ -z "${NO_IR_44:-}" ]] || echo '	  No IR'
  printf '%s\n' '	* 5745 MHz [149]' '	  Maximum TX power: 20.0 dBm'
}
'''

class SpeedTests(unittest.TestCase):
    def run_case(self, body, knobs=None, **env):
        with tempfile.TemporaryDirectory() as conf:
            for name, value in (knobs or {}).items():
                Path(conf, name).write_text(value + '\n')
            script = f'set -uo pipefail\nCONF={conf}\n{KNOB}\n{IW}\n{FUNCTIONS}\n{body}\n'
            result = subprocess.run(['bash', '-c', script], env=dict(os.environ, **env),
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout.split()

    def channels(self, mode, knobs=None, **env):
        return self.run_case(f'PROF_MODE={mode}\ntx_channels phy0 || true', knobs, **env)

    def options(self, drv, chan, mode='active-monitor', knobs=None):
        return self.run_case(f'PROF_MODE={mode}\nowl_extra=()\nowl_speed_options {drv} {chan}\necho "${{owl_extra[@]}}"', knobs)

    def test_active_monitor_stays_on_channel_6_by_default(self):
        self.assertEqual(self.channels('active-monitor'), ['2437'])

    def test_exclusive_mode_order_is_unchanged(self):
        self.assertEqual(self.channels('exclusive'), ['5220', '5745', '2437'])

    def test_exclusive_channel_file_picks_the_frequency(self):
        self.assertEqual(self.channels('active-monitor', {'exclusive-channel': '5220'}), ['5220'])

    def test_regulatory_domain_still_filters_the_frequency(self):
        self.assertEqual(self.channels('active-monitor', {'exclusive-channel': '5220'}, NO_IR_44='1'), [])
        self.assertEqual(self.channels('active-monitor', {'exclusive-channel': '5180'}), [])

    def test_mt7921e_on_44_aggregates_and_sends_wide_at_mcs15(self):
        self.assertEqual(self.options('mt7921e', 44), ['-A', '-V', '-R', 'mcs15-40-sgi'])

    def test_mt7921e_on_6_only_aggregates(self):
        self.assertEqual(self.options('mt7921e', 6), ['-A'])

    def test_mt76x2u_only_aggregates(self):
        self.assertEqual(self.options('mt76x2u', 44), ['-A'])
        self.assertEqual(self.options('mt76x2u', 149), ['-A'])

    def test_other_cards_get_neither(self):
        self.assertEqual(self.options('iwlwifi', 44, 'exclusive'), [])
        self.assertEqual(self.options('mt7925e', 44, 'shared'), [])

    def test_aggregation_file_overrides(self):
        self.assertEqual(self.options('mt7921e', 44, knobs={'aggregation': '0'}), ['-V', '-R', 'mcs15-40-sgi'])
        self.assertEqual(self.options('iwlwifi', 6, 'exclusive', {'aggregation': '1'}), ['-A'])

if __name__ == '__main__':
    unittest.main()
