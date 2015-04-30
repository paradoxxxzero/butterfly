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
import string
import random
import fcntl
import termios
import tornado.web
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


@url(r'/(?:user/(.+))?/?(?:wd/(.+))?')
class Index(Route):
    def get(self, user, path):
        if not tornado.options.options.unsecure and user:
            raise tornado.web.HTTPError(400)
        return self.render('index.html')


@url(r'/style.css')
class Style(Route):

    def get(self):
        default_style = os.path.join(
            os.path.dirname(__file__), 'static', 'main.css')

        self.log.info('Getting style')
        css = utils.get_style()
        self.log.debug('Style ok')

        self.set_header("Content-Type", "text/css")

        if css:
            self.write(css)
        else:
            with open(default_style) as s:
                while True:
                    data = s.read(16384)
                    if data:
                        self.write(data)
                    else:
                        break
        self.finish()


@url(r'/ws(?:/user/([^/]+))?/?(?:/wd/(.+))?')
class TermWebSocket(Route, tornado.websocket.WebSocketHandler):

    terminals = set()

    def pty(self):
        # Make a "unique" id in 4 bytes
        self.uid = ''.join(
            random.choice(
                string.ascii_lowercase + string.ascii_uppercase +
                string.digits)
            for _ in range(4))

        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            self.determine_user()
            self.shell()
        else:
            self.communicate()

    def determine_user(self):
        if self.callee is None and (
                tornado.options.options.unsecure and
                tornado.options.options.login):
            # If callee is now known and we have unsecure connection
            user = ''
            while user == '':
                try:
                    user = input('login: ')
                except (KeyboardInterrupt, EOFError):
                    self.log.debug("Errorin login input", exc_info=True)
                    pass

            try:
                self.callee = utils.User(name=user)
            except Exception:
                self.log.debug("Can't switch to user %s" % user, exc_info=True)
                self.callee = utils.User(name='nobody')
        elif (tornado.options.options.unsecure and not
              tornado.options.options.login):
            # if login is not required, we will use the same user as
            # butterfly is executed
            self.callee = utils.User()

        assert self.callee is not None

    def shell(self):
        try:
            os.chdir(self.path or self.callee.dir)
        except Exception:
            self.log.debug(
                "Can't chdir to %s" % (self.path or self.callee.dir),
                exc_info=True)

        env = os.environ
        # If local and local user is the same as login user
        # We set the env of the user from the browser
        # Usefull when running as root
        if self.caller == self.callee:
            env.update(self.socket.env)
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "butterfly"
        env["HOME"] = self.callee.dir
        env["LOCATION"] = "http%s://%s:%d/" % (
            "s" if not tornado.options.options.unsecure else "",
            tornado.options.options.host, tornado.options.options.port)
        env["PATH"] = '%s:%s' % (os.path.abspath(os.path.join(
            os.path.dirname(__file__), 'bin')), env.get("PATH"))

        try:
            tty = os.ttyname(0).replace('/dev/', '')
        except Exception:
            self.log.debug("Can't get ttyname", exc_info=True)
            tty = ''

        if self.caller != self.callee:
            try:
                os.chown(os.ttyname(0), self.callee.uid, -1)
            except Exception:
                self.log.debug("Can't chown ttyname", exc_info=True)

        utils.add_user_info(
            self.uid,
            tty, os.getpid(),
            self.callee.name, self.request.headers['Host'])

        if not tornado.options.options.unsecure or (
                self.socket.local and
                self.caller == self.callee and
                server == self.callee
        ) or not tornado.options.options.login:
            # User has been auth with ssl or is the same user as server
            # or login is explicitly turned off
            if (
                    not tornado.options.options.unsecure and
                    tornado.options.options.login and not (
                        self.socket.local and
                        self.caller == self.callee and
                        server == self.callee
                    )):
                # User is authed by ssl, setting groups
                try:
                    os.initgroups(self.callee.name, self.callee.gid)
                    os.setgid(self.callee.gid)
                    os.setuid(self.callee.uid)
                except Exception:
                    self.log.error(
                        'The server must be run as root '
                        'if you want to log as different user\n',
                        exc_info=True)
                    sys.exit(1)

            if tornado.options.options.cmd:
                args = tornado.options.options.cmd.split(' ')
            else:
                args = [tornado.options.options.shell or self.callee.shell]
                args.append('-i')

            os.execvpe(args[0], args, env)
            # This process has been replaced

        # Unsecure connection with su
        if server.root:
            if self.socket.local:
                if self.callee != self.caller:
                    # Force password prompt by dropping rights
                    # to the daemon user
                    os.setuid(daemon.uid)
            else:
                # We are not local so we should always get a password prompt
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
            if tornado.options.options.shell:
                args.append('-s')
                args.append(tornado.options.options.shell)
        args.append(self.callee.name)
        os.execvpe(args[0], args, env)

    def communicate(self):
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
        self.fd = None
        self.closed = False
        if self.request.headers['Origin'] not in (
                'http://%s' % self.request.headers['Host'],
                'https://%s' % self.request.headers['Host']):
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
        self.user = user if user else None
        self.caller = self.callee = None

        # If local we have the user connecting
        if self.socket.local and self.socket.user is not None:
            self.caller = self.socket.user

        if tornado.options.options.unsecure:
            if self.user:
                try:
                    self.callee = utils.User(name=self.user)
                except LookupError:
                    self.log.debug(
                        "Can't switch to user %s" % self.user, exc_info=True)
                    self.callee = None

            # If no user where given and we are local, keep the same user
            # as the one who opened the socket
            # ie: the one openning a terminal in borwser
            if not self.callee and not self.user and self.socket.local:
                self.callee = self.caller
        else:
            user = utils.parse_cert(self.stream.socket.getpeercert())
            assert user, 'No user in certificate'
            self.user = user
            try:
                self.callee = utils.User(name=self.user)
            except LookupError:
                raise Exception('Invalid user in certificate')

        TermWebSocket.terminals.add(self)

        motd = (self.render_string(
            tornado.options.options.motd,
            butterfly=self,
            version=__version__,
            opts=tornado.options.options,
            colors=utils.ansi_colors)
                .decode('utf-8')
                .replace('\r', '')
                .replace('\n', '\r\n'))
        self.write_message(motd)
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
            self.log.debug('WRIT<%r' % message)
            self.writer.write(message[1:])
            self.writer.flush()

    def shell_handler(self, fd, events):
        if events & ioloop.READ:
            try:
                read = self.reader.read()
            except IOError:
                read = ''

            self.log.debug('READ>%r' % read)
            if read and len(read) != 0 and self.ws_connection:
                self.write_message(read.decode('utf-8', 'replace'))
            else:
                events = ioloop.ERROR

        if events & ioloop.ERROR:
            self.log.info('Error on fd %d, closing' % fd)
            # Terminated
            self.on_close()
            self.close()

    def on_close(self):
        if self.closed:
            return
        self.closed = True
        if self.fd is not None:
            self.log.info('Closing fd %d' % self.fd)

        if getattr(self, 'pid', 0) == 0:
            self.log.info('pid is 0')
            return

        utils.rm_user_info(self.uid, self.pid)

        try:
            ioloop.remove_handler(self.fd)
        except Exception:
            self.log.error('handler removal fail', exc_info=True)

        try:
            os.close(self.fd)
        except Exception:
            self.log.debug('closing fd fail', exc_info=True)

        try:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        except Exception:
            self.log.debug('waitpid fail', exc_info=True)

        TermWebSocket.terminals.remove(self)
        self.log.info('Websocket closed')

        if self.application.systemd and not len(TermWebSocket.terminals):
            self.log.info('No more terminals, exiting...')
            sys.exit(0)
