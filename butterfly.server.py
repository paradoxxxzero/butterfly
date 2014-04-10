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
import uuid
import ssl
import os
import sys

try:
    input = raw_input
except NameError:
    pass

tornado.options.define("debug", default=False, help="Debug mode")
tornado.options.define("more", default=False,
                       help="Debug mode with more verbosity")
tornado.options.define("host", default='127.0.0.1', help="Server host")
tornado.options.define("port", default=57575, type=int, help="Server port")
tornado.options.define("shell", help="Shell to execute at login. Will be ignored if load_script option is defined.")
tornado.options.define("unsecure", default=False,
                       help="Don't use ssl not recommended")

tornado.options.define("generate_certs", default=False,
                       help="Generate butterfly certificates")
tornado.options.define("generate_user_pkcs", default='',
                       help="Generate user pfx for client authentication")

tornado.options.define("prompt_login", default=True, help="Whether to prompt login or not even for non local clients")

tornado.options.define("load_script", help="Start script if provided. If shell option is defined it will be ignored.")

tornado.options.define("wd", help="Default working directory. If /wd/ appears in the url, this option will be ignored.")

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
ioloop = tornado.ioloop.IOLoop.instance()
ca, ca_key = 'butterfly_ca.crt', 'butterfly_ca.key'
cert, cert_key = 'butterfly.crt', 'butterfly.key'


from butterfly import application

if tornado.options.options.generate_certs:
    from OpenSSL import crypto
    ca_pk = crypto.PKey()
    ca_pk.generate_key(crypto.TYPE_RSA, 2048)
    ca_cert = crypto.X509()
    ca_cert.get_subject().CN = 'butterfly ca'
    ca_cert.set_serial_number(100)
    ca_cert.gmtime_adj_notBefore(0)  # From now
    ca_cert.gmtime_adj_notAfter(315360000)  # to 10y
    ca_cert.set_issuer(ca_cert.get_subject())  # Self signed
    ca_cert.set_pubkey(ca_pk)
    ca_cert.sign(ca_pk, 'sha1')

    with open(ca, "wb") as cf:
        cf.write(
            crypto.dump_certificate(crypto.FILETYPE_PEM, ca_cert))
    with open(ca_key, "wb") as cf:
        cf.write(
            crypto.dump_privatekey(crypto.FILETYPE_PEM, ca_pk))

    server_pk = crypto.PKey()
    server_pk.generate_key(crypto.TYPE_RSA, 2048)
    server_cert = crypto.X509()
    server_cert.get_subject().CN = tornado.options.options.host
    server_cert.set_serial_number(200)
    server_cert.gmtime_adj_notBefore(0)  # From now
    server_cert.gmtime_adj_notAfter(315360000)  # to 10y
    server_cert.set_issuer(ca_cert.get_subject())  # Signed by ca
    server_cert.set_pubkey(server_pk)
    server_cert.sign(ca_pk, 'sha1')

    with open(cert, "wb") as cf:
        cf.write(crypto.dump_certificate(crypto.FILETYPE_PEM, server_cert))

    with open(cert_key, "wb") as cf:
        cf.write(crypto.dump_privatekey(crypto.FILETYPE_PEM, server_pk))
    print('Done')
    sys.exit(0)


if tornado.options.options.generate_user_pkcs:
    from OpenSSL import crypto
    if not all(map(os.path.exists,
                   [cert, cert_key, ca, ca_key])):
        print('Please generate certificates using --generate_certs before')
        sys.exit(1)

    user = tornado.options.options.generate_user_pkcs
    with open(ca, 'rb') as cf:
        ca_cert = crypto.load_certificate(crypto.FILETYPE_PEM, cf.read())
    with open(ca_key, 'rb') as cf:
        ca_pk = crypto.load_privatekey(crypto.FILETYPE_PEM, cf.read())

    client_pk = crypto.PKey()
    client_pk.generate_key(crypto.TYPE_RSA, 2048)

    client_cert = crypto.X509()
    client_cert.get_subject().CN = user
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

    with open('%s.p12' % user, "wb") as cf:
        cf.write(pfx.export(b''))
    print('%s.p12 written.' % user)
    sys.exit(0)


if (tornado.options.options.unsecure or
        tornado.options.options.host == '127.0.0.1'):
    ssl_opts = None
else:
    if not all(map(os.path.exists,
                   [cert, cert_key, ca, ca_key])):
            print("Unable to find butterfly certificate. "
                  "Can't run butterfly without certificate. "
                  "Either generate them or run as --unsecure "
                  "(NOT RECOMMENDED)")
            sys.exit(1)

    ssl_opts = {
        'certfile': cert,
        'keyfile': cert_key,
        'ca_certs': ca,
        'cert_reqs': ssl.CERT_REQUIRED
    }

http_server = tornado.httpserver.HTTPServer(application, ssl_options=ssl_opts)
http_server.listen(
    tornado.options.options.port, address=tornado.options.options.host)

url = "http%s://%s:%d/*" % (
    "s" if not tornado.options.options.unsecure else "",
    tornado.options.options.host,
    tornado.options.options.port)

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
ioloop.start()
