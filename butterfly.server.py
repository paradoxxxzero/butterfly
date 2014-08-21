#!/usr/bin/env python
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

import tornado.options
import tornado.ioloop
import tornado.httpserver
import tornado_systemd
import uuid
import ssl
import getpass
import os
import stat
import socket
import sys


tornado.options.define("debug", default=False, help="Debug mode")
tornado.options.define("more", default=False,
                       help="Debug mode with more verbosity")
tornado.options.define("host", default='localhost', help="Server host")
tornado.options.define("port", default=57575, type=int, help="Server port")
tornado.options.define("shell", help="Shell to execute at login")
tornado.options.define("unsecure", default=False,
                       help="Don't use ssl not recommended")
tornado.options.define("login", default=True,
                       help="Use login screen at start")

tornado.options.define("generate_certs", default=False,
                       help="Generate butterfly certificates")
tornado.options.define("generate_user_pkcs", default='',
                       help="Generate user pfx for client authentication")

tornado.options.define("unminified", default=False,
                       help="Use the unminified js (for development only)")

tornado.options.parse_command_line()


import logging
for logger in ('tornado.access', 'tornado.application',
               'tornado.general', 'butterfly'):
    level = logging.WARNING
    if tornado.options.options.debug:
        level = logging.INFO
        if tornado.options.options.more:
            level = logging.DEBUG
    logging.getLogger(logger).setLevel(level)

log = logging.getLogger('butterfly')
log.info('Starting server')

host = tornado.options.options.host
port = tornado.options.options.port

if os.getuid() == 0:
    ssl_dir = os.path.join(os.path.abspath(os.sep), 'etc', 'butterfly', 'ssl')
else:
    ssl_dir = os.path.join(os.path.expanduser('~'), '.butterfly', 'ssl')

if not os.path.exists(ssl_dir):
    os.makedirs(ssl_dir)


def to_abs(file):
    return os.path.join(ssl_dir, file)

ca, ca_key, cert, cert_key, pkcs12 = map(to_abs, [
    'butterfly_ca.crt', 'butterfly_ca.key',
    'butterfly_%s.crt', 'butterfly_%s.key',
    '%s.p12'])


def fill_fields(subject):
    subject.C = 'WW'
    subject.O = 'Butterfly'
    subject.OU = 'Butterfly Terminal'
    subject.ST = 'World Wide'
    subject.L = 'Terminal'


def write(file, content):
    with open(file, 'wb') as fd:
        fd.write(content)
    print('Writing %s' % file)


def read(file):
    print('Reading %s' % file)
    with open(file, 'rb') as fd:
        return fd.read()

if tornado.options.options.generate_certs:
    from OpenSSL import crypto
    print('Generating certificates for %s (change it with --host)\n' % host)

    if not os.path.exists(ca) and not os.path.exists(ca_key):
        print('Root certificate not found, generating it')
        ca_pk = crypto.PKey()
        ca_pk.generate_key(crypto.TYPE_RSA, 2048)
        ca_cert = crypto.X509()
        ca_cert.get_subject().CN = 'Butterfly CA on %s' % socket.gethostname()
        fill_fields(ca_cert.get_subject())
        ca_cert.set_serial_number(uuid.uuid4().int)
        ca_cert.gmtime_adj_notBefore(0)  # From now
        ca_cert.gmtime_adj_notAfter(315360000)  # to 10y
        ca_cert.set_issuer(ca_cert.get_subject())  # Self signed
        ca_cert.set_pubkey(ca_pk)
        ca_cert.sign(ca_pk, 'sha1')

        write(ca, crypto.dump_certificate(crypto.FILETYPE_PEM, ca_cert))
        write(ca_key, crypto.dump_privatekey(crypto.FILETYPE_PEM, ca_pk))
        os.chmod(ca_key, stat.S_IRUSR | stat.S_IWUSR)  # 0o600 perms
    else:
        print('Root certificate found, using it')
        ca_cert = crypto.load_certificate(crypto.FILETYPE_PEM, read(ca))
        ca_pk = crypto.load_privatekey(crypto.FILETYPE_PEM, read(ca_key))

    server_pk = crypto.PKey()
    server_pk.generate_key(crypto.TYPE_RSA, 2048)
    server_cert = crypto.X509()
    server_cert.get_subject().CN = host
    fill_fields(server_cert.get_subject())
    server_cert.set_serial_number(uuid.uuid4().int)
    server_cert.gmtime_adj_notBefore(0)  # From now
    server_cert.gmtime_adj_notAfter(315360000)  # to 10y
    server_cert.set_issuer(ca_cert.get_subject())  # Signed by ca
    server_cert.set_pubkey(server_pk)
    server_cert.sign(ca_pk, 'sha1')

    write(cert % host, crypto.dump_certificate(
        crypto.FILETYPE_PEM, server_cert))
    write(cert_key % host, crypto.dump_privatekey(
        crypto.FILETYPE_PEM, server_pk))
    os.chmod(cert_key % host, stat.S_IRUSR | stat.S_IWUSR)  # 0o600 perms

    print('\nNow you can run --generate-user-pkcs=user '
          'to generate user certificate.')
    sys.exit(0)


if tornado.options.options.generate_user_pkcs:
    from OpenSSL import crypto
    if not all(map(os.path.exists, [ca, ca_key])):
        print('Please generate certificates using --generate-certs before')
        sys.exit(1)

    user = tornado.options.options.generate_user_pkcs
    ca_cert = crypto.load_certificate(crypto.FILETYPE_PEM, read(ca))
    ca_pk = crypto.load_privatekey(crypto.FILETYPE_PEM, read(ca_key))

    client_pk = crypto.PKey()
    client_pk.generate_key(crypto.TYPE_RSA, 2048)

    client_cert = crypto.X509()
    client_cert.get_subject().CN = user
    fill_fields(client_cert.get_subject())
    client_cert.set_serial_number(uuid.uuid4().int)
    client_cert.gmtime_adj_notBefore(0)  # From now
    client_cert.gmtime_adj_notAfter(315360000)  # to 10y
    client_cert.set_issuer(ca_cert.get_subject())  # Signed by ca
    client_cert.set_pubkey(client_pk)
    client_cert.sign(client_pk, 'sha1')
    client_cert.sign(ca_pk, 'sha1')

    pfx = crypto.PKCS12()
    pfx.set_certificate(client_cert)
    pfx.set_privatekey(client_pk)
    pfx.set_ca_certificates([ca_cert])
    pfx.set_friendlyname(('%s cert for butterfly' % user).encode('utf-8'))

    while True:
        password = getpass.getpass('\nPKCS12 Password (can be blank): ')
        password2 = getpass.getpass('Verify Password (can be blank): ')
        if password == password2:
            break
        print('Passwords do not match.')

    print('')
    write(pkcs12 % user, pfx.export(password.encode('utf-8')))
    os.chmod(pkcs12 % user, stat.S_IRUSR | stat.S_IWUSR)  # 0o600 perms
    sys.exit(0)


if tornado.options.options.unsecure:
    ssl_opts = None
else:
    if not all(map(os.path.exists, [cert % host, cert_key % host, ca])):
        print("Unable to find butterfly certificate for host %s" % host)
        print(cert % host)
        print(cert_key % host)
        print(ca)
        print("Can't run butterfly without certificate.\n")
        print("Either generate them using --generate-certs --host=host "
              "or run as --unsecure (NOT RECOMMENDED)\n")
        print("For more information go to http://paradoxxxzero.github.io/"
              "2014/03/21/butterfly-with-ssl-auth.html\n")
        sys.exit(1)

    ssl_opts = {
        'certfile': cert % host,
        'keyfile': cert_key % host,
        'ca_certs': ca,
        'cert_reqs': ssl.CERT_REQUIRED
    }


from butterfly import application

http_server = tornado_systemd.SystemdHTTPServer(
    application, ssl_options=ssl_opts)
http_server.listen(port, address=host)
url = "http%s://%s:%d/*" % (
    "s" if not tornado.options.options.unsecure else "", host, port)

if http_server.systemd:
    os.environ.pop('LISTEN_PID')
    os.environ.pop('LISTEN_FDS')

# This is for debugging purpose
try:
    from wsreload.client import sporadic_reload, watch
except ImportError:
    log.debug('wsreload not found')
else:
    sporadic_reload({'url': url})

    files = ['butterfly/static/javascripts/',
             'butterfly/static/stylesheets/',
             'butterfly/templates/']
    watch({'url': url}, files, unwatch_at_exit=True)

log.info('Starting loop')

ioloop = tornado.ioloop.IOLoop.instance()
ioloop.start()
