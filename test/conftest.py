from selenium import webdriver
from pytest import fixture
from multiprocessing import Process, Lock, active_children
from cutter import attr_cut
from time import sleep
import atexit
import re
import os
import sys

try:
    from wdb.ext import add_w_builtin
    add_w_builtin()
except ImportError:
    pass


display = None
fs_path = {}
browsers = ['firefox', 'chrome']


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


def pytest_addoption(parser):
    parser.addoption("--display", action="store_true")
    parser.addoption("--browser", action="append")


def pytest_configure(config):
    if not config.getoption("--display"):
        from pyvirtualdisplay import Display
        display = Display(visible=0, size=(1440, 900))
        display.start()
    if config.getoption("--browser"):
        browsers[:] = config.getoption("--browser")


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
            old_serve_forever(self)

        HTTPServer.serve_forever = new_serve_forever
        os.environ['APP_TESTING'] = 'YES'
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


class ElementWrapper(object):
    def __init__(self, element):
        self.element = element

    def __getattr__(self, attr):
        if attr in self.__dict__:
            return getattr(self, attr)
        return getattr(self.element, attr)

    def find(self, selector):
        return attr_cut(
            map(ElementWrapper,
                self.element.find_elements_by_css_selector(selector)))
    __call__ = find

    def type(self, keys):
        self.clear()
        self.send_keys(keys)


class BrowserWrapper(object):

    def __init__(self, browser):
        self.browser = browser

    def __getattr__(self, attr):
        if attr in self.__dict__:
            return getattr(self, attr)
        return getattr(self.browser, attr)

    def go(self, url):
        if url.startswith('/'):
            url = url[1:]
        self.browser.get('http://localhost:29013/' + url)

    def __call__(self, selector):
        return attr_cut(
            map(ElementWrapper,
                self.browser.find_elements_by_css_selector(selector)))


@fixture(scope='session', params=browsers)
def s(request, app):  # s = Selenium Browser
    browser = getattr(webdriver, request.param.capitalize())()

    def close_browser():
        browser.close()

    request.addfinalizer(close_browser)
    app.wait_for_lock()
    return BrowserWrapper(browser)


@atexit.register
def killall():
    if display:
        display.stop()
    for child in active_children():
        os.kill(child.pid, SIGKILL)

