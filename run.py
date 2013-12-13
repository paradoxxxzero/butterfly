#!/usr/bin/env python
from multiprocessing import Process
from subprocess import call
from glob import glob


class CompassWatch(Process):
    daemon = True

    def run(self):
        call(['compass', 'watch', 'app/static'])


class CoffeeScript(Process):
    daemon = True

    def run(self):
        call(['coffee',
              '-wcb',
              '-j', 'app/static/javascripts/main.js'] +
             glob('app/static/coffees/*.coffee'))


class Server(Process):
    daemon = True

    def run(self):
        call(['python', 'serve.py'])


print('Lauching compass')
CompassWatch().start()

print('Lauching coffee')
CoffeeScript().start()

print('Lauching server')
server = Server()
server.start()
