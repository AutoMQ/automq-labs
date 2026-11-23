from pathlib import Path
import sys
from threading import Event
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from progress import operation, ReportingAWS
from setup import UI


class ProgressTests(unittest.TestCase):
    def test_waiting_and_completion(self):
        output, waiting = [], Event()
        def show(text):
            output.append(text)
            if text.startswith('Still working:'):
                waiting.set()
        with operation(show, 'Checking resource', interval=0.01):
            self.assertTrue(output[0].startswith('Checking resource'))
            self.assertTrue(waiting.wait(1))
        self.assertTrue(output[-1].startswith('Done:'))

    def test_error_stops_without_exposing_arguments(self):
        output = []
        class Client:
            region = 'us-east-1'
            def read(self, *args):
                raise ValueError('failure')
        with self.assertRaises(ValueError):
            ReportingAWS(Client(), output.append).read('iam', 'get-role', 'SECRET')
        self.assertTrue(output[-1].startswith('Stopped:'))
        self.assertNotIn('SECRET', ''.join(output))

    def test_fixed_choices_hide_refresh(self):
        output = []
        ui = UI(lambda _: '1', output.append)
        self.assertEqual(ui.choose('Instance type', lambda: ['r6i.large'], str, str, refresh=False), 'r6i.large')
        self.assertNotIn('r. Refresh', output)
        self.assertIn('b. Back', output)

class RichDisplayTests(unittest.TestCase):
    def test_redirected_output_is_literal_and_has_no_controls(self):
        import io
        from rich.console import Console
        from display import Display
        stream = io.StringIO()
        display = Display(Console(file=stream, force_terminal=False, width=20))
        payload = 'aws example --value "[red]' + 'x' * 100 + '[/red]"'
        display(payload)
        display('{"Resource": ["arn:aws:s3:::bucket/*"]}')
        with operation(display, 'Checking config'):
            pass
        output = stream.getvalue()
        self.assertIn(payload + '\n', output)
        self.assertIn('{"Resource": ["arn:aws:s3:::bucket/*"]}\n', output)
        self.assertNotIn('\x1b', output)
        self.assertIn('Done: Checking config', output)

    @patch.dict("os.environ", {"TERM": "xterm-256color"})
    def test_terminal_nested_progress_cleans_up_on_interrupt(self):
        import io
        from rich.console import Console
        from display import Display
        stream = io.StringIO()
        from unittest.mock import patch
        with patch.dict("os.environ", {"TERM": "xterm-256color"}):
            display = Display(Console(file=stream, force_terminal=True, width=80))
        with self.assertRaises(KeyboardInterrupt):
            with operation(display, 'Checking Role'):
                with operation(display, 'Searching Profiles'):
                    raise KeyboardInterrupt()
        self.assertIsNone(display.progress)
        self.assertEqual(display.depth, 0)
        self.assertIn('Stopped:', stream.getvalue())
        # Cursor is restored after the live display closes.
        self.assertIn('\x1b[?25h', stream.getvalue())


class CommandViewTests(unittest.TestCase):
    def test_command_stays_visible_until_refresh_and_back_returns_to_list(self):
        import tempfile
        for action, expected_fetches in [('r', 2), ('b', 1)]:
            with self.subTest(action=action), tempfile.TemporaryDirectory() as temp:
                path = Path(temp) / 'prepare.sh'
                path.write_text('echo "prepare resource"\n')
                output, calls = [], []
                answers = iter(['c', 'invalid', action, '1'])
                def read(_):
                    value = next(answers)
                    if value == 'invalid':
                        self.assertEqual(output.count('Resources'), 1)
                        self.assertIn('echo "prepare resource"', output)
                    return value
                def fetch():
                    calls.append(1)
                    return ['resource']
                result = UI(read, output.append).choose('Resources', fetch, str, str, prepare=lambda: path)
                self.assertEqual(result, 'resource')
                self.assertEqual(len(calls), expected_fetches)
                self.assertEqual(output.count('echo "prepare resource"'), 1)
