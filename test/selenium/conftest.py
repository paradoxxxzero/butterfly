from selenium import webdriver
from pytest import fixture
from time import sleep
from multiprocessing import Process, active_children, Lock
from signal import signal, SIGUSR1, SIGKILL
import atexit
import os
import re
import sys
try:
    from wdb.ext import add_w_builtin
    add_w_builtin()
except ImportError:
    pass

display = None
fs_path = {}


def pytest_report_teststatus(report):
    try:
        browser = re.search('(\[.*\])', report.nodeid).groups()[0]
    except:
        return

    if browser not in fs_path:
        fs_path[browser] = [report.fspath]
        sys.stdout.write('\t' + browser + '\t')

    elif report.fspath not in fs_path[browser]:
        fs_path[browser].append(report.fspath)
        sys.stdout.write('\t' + browser + '\t')

if not os.environ.get('SELENIUM_BROWSERS_VISIBLE'):
    from pyvirtualdisplay import Display
    display = Display(visible=0, size=(1440, 900))
    display.start()


class App(Process):
    def __init__(self):
        # self.parent_pid = os.getpid()
        super(App, self).__init__()
        self.lock = Lock()
        self.start()

    def run(self):
        from http.server import HTTPServer
        old_serve_forever = HTTPServer.serve_forever
        print('Acquire lock')
        l = self.lock
        l.acquire()

        # Inform parent that we are ready
        def new_serve_forever(self):
            print('Release lock')
            l.release()
            # from signal import SIGUSR1
            # os.kill(ppid, SIGUSR1)
            old_serve_forever(self)

        HTTPServer.serve_forever = new_serve_forever

        from app import app
        app.run(
            debug=True,
            threaded=True,
            use_reloader=False,
            port=29013)

    def wait_for_lock(self):
        ok = self.lock.acquire(20)
        if not ok:
            raise RuntimeError(
                'Impossible to get app lock.'
                ' App may not have been started successfuly')
        self.lock.release()


@fixture(scope='session')
def app(request):
    app = App()

    def end_app():
        app.terminate()

    request.addfinalizer(end_app)
    return app

@fixture(scope='session', params=('firefox', 'chrome'))
def s(request, app): # s = Selenium Browser
    browser = getattr(webdriver, request.param.capitalize())()

    def close_browser():
        browser.close()

    request.addfinalizer(close_browser)
    app.wait_for_lock()
    return browser


@atexit.register
def quit():
    if display:
        display.stop()
