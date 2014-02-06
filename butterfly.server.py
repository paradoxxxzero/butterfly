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

tornado.options.define("secret", default='secret', help="Secret")
tornado.options.define("debug", default=False, help="Debug mode")
tornado.options.define("host", default='127.0.0.1', help="Server host")
tornado.options.define("port", default=57575, type=int, help="Server port")
tornado.options.define("shell", help="Shell to execute at login")

tornado.options.parse_command_line()


import logging
for logger in ('tornado.access', 'tornado.application',
               'tornado.general', 'butterfly'):
    logging.getLogger(logger).setLevel(
        logging.DEBUG if tornado.options.options.debug else logging.WARNING)

log = logging.getLogger('butterfly')
log.debug('Starting server')
ioloop = tornado.ioloop.IOLoop.instance()


from butterfly import application
application.listen(tornado.options.options.port)


url = "http://%s:%d/*" % (
    tornado.options.options.host, tornado.options.options.port)

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

log.debug('Starting loop')
ioloop.start()
