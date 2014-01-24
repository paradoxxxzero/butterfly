import pty
import os
import io
import struct
import fcntl
import termios
import tornado.websocket
import tornado.process
import tornado.ioloop
import tornado.options
from app import url, Route

ioloop = tornado.ioloop.IOLoop.instance()


@url(r'/(?:(wd/.+))?')
class Index(Route):
    def get(self, path):
        return self.render('index.html')


@url(r'/ws(?:(/.+))?')
class TermWebSocket(Route, tornado.websocket.WebSocketHandler):

    def pty(self):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            # Child
            try:
                os.closerange(3, 256)
            except:
                pass
            env = os.environ
            env["TERM"] = "xterm-256color"
            env["COLORTERM"] = "wsterm"
            command = os.getenv('SHELL')
            env["LOCATION"] = "http://%s:%d/" % (
                tornado.options.options.host, tornado.options.options.port)
            env["WSTERMDIR"] = os.getcwd()

            env["SHELL"] = command
            env["PATH"] = "%s:%s" % (
                os.path.abspath(os.path.join(
                    os.path.dirname(__file__), '..', 'bin')), env["PATH"])
            os.chdir(self.path or os.path.expanduser("~"))
            os.execvpe(command, [''], env)
        else:
            self.log.debug('Adding handler')
            fcntl.fcntl(self.fd, fcntl.F_SETFL, os.O_NONBLOCK)

            # Set the size of the terminal window:
            s = struct.pack("HHHH", 80, 80, 0, 0)
            fcntl.ioctl(self.fd, termios.TIOCSWINSZ, s)

            def utf8_error(e):
                self.log.error(e)

            self.reader = io.open(
                self.fd,
                'rb',
                buffering=0,
                closefd=False
            )
            self.writer = io.open(
                self.fd,
                'wt',
                encoding='utf-8',
                closefd=False
            )
            ioloop.add_handler(self.fd, self.shell, ioloop.READ | ioloop.ERROR)

    def open(self, path):
        self.log.info('Websocket opened')
        self.set_nodelay(True)
        self.path = path
        self.pty()

    def on_message(self, message):
        if message.startswith('RS|'):
            message = message[3:]
            cols, rows = map(int, message.split(','))
            s = struct.pack("HHHH", rows, cols, 0, 0)
            fcntl.ioctl(self.fd, termios.TIOCSWINSZ, s)
            self.log.info('SIZE (%d, %d)' % (cols, rows))
        elif message.startswith('SH|'):
            message = message[3:]
            self.log.info('WRIT<%r' % message)
            self.writer.write(message)
            self.writer.flush()

    def shell(self, fd, events):
        if events & ioloop.READ:
            try:
                read = self.reader.read()
            except IOError:
                self.log.info('READ>%r' % read)
                self.write_message('DIE')
                return

            self.log.info('READ>%r' % read)
            self.write_message(read.decode('utf-8', 'replace'))

        if events & ioloop.ERROR:
            self.log.info('Closing due to ioloop fd handler error')
            ioloop.remove_handler(self.fd)
            # Terminated
            self.close()

    def on_close(self):
        if self.pid == 0:
            return
        try:
            self.writer.write('')
            self.writer.flush()
        except OSError:
            pass
        try:
            os.close(self.fd)
        except OSError:
            pass
        try:
            os.waitpid(self.pid, 0)
        except OSError:
            pass
        self.log.info('Websocket closed')
