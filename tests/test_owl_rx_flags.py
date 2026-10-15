"""Build tests/owl_rx_flags.c against OWL's sources, patched, under AddressSanitizer."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
OWL = ROOT / 'upstream/owl'  # checked out and patched by tools/build-owl.sh

class RxFlagsTests(unittest.TestCase):
    def test_frame_without_flags_is_not_dropped(self):
        if not (OWL / 'radiotap/radiotap.c').exists():
            self.skipTest('no patched OWL in upstream/owl: run `just build` first')
        cc = shutil.which('cc')
        if not cc:
            self.skipTest('no C compiler')
        with tempfile.TemporaryDirectory() as tmp:
            binary = Path(tmp) / 'owl_rx_flags'
            subprocess.run([cc, '-std=gnu11', '-g', '-fsanitize=address', '-fno-omit-frame-pointer',
                            '-Wno-address-of-packed-member',
                            '-I', OWL / 'src', '-I', OWL / 'radiotap',
                            ROOT / 'tests/owl_rx_flags.c', *sorted((OWL / 'src').glob('*.c')),
                            OWL / 'radiotap/radiotap.c', '-o', binary, '-lm'],
                           check=True, capture_output=True, text=True)
            # The fake stack ASan may give awdl_rx's locals would hide the stack the test dirties.
            run = subprocess.run([binary], capture_output=True, text=True,
                                 env=dict(os.environ, ASAN_OPTIONS='detect_stack_use_after_return=0'))
            self.assertEqual(run.returncode, 0, run.stderr)

if __name__ == '__main__':
    unittest.main()
