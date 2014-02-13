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
from butterfly import url, Route, utils

ioloop = tornado.ioloop.IOLoop.instance()

server = utils.User()
daemon = utils.User(name='daemon')


def motd(socket, caller, callee):
    return (
'''
B                   `         '
   ;,,,             `       '             ,,,;
   `Y888888bo.       :     :       .od888888Y'
     8888888888b.     :   :     .d8888888888      AWelcome to RbutterflyB
     88888Y'  `Y8b.   `   '   .d8Y'  `Y88888
    j88888  R.db.B  Yb. '   ' .dY  R.db.B  88888k     AServer runnging as G%rB
      `888  RY88YB    `b ( ) d'    RY88YB  888'
       888b  R'"B        ,',        R"'B  d888        AConnecting to:B
      j888888bd8gf"'   ':'   `"?g8bd888888k         AHost: G%sB
        R'Y'B   .8'     d' 'b     '8.   R'Y'X           AUser: G%rB
         R!B   .8' RdbB  d'; ;`b  RdbB '8.   R!B
            d88  R`'B  8 ; ; 8  R`'B  88b             AFrom:B
           d888b   .g8 ',' 8g.   d888b              AHost: G%sB
          :888888888Y'     'Y888888888:             AUser: G%rB
          '! 8888888'       `8888888 !'
             '8Y  R`Y         Y'B  Y8'
R              Y                   Y
              !                   !X

'''
        .replace('B', '\x1b[34;1m')
        .replace('G', '\x1b[32;1m')
        .replace('R', '\x1b[37;1m')
        .replace('A', '\x1b[37;0m')
        .replace('X', '\x1b[0m')
        .replace('\n', '\r\n')
        % (
            server,
            '%s:%d' % (socket.remote_addr, socket.remote_port),
            callee,
            '%s:%d' % (socket.local_addr, socket.local_port),
            caller or '?'))


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
        while self.callee is None:
            user = input('login: ')
            try:
                self.callee = utils.User(name=user)
            except:
                print('User %s not found' % user)

        try:
            os.chdir(self.path or self.callee.dir)
        except:
            pass

        env = os.environ
        env.update(self.socket.env)

        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "butterfly"
        env["HOME"] = self.callee.dir
        env["SHELL"] = self.callee.shell
        env["LOCATION"] = "http://%s:%d/" % (
            tornado.options.options.host, tornado.options.options.port)
        env["PATH"] = '%s:%s' % (os.path.abspath(os.path.join(
            os.path.dirname(__file__), '..', 'bin')), env.get("PATH"))
        args = ['butterfly']

        if self.socket.local:
            # All users are the same -> launch shell
            if self.caller == self.callee and server == self.callee:
                os.execvpe(
                    tornado.options.options.shell or self.callee.shell,
                    args, env)
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

        args.append('-p')
        if tornado.options.options.shell:
            args.append('-s')
            args.append(tornado.options.options.shell)
        args.append(self.callee.name)
        os.execvpe('/bin/su', args, env)

    def communicate(self):
        self.log.debug('Adding handler')
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
        self.socket = utils.Socket(self.ws_connection.stream.socket)
        self.set_nodelay(True)
        self.log.info('Websocket opened %r' % self.socket)
        self.path = path
        self.user = user.decode('utf-8') if user else None
        self.caller = self.callee = None
        if self.socket.local:
            self.caller = utils.User(uid=self.socket.uid)
        else:
            # We don't know uid is on the other machine
            pass

        if self.user:
            try:
                self.callee = utils.User(name=self.user)
            except LookupError:
                print('User %s not found' % self.user)
                self.callee = None

        # If no user where given and we are local, keep the same user
        # as the one who opened the socket
        # ie: the one openning a terminal in borwser
        if not self.callee and not self.user and self.socket.local:
            self.callee = self.caller
        self.write_message(motd(self.socket, self.caller, self.callee))
        self.pty()

    def on_message(self, message):
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
                self.log.info('READ>%r' % read)
                self.write_message('DIE')
                return

            self.log.info('READ>%r' % read)
            self.write_message(read.decode('utf-8', 'replace'))

        if events & ioloop.ERROR:
            self.log.info('Closing due to ioloop fd handler error')
            ioloop.remove_handler(self.fd)

            # Terminated
            self.on_close()
            self.close()

    def on_close(self):
        if self.pid == 0:
            self.log.warning('pid is 0')
            return
        try:
            self.writer.write('')
            self.writer.flush()
        except OSError:
            self.log.warning('closing term fail', exc_info=True)
        try:
            os.close(self.fd)
        except OSError:
            self.log.warning('closing fd fail', exc_info=True)
        try:
            os.waitpid(self.pid, 0)
        except OSError:
            self.log.warning('waitpid fail', exc_info=True)
        self.log.info('Websocket closed')
