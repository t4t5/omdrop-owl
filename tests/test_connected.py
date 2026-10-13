"""Connected-mode policy and recovery checks. Never operates a real radio."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('connected', ROOT / 'userspace/connected-radio.py')
radio = importlib.util.module_from_spec(spec)
spec.loader.exec_module(radio)
SOURCE = (ROOT / 'userspace/omdrop-discoverable').read_text()


class ConnectedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.net = self.root / 'net'; self.net.mkdir()
        self.run = self.root / 'run'; self.run.mkdir()
        self.phy = self.root / 'phy8'; self.phy.mkdir()
        self.state = dict(station='wlan-test', phy='phy8', mac='02:25:00:aa:00:01', indices={})
        self.commands = []

    def tearDown(self):
        self.temp.cleanup()

    def iface(self, name, mac=None, index=4):
        n = self.net / name; n.mkdir()
        (n / 'address').write_text(mac or self.state['mac'])
        (n / 'ifindex').write_text(str(index))
        (n / 'phy80211').symlink_to(self.phy)
        return n

    def cmd(self, args, **kw):
        self.commands.append(args)
        if args[:2] == ['iw', 'dev'] and args[-1] == 'del':
            p = self.net / args[2]
            for child in p.iterdir(): child.unlink()
            p.rmdir()
        return SimpleNamespace(returncode=0, stdout='', stderr='')

    def cleanup(self):
        with patch.object(radio, 'RUN', self.run), patch.object(radio, 'NET', self.net), patch.object(radio, 'command', self.cmd):
            radio.cleanup()

    def save(self):
        (self.run / 'go-state.json').write_text(json.dumps(self.state))

    def test_partial_start_cleanup_uses_reserved_mac_and_phy(self):
        self.iface('awdlgo0')
        self.iface('wlan-test', '10:11:12:13:14:15')
        self.save(); self.cleanup(); self.cleanup()
        self.assertTrue((self.net / 'wlan-test').exists())
        self.assertEqual(self.commands, [['iw', 'dev', 'awdlgo0', 'del']])
        self.assertFalse((self.run / 'go-state.json').exists())

    def test_replacement_interface_is_not_deleted(self):
        self.iface('awdlgo0', index=8)
        self.state['indices'] = {'awdlgo0': 4}
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'identity changed'):
            self.cleanup()
        self.assertEqual(self.commands, [])
        self.assertTrue((self.run / 'go-state.json').exists())

    def test_foreign_mac_or_phy_is_not_deleted(self):
        n = self.iface('mon0', '02:ff:00:00:00:01')
        self.save()
        with self.assertRaises(RuntimeError): self.cleanup()
        (n / 'address').write_text(self.state['mac'])
        self.state['phy'] = 'phy9'; self.save()
        with self.assertRaises(RuntimeError): self.cleanup()
        self.assertEqual(self.commands, [])

    def test_cleanup_order_and_readiness_removal(self):
        for name in radio.OWNED: self.iface(name)
        for name in ('go-ready', 'supervisor.pid', 'owl.pid'): (self.run / name).write_text('ready')
        self.save(); self.cleanup()
        self.assertEqual([c[2] for c in self.commands], ['mon0', 'awdlgo0'])
        self.assertEqual(list(self.run.iterdir()), [])

    def test_regulatory_accepts_installed_iw_format_without_bypass(self):
        for freq in ('2437', '2437.0'):
            row = f'* {freq} MHz [6] (22.0 dBm)'
            self.assertTrue(radio.legal_channel(row))
            for restriction in ('disabled', 'no IR', 'radar detection'):
                self.assertFalse(radio.legal_channel(row + f' ({restriction})'))
        self.assertFalse(radio.legal_channel('* 2437 MHz [6]\n* 2437 MHz [6]'))

    def test_profile_selection_and_admin_precedence(self):
        function = SOURCE[SOURCE.index('load_profile()'):SOURCE.index('# The manager owns')]
        conf = self.root / 'conf'; conf.mkdir()
        profiles = self.root / 'profiles'
        profiles.write_text('iwlwifi tested exclusive station no no\niwlwifi:8086:51f0 tested go station no no\n* untested shared station yes no\n')
        env = dict(os.environ, CONF=str(conf), PROFILES=str(profiles))
        script = '''set -u
cat() { case "$1" in */vendor) echo 0x8086;; */device) echo "$DEVICE";; *) command cat "$@";; esac; }
''' + function + '\nload_profile iwlwifi wlan-test; echo "$PROF_MODE"'
        def mode(device):
            p = subprocess.run(['bash', '-c', script], env=dict(env, DEVICE=device), capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stderr)
            return p.stdout.strip()
        self.assertEqual(mode('0x51f0'), 'go')
        self.assertEqual(mode('0x1234'), 'exclusive')
        (conf / 'owl-profiles').write_text('iwlwifi tested exclusive station no no\n')
        self.assertEqual(mode('0x51f0'), 'exclusive')

    def test_status_quotes_multiline_error_as_json(self):
        function = SOURCE[SOURCE.index('cmd_status()'):SOURCE.index('# ---------------------------------------------------------------------- probe')]
        reason = 'iw: "bad"\nsecond line\\tail'
        (self.run / 'reason').write_text(reason)
        p = subprocess.run(['bash', '-c', 'visible() { return 1; };\n' + function + '\ncmd_status --json'],
                           env=dict(os.environ, RUN=str(self.run)), capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads(p.stdout)['reason'], reason)
        # omdrop's shell consumers require compact booleans.
        self.assertIn('"visible":false', p.stdout)
        self.assertIn('"rx_proven":false', p.stdout)

    def test_collected_service_counts_as_stopped(self):
        function = SOURCE[SOURCE.index('connected_stop_service()'):SOURCE.index('connected_start()')]
        for state, expected in (('not-found', 0), ('loaded', 1)):
            script = 'systemctl() { [ "$1" = stop ] && return 5; echo "$LOAD"; }\n' + function + '\nconnected_stop_service'
            p = subprocess.run(['bash', '-c', script], env=dict(os.environ, GO_UNIT='test.service', LOAD=state))
            self.assertEqual(p.returncode, expected)

    def test_start_uses_owned_service_and_has_no_station_mutations(self):
        function = SOURCE[SOURCE.index('connected_start()'):SOURCE.index('\nuntested_hint()')]
        lib = self.root / 'lib'; lib.mkdir()
        for name in ('awdl-go', 'connected-radio.py'):
            (lib / name).touch(); (lib / name).chmod(0o755)
        env = dict(os.environ, RUN=str(self.run), LIB=str(lib), OWL_LOG=str(self.run / 'owl.log'))
        script = '''set -u
GO=omdrop-test-go; MON=omdrop-test-mon; IF=omdrop-test-if; GO_UNIT=omdrop-owl-go.service; drv=iwlwifi
log() { :; }; die() { echo "$*" >&2; exit 4; }
systemctl() { echo "systemctl $*" >> "$RUN/calls"; }
systemd-run() { echo "systemd-run $*" >> "$RUN/calls"; touch "$RUN/go-ready"; }
''' + function + '\nconnected_start wlan-test 60; cat "$RUN/calls"'
        p = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('ExecStopPost=/usr/bin/python3', p.stdout)
        self.assertIn('KillMode=control-group', p.stdout)
        self.assertNotIn('disconnect', p.stdout)
        self.assertNotIn('modprobe', p.stdout)


if __name__ == '__main__':
    unittest.main()
