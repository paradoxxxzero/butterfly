from contextlib import contextmanager


@contextmanager
def html():
    print('\x1bP;HTML|')
    yield
    print('\x1bP')


@contextmanager
def image(mime='image'):
    print('\x1bP;IMAGE|%s;' % mime)
    yield
    print('\x1bP')


@contextmanager
def prompt():
    print('\x1bP;PROMPT|')
    yield
    print('\x1bP')


@contextmanager
def text():
    print('\x1bP;TEXT|')
    yield
    print('\x1bP')
