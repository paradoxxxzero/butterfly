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
import ssl

tornado.options.define("debug", default=False, help="Debug mode")
tornado.options.define("more", default=False,
                       help="Debug mode with more verbosity")
tornado.options.define("host", default='127.0.0.1', help="Server host")
tornado.options.define("port", default=57575, type=int, help="Server port")
tornado.options.define("shell", help="Shell to execute at login")
tornado.options.define("secure", default=False,
                       help="Choose whether or not to use SSL")
tornado.options.define("reallysecure", default=False,
                       help="Require certificate authentication.")

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


from butterfly import application

if tornado.options.options.reallysecure:
    tornado.options.options.secure = True
    reqs = ssl.CERT_REQUIRED
elif tornado.options.options.secure:
    reqs = ssl.CERT_OPTIONAL

ssl_opts = None
if tornado.options.options.secure:
    ssl_opts = dict(certfile="butterfly.crt", keyfile="butterfly.key",
                    cert_reqs=reqs, ca_certs="butterflyca.crt")

http_server = tornado.httpserver.HTTPServer(application, ssl_options=ssl_opts)
http_server.listen(
    tornado.options.options.port, address=tornado.options.options.host)

url = "http%s://%s:%d/*" % ("s" if tornado.options.options.secure else "",
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
