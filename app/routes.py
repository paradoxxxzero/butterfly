import tornado.websocket
from app import url, Route

@url(r'/')
class Index(Route):
    def get(self):
        return self.render('index.html')


@url(r'/ws')
class EchoWebSocket(Route, tornado.websocket.WebSocketHandler):

    def open(self):
        log.info('Websocket opened')

    def on_message(self, message):
        self.write_message(message)

    def on_close(self):
        log.info('Websocket closed')


