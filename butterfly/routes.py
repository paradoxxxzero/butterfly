# *-* coding: utf-8 *-*
# This file is part of butterfly
#
# butterfly Copyright (C) 2014  Florian Mounier
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import pwd
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
from butterfly import url, Route

ioloop = tornado.ioloop.IOLoop.instance()


@url(r'/(?:user/(.+))?/?(?:wd/(.+))?')
class Index(Route):
    def get(self, user, path):
        return self.render('index.html')


@url(r'/ws(?:/user/([^/]+))?/?(?:/wd/(.+))?')
class TermWebSocket(Route, tornado.websocket.WebSocketHandler):

    def pty(self):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            # Child
            try:
                os.closerange(3, 256)
            except:
                pass

            env = {}
            env["TERM"] = "xterm-256color"
            env["COLORTERM"] = "butterfly"
            env["LOCATION"] = "http://%s:%d/" % (
                tornado.options.options.host, tornado.options.options.port)
            env["BUTTERFLY_DIR"] = os.getcwd()
            env["SHELL"] = self.pw.pw_shell or '/bin/sh'
            # env["PATH"] = os.path.abspath(os.path.join(
                # os.path.dirname(__file__), '..', 'bin'))
            try:
                os.chdir(self.path or self.pw.pw_dir)
            except:
                pass
            shell = tornado.options.options.command or self.pw.pw_shell
            args = ['-i', '-l']

            # All users are the same -> launch shell
            if self.is_local and (
                    self.uid == self.pw.pw_uid and self.uid == os.getuid()):
                os.execvpe(shell, args, env)

            if not (self.is_local and os.getuid() == 0 and
                    self.uid == self.pw.pw_uid):
                # If user is not the same, get a password prompt
                os.setuid(self.uid)

            if tornado.options.options.command:
                args.append('-s')
                args.append('%s' % tornado.options.options.command)
            args.append(self.pw.pw_name)
            print('Logging: %s@%s' % (self.pw.pw_name, self.bind))
            os.execvpe('/bin/su', args, env)
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

    @property
    def is_local(self):
        return self.bind == '127.0.0.1'

    @property
    def pw(self):
        if self.user:
            return pwd.getpwnam(self.user)

        if self.uid and self.is_local:
            return pwd.getpwuid(self.uid)
        # ?? Returning first user
        return pwd.getpwuid(1000)

    @property
    def uid(self):
        try:
            with open('/proc/net/tcp') as k:
                lines = k.readlines()
            for line in lines:
                # Look for local address with peer port
                if line.split()[1] == '0100007F:%X' % self.port:
                    # We got the user
                    return int(line.split()[7])
        except:
            pass
        try:
            with open('/proc/net/tcp6') as k:
                lines = k.readlines()
            for line in lines:
                # Look for local address with peer port
                if line.split()[1] == (
                        '00000000000000000000000001000000:%X' % self.port):
                    # We got the user
                    return int(line.split()[7])
        except:
            pass

    def open(self, user, path):
        self.bind, self.port = (
            self.ws_connection.stream.socket.getpeername()[:2])
        self.log.info('Websocket opened for %s:%d' % (self.bind, self.port))
        self.set_nodelay(True)
        self.user = user.decode('utf-8') if user else None
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
