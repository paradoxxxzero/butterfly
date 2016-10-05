# *-* coding: utf-8 *-*
# This file is part of butterfly
#
# butterfly Copyright (C) 2015  Florian Mounier
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


import os
import sys
import tornado.options
import tornado.process
import tornado.escape
import tornado.web
import tornado.websocket
from mimetypes import guess_type
from collections import defaultdict
from butterfly import url, Route, utils, __version__
from butterfly.terminal import Terminal


def u(s):
    if sys.version_info[0] == 2:
        return s.decode('utf-8')
    return s


@url(r'/(?:user/(.+))?/?(?:wd/(.+))?/?(?:session/(.+))?')
class Index(Route):
    def get(self, user, path, session):
        if not tornado.options.options.unsecure and user:
            raise tornado.web.HTTPError(400)
        return self.render('index.html')


@url(r'/theme/([^/]+)/style.css')
class Theme(Route):

    def get(self, theme):
        self.log.info('Getting style')
        try:
            import sass
            sass.CompileError
        except Exception:
            self.log.error(
                'You must install libsass to use sass '
                '(pip install libsass)')
            return
        base_dir = self.get_theme_dir(theme)

        style = None
        for ext in ['css', 'scss', 'sass']:
            probable_style = os.path.join(base_dir, 'style.%s' % ext)
            if os.path.exists(probable_style):
                style = probable_style

        if not style:
            raise tornado.web.HTTPError(404)

        sass_path = os.path.join(
            os.path.dirname(__file__), 'sass')

        css = None
        try:
            css = sass.compile(filename=style, include_paths=[
                base_dir, sass_path])
        except sass.CompileError:
            self.log.error(
                'Unable to compile style (filename: %s, paths: %r) ' % (
                    style, [base_dir, sass_path]), exc_info=True)
            if not style:
                raise tornado.web.HTTPError(500)

        self.log.debug('Style ok')
        self.set_header("Content-Type", "text/css")
        self.write(css)
        self.finish()


@url(r'/theme/([^/]+)/(.+)')
class ThemeStatic(Route):

    def get(self, theme, name):
        if '..' in name:
            raise tornado.web.HTTPError(403)

        base_dir = self.get_theme_dir(theme)

        fn = os.path.normpath(os.path.join(base_dir, name))
        if not fn.startswith(base_dir):
            raise tornado.web.HTTPError(403)

        if os.path.exists(fn):
            self.set_header("Content-Type", guess_type(fn)[0])
            with open(fn, 'rb') as s:
                while True:
                    data = s.read(16384)
                    if data:
                        self.write(data)
                    else:
                        break
            self.finish()
        raise tornado.web.HTTPError(404)


@url(r'/ws'
     '(?:/user/(?P<user>[^/]+))?/?'
     '(?:session/(?P<session>[^/]+))?/?'
     '(?:/wd/(?P<path>.+))?')
class TermWebSocket(Route, tornado.websocket.WebSocketHandler):
    session_history_size = 50000
    # List of websockets per session per user
    # dict: user -> dict: session -> [TermWebSocket]
    sessions = defaultdict(dict)

    # Terminal for session per user
    # dict: user -> dict: session -> Terminal
    terminals = defaultdict(dict)

    # All terminals sockets for systemd socket deactivation
    sockets = []

    # Session history
    history = {}

    def open(self, user, path, session):
        self.session = session
        self.closed = False
        self.secure_user = None

        # Prevent cross domain
        if self.request.headers['Origin'] not in (
                'http://%s' % self.request.headers['Host'],
                'https://%s' % self.request.headers['Host']):
            self.log.warning(
                'Unauthorized connection attempt: from : %s to: %s' % (
                    self.request.headers['Origin'],
                    self.request.headers['Host']))
            self.close()
            return

        TermWebSocket.sockets.append(self)

        self.log.info('Websocket opened %r' % self)
        self.set_nodelay(True)

        socket = utils.Socket(self.ws_connection.stream.socket)
        opts = tornado.options.options

        if not opts.unsecure:
            user = utils.parse_cert(
                self.ws_connection.stream.socket.getpeercert())
            assert user, 'No user in certificate'
            try:
                user = utils.User(name=user)
            except LookupError:
                raise Exception('Invalid user in certificate')

            # Certificate authed user
            self.secure_user = user

        elif socket.local and socket.user == utils.User():
            # Local to local returning browser user
            self.secure_user = socket.user

        # Handling terminal session
        if session:
            if session in self.user_sessions:
                # Session already here, registering websocket
                self.user_sessions[session].append(self)
                self.write_message('S' + TermWebSocket.history[session])
                # And returning, we don't want another terminal
                return
            else:
                # New session, opening terminal
                self.user_sessions[session] = [self]
                TermWebSocket.history[session] = ''

        terminal = Terminal(
            user, path, session, socket,
            self.request.headers['Host'], self.render_string, self.write)

        terminal.pty()

        if session:
            if not self.secure_user:
                self.log.error(
                    'No terminal session without secure authenticated user'
                    'or local user.')
                self._terminal = terminal
                self.session = None
            else:
                self.log.info('Openning session %s for secure user %r' % (
                    session, self.secure_user))
                self.user_terminals[session] = terminal
        else:
            self._terminal = terminal

    @property
    def user_sessions(self):
        """Return the dict session of socket lists"""
        if not self.secure_user:
            return {}
        return TermWebSocket.sessions[self.secure_user.name]

    @property
    def user_terminals(self):
        """Return the dict session of terminal"""
        if not self.secure_user:
            return {}
        return TermWebSocket.terminals[self.secure_user.name]

    @classmethod
    def close_all(cls, session, user):
        terminals = TermWebSocket.terminals.get(user.name)
        del terminals[session]

        sessions = TermWebSocket.sessions.get(user.name)
        if sessions:
            sockets = sessions[session]
        for socket in sockets[:]:
            socket.on_close()
            socket.close()
        del sessions[session]

    @classmethod
    def broadcast(cls, session, message, user, emitter=None):
        if message[0] == 'S':
            cls.history[session] += message[1:]
        if len(cls.history[session]) > cls.session_history_size:
            cls.history[session] = cls.history[session][
                -cls.session_history_size:]
        sessions = cls.sessions.get(user.name, [])

        for session in sessions[session]:
            try:
                if session != emitter:
                    session.write_message(message)
            except Exception:
                session.log.exception('Error on broadcast')
                session.close()

    def write(self, message):
        if self.session and self.secure_user:
            if message is None:
                TermWebSocket.close_all(self.session, self.secure_user)
            else:
                TermWebSocket.broadcast(
                    self.session, message, self.secure_user)
        else:
            if message is None:
                self.on_close()
                self.close()
            else:
                self.write_message(message)

    def on_message(self, message):
        if self.session and self.secure_user:
            term = self.user_terminals.get(self.session)
            term and term.write(message)
            if message[0] == 'R':
                # Broadcast resize
                TermWebSocket.broadcast(
                    self.session, message, self.secure_user, self)
        else:
            self._terminal.write(message)

    def on_close(self):
        if self.closed:
            return
        self.closed = True
        self.log.info('Websocket closed %r' % self)
        TermWebSocket.sockets.remove(self)
        if self.session:
            self.user_sessions[self.session].remove(self)
        elif hasattr(self, '_terminal'):
            self._terminal.close()
        else:
            self.log.error(
                'Socket with neither session nor terminal %r' % self)
        opts = tornado.options.options
        if opts.one_shot or (
                self.application.systemd and
                not len(TermWebSocket.sockets) and
                not sum([
                    len(sessions)
                    for user, sessions in TermWebSocket.terminals.items()])):
            sys.exit(0)


@url(r'/sessions/list.json')
class SessionsList(Route):
    """Get the theme list"""

    def get(self):
        if tornado.options.options.unsecure:
            raise tornado.web.HTTPError(403)

        cert = self.request.get_ssl_certificate()
        user = utils.parse_cert(cert)

        if not user:
            raise tornado.web.HTTPError(403)

        self.set_header('Content-Type', 'application/json')
        self.write(tornado.escape.json_encode({
            'sessions': sorted(
                TermWebSocket.sessions.get(user, [])),
            'user': user
        }))


@url(r'/themes/list.json')
class ThemesList(Route):
    """Get the theme list"""

    def get(self):

        if os.path.exists(self.themes_dir):
            themes = [
                theme
                for theme in os.listdir(self.themes_dir)
                if os.path.isdir(os.path.join(self.themes_dir, theme)) and
                not theme.startswith('.')]
        else:
            themes = []

        if os.path.exists(self.builtin_themes_dir):
            builtin_themes = [
                'built-in-%s' % theme
                for theme in os.listdir(self.builtin_themes_dir)
                if os.path.isdir(os.path.join(
                    self.builtin_themes_dir, theme)) and
                not theme.startswith('.')]
        else:
            builtin_themes = []

        self.set_header('Content-Type', 'application/json')
        self.write(tornado.escape.json_encode({
            'themes': sorted(themes),
            'builtin_themes': sorted(builtin_themes),
            'dir': self.themes_dir
        }))


@url('/local.js')
class LocalJsStatic(Route):
    def get(self):
        self.set_header("Content-Type", 'application/javascript')
        if os.path.exists(self.local_js_dir):
            for fn in os.listdir(self.local_js_dir):
                if not fn.endswith('.js'):
                    continue
                with open(os.path.join(self.local_js_dir, fn), 'rb') as s:
                    while True:
                        data = s.read(16384)
                        if data:
                            self.write(data)
                        else:
                            self.write(';')
                            break
        self.finish()
