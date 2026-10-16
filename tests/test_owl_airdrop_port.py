"""Build tests/owl_airdrop_port.c against OWL's sources, patched, under AddressSanitizer."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
OWL = ROOT / 'upstream/owl'  # checked out and patched by tools/build-owl.sh

class AirdropPortTests(unittest.TestCase):
    def test_srv_port_is_read_from_the_service_response_tlv(self):
        if not (OWL / 'radiotap/radiotap.c').exists():
            self.skipTest('no patched OWL in upstream/owl: run `just build` first')
        cc = shutil.which('cc')
        if not cc:
            self.skipTest('no C compiler')
        with tempfile.TemporaryDirectory() as tmp:
            binary = Path(tmp) / 'owl_airdrop_port'
            subprocess.run([cc, '-std=gnu11', '-g', '-fsanitize=address', '-fno-omit-frame-pointer',
                            '-Wno-address-of-packed-member',
                            '-I', OWL / 'src', '-I', OWL / 'radiotap',
                            ROOT / 'tests/owl_airdrop_port.c', *sorted((OWL / 'src').glob('*.c')),
                            OWL / 'radiotap/radiotap.c', '-o', binary, '-lm'],
                           check=True, capture_output=True, text=True)
            run = subprocess.run([binary], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)

if __name__ == '__main__':
    unittest.main()
