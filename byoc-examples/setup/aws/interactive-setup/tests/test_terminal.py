import hashlib
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import tempfile
import termios
import time
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT))
from core import SetupError
from setup import UI, Wizard


class TerminalTests(unittest.TestCase):
    def test_multiline_paste_preserves_all_lines_without_echo(self):
        command = 'sudo docker run -d \\\n  -e CONFIG=' + 'S' * 1200 + ' \\\n  -e CLOUD_PROVIDER=aws \\\n  automq.azurecr.io/automq/automq-byoc-console:8.4.7-aws'
        master, slave = pty.openpty()
        original = termios.tcgetattr(slave)
        code = ('import sys,hashlib; sys.path.insert(0,sys.argv[1]); '
                'from setup import read_home_command; '
                'v=read_home_command(); print("DIGEST="+hashlib.sha256(v.encode()).hexdigest())')
        process = subprocess.Popen([sys.executable, '-c', code, str(SCRIPT)], stdin=slave, stdout=slave, stderr=slave)
        received = b''
        sent = False
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    received += os.read(master, 65536)
                if not sent and b'> ' in received:
                    os.write(master, (command + '\n\n').encode())
                    sent = True
                if process.poll() is not None:
                    while select.select([master], [], [], 0)[0]:
                        received += os.read(master, 65536)
                    break
            self.assertEqual(process.poll(), 0, received.decode())
            self.assertIn(('DIGEST='+hashlib.sha256(command.encode()).hexdigest()).encode(), received)
            self.assertNotIn(b'CONFIG=', received)
            restored = termios.tcgetattr(slave)
            # macOS may set the kernel-maintained PENDIN bit after mode changes.
            restored[3] &= ~getattr(termios, 'PENDIN', 0)
            original[3] &= ~getattr(termios, 'PENDIN', 0)
            self.assertEqual(restored, original)
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
            os.close(master)
            os.close(slave)

    def test_bad_command_retries_paste_without_reselecting_console(self):
        output, prompts = [], []
        def read(prompt):
            prompts.append(prompt)
            return '1'
        with tempfile.TemporaryDirectory() as directory, \
             patch('setup.read_home_command', side_effect=['incomplete', 'complete']) as paste, \
             patch('setup.parse_home', side_effect=[SetupError('Missing image'), {'region': 'us-east-1'}]):
            wizard = Wizard(Path(directory)/'out', UI(read, output.append), lambda _: type("Client", (), {"region": "us-east-1"})(),
                            home_reader=lambda _: {'available': True})
            wizard.console_choice()
            wizard.home()
            self.assertEqual(len(prompts), 1)
            self.assertEqual(paste.call_count, 2)
            self.assertEqual(wizard.state['console_mode'], 'new')
            self.assertTrue(any('ERROR: Missing image' in line for line in output))


if __name__ == '__main__':
    unittest.main()
