from contextlib import contextmanager
import sys


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
