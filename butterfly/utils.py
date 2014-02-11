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


log = getLogger('butterfly')


class User(object):
    def __init__(self, uid=None, name=None):
        if not uid and not name:
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
        return self.uid == other.uid

    def __repr__(self):
        return "%s [%r]" % (self.name, self.uid)


def get_socket_line(port):
    try:
        with open('/proc/net/tcp') as k:
            lines = k.readlines()
        for line in lines:
            # Look for local address with peer port
            if line.split()[1] == '0100007F:%X' % port:
                # We got the socket
                return line.split()
    except:
        log.error('getting socket inet4 line fail', exc_info=True)

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
        log.error('getting socket inet6 line fail', exc_info=True)


def get_env(inode):
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


class Socket(object):

    def __init__(self, socket):
        sn = socket.getsockname()
        self.local_addr = sn[0]
        self.local_port = sn[1]
        pn = socket.getpeername()
        self.remote_addr = pn[0]
        self.remote_port = pn[1]
        line = get_socket_line(self.remote_port)
        if line:
            self.uid = int(line[7])
            self.inode = line[9]
        else:
            self.uid = None
            self.inode = None

        self.env = {}
        if self.local:
            try:
                self.env = get_env(self.inode)
            except:
                log.warning('Unable to get env', exc_info=True)

    @property
    def local(self):
        return self.remote_addr in ['127.0.0.1', '::1']

    def __repr__(self):
        return '<Socket L: %s:%d R: %s:%d Uid: %r Inode: %s %d>' % (
            self.local_addr, self.local_port,
            self.remote_addr, self.remote_port,
            self.uid, self.inode, len(self.env))
