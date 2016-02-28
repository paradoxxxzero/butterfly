from contextlib import contextmanager
from butterfly.utils import ansi_colors as colors
import sys
import termios
import tty


@contextmanager
def html():
    sys.stdout.write('\x1bP;HTML|')
    yield
    sys.stdout.write('\x1bP')
    sys.stdout.flush()


@contextmanager
def image(mime='image'):
    sys.stdout.write('\x1bP;IMAGE|%s;' % mime)
    yield
    sys.stdout.write('\x1bP\n')
    sys.stdout.flush()


@contextmanager
def prompt():
    sys.stdout.write('\x1bP;PROMPT|')
    yield
    sys.stdout.write('\x1bP')
    sys.stdout.flush()


@contextmanager
def text():
    sys.stdout.write('\x1bP;TEXT|')
    yield
    sys.stdout.write('\x1bP')
    sys.stdout.flush()


def geolocation():
    sys.stdout.write('\x1b[?99n')
    sys.stdout.flush()

    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(sys.stdin.fileno())
        rv = sys.stdin.read(1)
        if rv != '\x1b':
            raise
        rv = sys.stdin.read(1)
        if rv != '[':
            raise
        rv = sys.stdin.read(1)
        if rv != '?':
            raise

        loc = ''
        while rv != 'R':
            rv = sys.stdin.read(1)
            if rv != 'R':
                loc += rv
    except:
        return
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    if not loc or ';' not in loc:
        return
    return tuple(map(float, loc.split(';')))
