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


import os
import pwd
from logging import getLogger
import subprocess
import re

log = getLogger('butterfly')


def get_style():
    style = None
    for ext in ['css', 'scss', 'sass']:
        for fn in [
                '/etc/butterfly/style',
                os.path.expanduser('~/.butterfly/style')]:
            if os.path.exists('%s.%s' % (fn, ext)):
                style = '%s.%s' % (fn, ext)

    if style is None:
        return

    if style.endswith('.scss') or style.endswith('.sass'):
        sass_path = os.path.join(
            os.path.dirname(__file__), 'sass')
        try:
            import sass
        except:
            log.error('You must install libsass to use sass '
                      '(pip install libsass)')
            return

        try:
            return sass.compile(filename=style, include_paths=[sass_path])
        except sass.CompileError:
            log.error(
                'Unable to compile style.scss (filename: %s, paths: %r) ' % (
                    style, [sass_path]), exc_info=True)
            return

    with open(style) as s:
        return s.read()


def parse_cert(cert):
    user = None

    for elt in cert['subject']:
        user = dict(elt).get('commonName', None)
        if user:
            break

    return user


class User(object):
    def __init__(self, uid=None, name=None):
        if uid is None and not name:
            uid = os.getuid()
        if uid is not None:
            self.pw = pwd.getpwuid(uid)
        else:
            self.pw = pwd.getpwnam(name)
        if self.pw is None:
            raise LookupError('Unknown user')

    @property
    def uid(self):
        return self.pw.pw_uid

    @property
    def gid(self):
        return self.pw.pw_gid

    @property
    def name(self):
        return self.pw.pw_name

    @property
    def dir(self):
        return self.pw.pw_dir

    @property
    def shell(self):
        return self.pw.pw_shell

    @property
    def root(self):
        return self.uid == 0

    def __eq__(self, other):
        if other is None:
            return False
        return self.uid == other.uid

    def __repr__(self):
        return "%s [%r]" % (self.name, self.uid)


class Socket(object):

    def __init__(self, socket):
        sn = socket.getsockname()
        self.local_addr = sn[0]
        self.local_port = sn[1]
        pn = socket.getpeername()
        self.remote_addr = pn[0]
        self.remote_port = pn[1]
        self.user = None
        self.env = {}

        if not self.local:
            return

        # If there is procfs, get as much info as we can
        if os.path.exists('/proc/net'):
            try:
                line = get_procfs_socket_line(self.remote_port)
                self.user = User(uid=int(line[7]))
                self.env = get_socket_env(line[9])
            except Exception:
                log.debug('procfs was no good, aight', exc_info=True)

        if self.user is None:
            # Try with lsof
            try:
                self.user = User(name=get_lsof_socket_line(
                    self.remote_addr, self.remote_port)[1])
            except Exception:
                log.debug('lsof was no good', exc_info=True)

    @property
    def local(self):
        return self.remote_addr in ['127.0.0.1', '::1']

    def __repr__(self):
        return '<Socket L: %s:%d R: %s:%d User: %r>' % (
            self.local_addr, self.local_port,
            self.remote_addr, self.remote_port,
            self.user)


# Portable way to get the user, if lsof is installed
def get_lsof_socket_line(addr, port):
    # May want to make this into a dictionary in the future...
    regex = "\w+\s+(?P<pid>\d+)\s+(?P<user>\w+).*\s" \
            "(?P<laddr>.*?):(?P<lport>\d+)->(?P<raddr>.*?):(?P<rport>\d+)"
    output = subprocess.check_output(['lsof', '-Pni'])
    lines = output.split('\n')
    for line in lines:
        # Look for local address with peer port
        match = re.findall(regex, line)
        if len(match):
            match = match[0]
            if int(match[5]) == port:
                return match
    raise Exception("Couldn't find a match!")


# Linux only socket line get
def get_procfs_socket_line(port):
    try:
        with open('/proc/net/tcp') as k:
            lines = k.readlines()
        for line in lines:
            # Look for local address with peer port
            if line.split()[1] == '0100007F:%X' % port:
                # We got the socket
                return line.split()
    except:
        log.debug('getting socket inet4 line fail', exc_info=True)

    try:
        with open('/proc/net/tcp6') as k:
            lines = k.readlines()
        for line in lines:
            # Look for local address with peer port
            if line.split()[1] == (
                    '00000000000000000000000001000000:%X' % port):
                # We got the socket
                return line.split()
    except:
        log.debug('getting socket inet6 line fail', exc_info=True)


# Linux only browser environment far fetch
def get_socket_env(inode):
    for pid in os.listdir("/proc/"):
        if not pid.isdigit():
            continue
        for fd in os.listdir("/proc/%s/fd/" % pid):
            lnk = "/proc/%s/fd/%s" % (pid, fd)
            if not os.path.islink(lnk):
                continue
            if 'socket:[%s]' % inode == os.readlink(lnk):
                with open('/proc/%s/status' % pid) as s:
                    for line in s.readlines():
                        if line.startswith('PPid:'):
                            with open('/proc/%s/environ' %
                                      line[len('PPid:'):].strip()) as e:
                                keyvals = e.read().split('\x00')
                                env = {}
                                for keyval in keyvals:
                                    if '=' in keyval:
                                        key, val = keyval.split('=', 1)
                                        env[key] = val
                                return env
