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
import tornado.web
import tornado.websocket
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


@url(r'/theme/font/([^/]+)')
class Font(Route):

    def get(self, name):
        if not tornado.options.options.theme or not name:
            raise tornado.web.HTTPError(404)
        font = 'themes/%s/font/%s' % (
            tornado.options.options.theme,
            name)
        for fn in [
                '/etc/butterfly/%s' % font,
                os.path.expanduser('~/.butterfly/%s' % font)]:
            if os.path.exists(fn):
                ext = fn.split('.')[-1]
                self.set_header("Content-Type", "application/x-font-%s" % ext)
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
    session_history_size = 10000
    # List of websockets per session
    sessions = {}

    # Terminal for session
    terminals = {}

    # All terminals sockets for systemd socket deactivation
    sockets = []

    # Session history
    history = {}

    def open(self, user, path, session):
        self.session = session
        self.closed = False

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

        # Handling terminal session
        if session:
            if session in TermWebSocket.sessions:
                # Session already here, registering websocket
                TermWebSocket.sessions[session].append(self)
                self.write_message(TermWebSocket.history[session])
                # And returning, we don't want another terminal
                return
            else:
                # New session, opening terminal
                TermWebSocket.sessions[session] = [self]
                TermWebSocket.history[session] = ''

        terminal = Terminal(
                    user, path, session,
                    self.ws_connection.stream.socket,
                    self.request.headers['Host'],
                    self.render_string,
                    self.write)

        if session:
            TermWebSocket.terminals[session] = terminal
        else:
            self._terminal = terminal

    @classmethod
    def close_all(cls, session):
        for inst in TermWebSocket.sessions[session][:]:
            inst.on_close()
            inst.close()
        del TermWebSocket.sessions[session]
        del TermWebSocket.terminals[session]

    @classmethod
    def broadcast(cls, session, message):
        cls.history[session] += message
        if len(cls.history) > cls.session_history_size:
            cls.history[session] = cls.history[session][
                -cls.session_history_size:]
        for session in cls.sessions[session][:]:
            try:
                session.write_message(message)
            except Exception:
                session.close()

    def write(self, message):
        if self.session:
            if message is None:
                TermWebSocket.close_all(self.session)
            else:
                TermWebSocket.broadcast(self.session, message)
        else:
            if message is None:
                self.on_close()
                self.close()
            else:
                self.write_message(message)

    def on_message(self, message):
        if self.session:
            term = TermWebSocket.terminals.get(self.session)
            term and term.write(message)
        else:
            self._terminal.write(message)

    def on_close(self):
        if self.closed:
            return
        self.closed = True
        self.log.info('Websocket closed %r' % self)
        TermWebSocket.sockets.remove(self)
        if self.session:
            TermWebSocket.sessions[self.session].remove(self)
        elif hasattr(self, '_terminal'):
            self._terminal.close()
        else:
            self.log.error(
                'Socket with neither session nor terminal %r' % self)
        if self.application.systemd and not len(TermWebSocket.sockets):
            sys.exit(0)


@url(r'/list(?:user/(.+))?/?(?:wd/(.+))?')
class List(Route):
    """List available terminals"""
    def get(self, user, path):
        if not tornado.options.options.unsecure and user:
            raise tornado.web.HTTPError(400)
        return self.render('list.html', sessions=TermWebSocket.sessions)
