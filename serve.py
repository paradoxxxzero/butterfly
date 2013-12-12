import logging

host = 'apparatus.l'
port = 2001
url = "http://%s:%d/*" % (host, port)

try:
    from wdb.ext import add_w_builtin
    add_w_builtin()
except ImportError:
    pass

from app import app
try:
    from log_colorizer import make_colored_stream_handler
    handler = make_colored_stream_handler()
    handler.setLevel(logging.DEBUG)

    del app.logger.handlers[:]
    app.logger.addHandler(handler)
    app.logger.setLevel(logging.DEBUG)

    import werkzeug
    werkzeug._internal._log(
        'debug', 'Need to log something before deleting handler -_-')
    del logging.getLogger('werkzeug').handlers[:]
    logging.getLogger('werkzeug').addHandler(handler)
except:
    print('log colorizer not found')

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

    files = ['app/static/javascripts/*',
             'app/static/stylesheets/*',
             'app/templates/*']
    watch({'url': url}, files, unwatch_at_exit=True)

app.run(
    debug=True,
    host=host,
    port=port,
    use_debugger=werkzeug_debugger,
    threaded=True)
