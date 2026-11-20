"""Rich presentation; literal output preserves commands, IDs and policies."""
from contextlib import contextmanager
from time import monotonic
try:
    from rich.console import Console
    from rich.progress import Progress, SpinnerColumn, TextColumn, TimeElapsedColumn
    from rich.text import Text
except ImportError:
    raise SystemExit('Install the dependencies listed in the interactive setup requirements.txt.') from None


class Display:
    def __init__(self, console=None):
        self.console = console or Console(markup=False, highlight=False)
        self.progress = None
        self.depth = 0

    def __call__(self, value):
        text = str(value)
        clean = text.lstrip()
        style = None
        if clean.startswith(('ERROR:', 'Stopped:')):
            style = 'bold red'
        elif clean.startswith(('PASS:', 'Done:')):
            style = 'green'
        elif clean.startswith(('Current:', 'Current/default:')):
            style = 'cyan'
        # out() adds no wrapping, markup, borders or line numbers to copyable data.
        self.console.out(text, style=style, highlight=False)

    def heading(self, title, step=False):
        self.console.print('\n' if step else '')
        self.console.rule(Text(title, style='bold cyan' if step else 'bold'),
                          align='left', characters='─' if self.console.is_terminal else '-',
                          style='cyan' if step else 'dim')
        self.console.print()

    @contextmanager
    def operation(self, label, interval=10):
        if not self.console.is_terminal or self.console.is_dumb_terminal:
            from progress import operation
            # A plain callback retains periodic log feedback without an animation.
            with operation(lambda text: self(text), label, interval):
                yield
            return
        started = monotonic()
        if self.depth == 0:
            self.progress = Progress(SpinnerColumn(), TextColumn('{task.description}'),
                                     TimeElapsedColumn(), console=self.console,
                                     transient=True, refresh_per_second=8)
            self.progress.start()
        self.depth += 1
        task = self.progress.add_task(Text(label), total=None)
        outcome = 'Done'
        try:
            yield
        except BaseException:
            outcome = 'Stopped'
            raise
        finally:
            self.progress.remove_task(task)
            self.depth -= 1
            if self.depth == 0:
                self.progress.stop()
                self.progress = None
            self(f'{outcome}: {label} ({monotonic() - started:.1f}s)')
