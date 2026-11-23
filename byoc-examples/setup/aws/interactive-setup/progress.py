"""Operation feedback delegated to Rich, with plain-text log support."""
from contextlib import contextmanager
from threading import Event, Thread
from time import monotonic


@contextmanager
def operation(show, label, interval=10):
    if hasattr(show, "operation"):
        with show.operation(label, interval):
            yield
        return
    started = monotonic()
    stopped = Event()
    show(f'{label}...')

    def heartbeat():
        while not stopped.wait(interval):
            show(f'Still working: {label} ({monotonic() - started:.0f}s)')

    worker = Thread(target=heartbeat, daemon=True)
    worker.start()
    outcome = 'Done'
    try:
        yield
    except BaseException:
        outcome = 'Stopped'
        raise
    finally:
        stopped.set()
        worker.join()
        show(f'{outcome}: {label} ({monotonic() - started:.1f}s)')


class ReportingAWS:
    """Report every read, including checks which do not use a resource list."""
    def __init__(self, client, show):
        self.client, self.show = client, show
        self.region = client.region

    def read(self, service, action, *args):
        # Never display arguments, response bodies or credentials in status lines.
        verb = 'Searching' if action.startswith(('list-', 'describe-')) else 'Checking'
        label = f'{verb}: {service} / {action}'
        with operation(self.show, label):
            return self.client.read(service, action, *args)
