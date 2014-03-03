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


def get_socket_line(addr, port):
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

class Socket(object):

    def __init__(self, socket):
        sn = socket.getsockname()
        self.local_addr = sn[0]
        self.local_port = sn[1]
        pn = socket.getpeername()
        self.remote_addr = pn[0]
        self.remote_port = pn[1]
        try:
            self.user = get_socket_line(self.remote_addr, self.remote_port)[1]
        except Exception:
            self.user = None

        # su will handle setting up the user environment, so make this empty.
        self.env = {}

    @property
    def local(self):
        return self.remote_addr in ['127.0.0.1', '::1']

    def __repr__(self):
        return '<Socket L: %s:%d R: %s:%d User: %s>' % (
            self.local_addr, self.local_port,
            self.remote_addr, self.remote_port,
            self.user)
