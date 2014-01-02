#!/usr/bin/env python

host = 'apparatus.l'
port = 2001
url = "http://%s:%d/*" % (host, port)

from log_colorizer import colorize
colorize()

try:
    from wdb.ext import add_w_builtin
    add_w_builtin()
except ImportError:
    pass

import logging
from app import app
app.logger.setLevel(logging.DEBUG)

del app.logger.handlers[:]

logging.getLogger('werkzeug').setLevel(logging.DEBUG)

werkzeug_debugger = True
try:
    from wdb.ext import WdbMiddleware
except ImportError:
    app.logger.debug('wdb not found')
else:
    app.wsgi_app = WdbMiddleware(app.wsgi_app, start_disabled=True)
    werkzeug_debugger = False

try:
    from wsreload.client import monkey_patch_http_server, watch
except ImportError:
    app.logger.debug('wsreload not found')
else:
    def log(httpserver):
        app.logger.debug('WSReloaded after server restart')
    monkey_patch_http_server({'url': url}, callback=log)
    app.logger.debug('HTTPServer monkey patched for url %s' % url)

    files = ['app/static/javascripts/',
             'app/static/stylesheets/',
             'app/templates/']
    watch({'url': url}, files, unwatch_at_exit=True)

app.run(
    debug=True,
    host=host,
    port=port,
    use_debugger=werkzeug_debugger,
    threaded=True)
