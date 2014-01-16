import pty
import os
import io
import sys
import struct
import signal
import fcntl
import termios
import tornado.websocket
import tornado.process
import tornado.ioloop
from subprocess import Popen
from app import url, Route

ioloop = tornado.ioloop.IOLoop.instance()


@url(r'/')
class Index(Route):
    def get(self):
        return self.render('index.html')


@url(r'/ws')
class TermWebSocket(Route, tornado.websocket.WebSocketHandler):

    def open(self):
        self.log.info('Websocket opened')

        pid, fd = pty.fork()
        if pid == 0:
            # Child
            try:
                fd_list = [int(i) for i in os.listdir('/proc/self/fd')]
            except OSError:
                fd_list = range(256)
            # Close all file descriptors other than
            # stdin, stdout, and stderr (0, 1, 2)
            for i in [i for i in fd_list if i > 2]:
                try:
                    os.close(i)
                except OSError:
                    pass
            env = os.environ
            env["TERM"] = "xterm"
            env["COLORTERM"] = "wsterm"
            command = os.getenv('SHELL')
            env["SHELL"] = command[0]
            p = Popen(command, env=env)
            p.wait()
            self.log.info('Exiting...')
            sys.exit(0)
        else:
            self.pid = pid
            self.fd = fd
            self.log.debug('Adding handler')
            fcntl.fcntl(fd, fcntl.F_SETFL, os.O_NONBLOCK)

            # Set the size of the terminal window:
            s = struct.pack("HHHH", 80, 80, 0, 0)
            fcntl.ioctl(fd, termios.TIOCSWINSZ, s)

            self.reader = io.open(
                fd,
                'rt',
                buffering=1024,
                newline="",
                encoding='UTF-8',
                closefd=False,
                errors='handle_special'
            )
            self.writer = io.open(
                fd,
                'wt',
                buffering=1024,
                newline="",
                encoding='UTF-8',
                closefd=False
            )
            ioloop.add_handler(fd, self.shell, ioloop.READ)

    def on_message(self, message):
        self.log.info('WRIT<%s' % message)
        self.writer.write(message)
        self.writer.flush()

    def shell(self, fd, events):
        if events & ioloop.READ:
            self.log.info('shell %d: %d' % (fd, events))
            try:
                read = self.reader.read()
            except IOError:
                self.log.info('READ>%s' % read)
                self.write_message('Exited')
                return

            self.log.info('READ>%s' % read)
            self.write_message(read)

    def on_close(self):
        self.writer.write('')
        os.close(self.fd)
        os.waitpid(self.pid, 0)
        self.log.info('Websocket closed')
