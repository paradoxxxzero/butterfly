#!/usr/bin/env python

try:
    from wdb.ext import add_w_builtin
    add_w_builtin()
except ImportError:
    pass

import tornado.options
import tornado.ioloop

tornado.options.define("secret", default='secret', help="Secret")
tornado.options.define("debug", default=False, help="Debug mode")
tornado.options.define("host", default='wsterm.l', help="Server host")
tornado.options.define("port", default=11112, type=int, help="Server port")

tornado.options.parse_command_line()


from logging import getLogger
for logger in ('tornado.access', 'tornado.application',
               'tornado.general', 'wsterm'):
    getLogger(logger).setLevel(10 if tornado.options.options.debug else 30)

log = getLogger('wsterm')
log.debug('Starting server')
ioloop = tornado.ioloop.IOLoop.instance()


from app import application
application.listen(tornado.options.options.port)


url = "http://%s:%d/*" % (
    tornado.options.options.host, tornado.options.options.port)

try:
    from wsreload.client import sporadic_reload, watch
except ImportError:
    log.debug('wsreload not found')
else:
    sporadic_reload({'url': url})

    files = ['app/static/javascripts/',
             'app/static/stylesheets/',
             'app/templates/']
    watch({'url': url}, files, unwatch_at_exit=True)

log.debug('Starting loop')
ioloop.start()
