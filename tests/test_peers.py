"""Run the helper's `peers` over made-up OWL logs, never the real radio."""
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'userspace/omdrop-discoverable').read_text()
PEERS = SOURCE[SOURCE.index('cmd_peers()'):SOURCE.index('# ---------------------------------------------------------------------- probe')]

class PeersTests(unittest.TestCase):
    def peers(self, log):
        with tempfile.TemporaryDirectory() as tmp:
            owl_log = Path(tmp, 'owl.log')
            owl_log.write_text(log)
            script = f'set -uo pipefail\nOWL_LOG={owl_log}\ndie() {{ echo "$1" >&2; exit "$2"; }}\n' + PEERS + '\ncmd_peers\n'
            result = subprocess.run(['bash', '-c', script], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            return sorted(result.stdout.splitlines())

    def test_peers_are_the_added_and_not_removed(self):
        self.assertEqual(self.peers(
            '11:25:21 INFO : add peer 86:8:4:8a:2b:f4 (iPad)\n'
            '11:25:22 INFO : add peer 42:a:9b:62:8d:9e (iPhone)\n'
            '11:25:30 INFO : remove peer 42:a:9b:62:8d:9e (iPhone)\n'),
            ['86:08:04:8a:2b:f4 rssi=?'])

    def test_no_peer_yet_is_an_empty_list(self):
        self.assertEqual(self.peers('11:25:20 INFO : started\n'), [])

    def test_announced_port_is_reported_until_the_peer_is_removed(self):
        self.assertEqual(self.peers(
            '11:25:20 INFO : peer aa:50:8e:d9:c9:ce airdrop port 35471\n'
            '11:25:21 INFO : add peer aa:50:8e:d9:c9:ce ()\n'
            '11:25:22 INFO : add peer 86:8:4:8a:2b:f4 (iPad)\n'
            '11:25:23 INFO : peer 42:a:9b:62:8d:9e airdrop port 43323\n'
            '11:25:24 INFO : add peer 42:a:9b:62:8d:9e ()\n'
            '11:25:25 INFO : peer 42:a:9b:62:8d:9e airdrop port 43324\n'
            '11:25:30 INFO : remove peer 42:a:9b:62:8d:9e ()\n'
            # Announced after the peer was added, which is how it was captured.
            '11:25:31 INFO : add peer 7a:c1:d0:ea:9f:1e ()\n'
            '11:25:32 INFO : peer 7a:c1:d0:ea:9f:1e airdrop port 35529\n'
            # Heard, but never a peer.
            '11:25:33 INFO : peer 16:1b:8f:82:45:f9 airdrop port 40000\n'),
            ['7a:c1:d0:ea:9f:1e rssi=? port=35529', '86:08:04:8a:2b:f4 rssi=?',
             'aa:50:8e:d9:c9:ce rssi=? port=35471'])

if __name__ == '__main__':
    unittest.main()
