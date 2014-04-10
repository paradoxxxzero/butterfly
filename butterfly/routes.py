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
import sys
import signal
from butterfly import url, Route, utils, __version__

ioloop = tornado.ioloop.IOLoop.instance()

server = utils.User()
daemon = utils.User(name='daemon')

# Python 2 backward compatibility
try:
    input = raw_input
except NameError:
    pass


def u(s):
    if sys.version_info[0] == 2:
        return s.decode('utf-8')
    return s


def motd(socket):
    return (
'''
B                   `         '
   ;,,,             `       '             ,,,;
   `Y888888bo.       :     :       .od888888Y'
     8888888888b.     :   :     .d8888888888
     88888Y'  `Y8b.   `   '   .d8Y'  `Y88888
    j88888  R.db.B  Yb. '   ' .dY  R.db.B  88888k
      `888  RY88YB    `b ( ) d'    RY88YB  888'
       888b  R'"B        ,',        R"'B  d888
      j888888bd8gf"'   ':'   `"?g8bd888888k
        R'Y'B   .8'     d' 'b     '8.   R'Y'X
         R!B   .8' RdbB  d'; ;`b  RdbB '8.   R!B
            d88  R`'B  8 ; ; 8  R`'B  88b             Rbutterfly Zv %sB
           d888b   .g8 ',' 8g.   d888b
          :888888888Y'     'Y888888888:           AConnecting to:B
          '! 8888888'       `8888888 !'              G%sB
             '8Y  R`Y         Y'B  Y8'
R              Y                   Y               AFrom:R
              !                   !                  G%sX

'''
        .replace('B', '\x1b[34;1m')
        .replace('G', '\x1b[32;1m')
        .replace('R', '\x1b[37;1m')
        .replace('Z', '\x1b[33;1m')
        .replace('A', '\x1b[37;0m')
        .replace('X', '\x1b[0m')
        .replace('\n', '\r\n')
        % (__version__,
           '%s:%d' % (socket.local_addr, socket.local_port),
           '%s:%d' % (socket.remote_addr, socket.remote_port)))


@url(r'/(?:user/(.+))?/?(?:wd/(.+))?')
class Index(Route):
    def get(self, user, path):
        return self.render('index.html')


@url(r'/ws(?:/user/([^/]+))?/?(?:/wd/(.+))?')
class TermWebSocket(Route, tornado.websocket.WebSocketHandler):

    def pty(self):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            try:
                os.closerange(3, 256)
            except:
                pass
            self.shell()
        else:
            self.communicate()

    def shell(self):
        if not tornado.options.options.prompt_login:
            self.callee = utils.User(self.caller)
        if self.callee is None:
            user = input('login: ')
            try:
                self.callee = utils.User(name=user)
            except:
                self.callee = utils.User(name='nobody')

        try:
            os.chdir(tornado.options.options.wd or self.path or self.callee.dir)
        except:
            pass

        env = os.environ
        env.update(self.socket.env)
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "butterfly"
        env["HOME"] = self.callee.dir
        env["LOCATION"] = "http%s://%s:%d/" % (
            "s" if not tornado.options.options.unsecure else "",
            tornado.options.options.host, tornado.options.options.port)
        env["PATH"] = '%s:%s' % (os.path.abspath(os.path.join(
            os.path.dirname(__file__), '..', 'bin')), env.get("PATH"))

        env.pop("VIRTUAL_ENV", None)    # If the server is running from virtualenv
        env.pop("PS1", None)            # then remove the prefix (virtenv) and show the regular one [user@comp ~]

        if tornado.options.options.load_script:
            args = tornado.options.options.load_script.split(" ")
        elif tornado.options.options.shell:
            args = [tornado.options.options.shell]
        else:
            args = [self.callee.shell, "-i"]

        if self.socket.local or not tornado.options.options.prompt_login:
            # All users are the same -> launch shell
            if (self.caller == self.callee and server == self.callee) or not tornado.options.options.prompt_login:
                os.execvpe(args[0], args, env)
                # This process has been replaced
                return

            if server.root:
                if self.callee != self.caller:
                    # Force password prompt by dropping rights
                    # to the daemon user
                    os.setuid(daemon.uid)
        else:
            # We are not local so we should always get a password prompt
            if server.root:
                if self.callee == daemon:
                    # No logging from daemon
                    sys.exit(1)
                os.setuid(daemon.uid)

        if os.path.exists('/usr/bin/su'):
            args = ['/usr/bin/su']
        else:
            args = ['/bin/su']

        if sys.platform == 'linux':
            args.append('-p')
            if tornado.options.options.load_script:
                args.append('-c')
                args.append(tornado.options.options.load_script)
            elif tornado.options.options.shell:
                args.append('-s')
                args.append(tornado.options.options.shell)
        args.append(self.callee.name)
        os.execvpe(args[0], args, env)

    def communicate(self):
        self.log.info('Adding handler')
        fcntl.fcntl(self.fd, fcntl.F_SETFL, os.O_NONBLOCK)

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
        ioloop.add_handler(
            self.fd, self.shell_handler, ioloop.READ | ioloop.ERROR)

    def open(self, user, path):
        if self.request.headers['Origin'] != 'http%s://%s' % (
                "s" if not tornado.options.options.unsecure else "",
                self.request.headers['Host']):
            self.log.warning(
                'Unauthorized connection attempt: from : %s to: %s' % (
                    self.request.headers['Origin'],
                    self.request.headers['Host']))
            self.close()
            return

        self.socket = utils.Socket(self.ws_connection.stream.socket)
        self.set_nodelay(True)
        self.log.info('Websocket opened %r' % self.socket)
        self.path = path
        self.user = user.decode('utf-8') if user else None
        self.caller = self.callee = None
        if not tornado.options.options.unsecure:
            cert = self.request.get_ssl_certificate()
            if cert is not None:
                for field in cert['subject']:
                    if field[0][0] == 'commonName':
                        self.user = self.callee = field[0][1]

        # If local we have the user connecting
        if self.socket.local and self.socket.user is not None:
            self.caller = self.socket.user

        if self.user:
            try:
                self.callee = utils.User(name=self.user)
            except LookupError:
                self.callee = None

        # If no user where given and we are local, keep the same user
        # as the one who opened the socket
        # ie: the one openning a terminal in borwser
        if not self.callee and not self.user and self.socket.local:
            self.callee = self.caller
        self.write_message(motd(self.socket))
        self.pty()

    def on_message(self, message):
        if not hasattr(self, 'writer'):
            self.on_close()
            self.close()
            return
        if message[0] == 'R':
            cols, rows = map(int, message[1:].split(','))
            s = struct.pack("HHHH", rows, cols, 0, 0)
            fcntl.ioctl(self.fd, termios.TIOCSWINSZ, s)
            self.log.info('SIZE (%d, %d)' % (cols, rows))
        elif message[0] == 'S':
            self.log.info('WRIT<%r' % message)
            self.writer.write(message[1:])
            self.writer.flush()

    def shell_handler(self, fd, events):
        if events & ioloop.READ:
            try:
                read = self.reader.read()
            except IOError:
                read = ''

            self.log.info('READ>%r' % read)
            if len(read) != 0 and self.ws_connection:
                self.write_message(read.decode('utf-8', 'replace'))
            else:
                events = ioloop.ERROR

        if events & ioloop.ERROR:
            self.log.info('Error on fd, closing')
            # Terminated
            self.on_close()
            self.close()

    def on_close(self):
        if getattr(self, 'pid', 0) == 0:
            self.log.info('pid is 0')
            return

        try:
            os.close(self.fd)
        except Exception:
            self.log.debug('closing fd fail', exc_info=True)

        try:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        except Exception:
            self.log.debug('waitpid fail', exc_info=True)

        try:
            ioloop.remove_handler(self.fd)
        except Exception:
            self.log.debug('handler removal fail', exc_info=True)

        self.log.info('Websocket closed')
