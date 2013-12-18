#!/usr/bin/env python
from multiprocessing import Process
from subprocess import Popen
from glob import glob
import time
import shlex

commands = [
    'coffee -wcb -j app/static/javascripts/main.js ' +
    ' '.join(glob('app/static/coffees/*.coffee')),
    'compass watch app/static',
    'python serve.py'
]


class Run(Process):
    daemon = True

    def __init__(self, command, *args, **kwargs):
        super(Run, self).__init__(*args, **kwargs)
        self.cmd = command

    def run(self):
        try:
            while True:
                self.proc = Popen(shlex.split(self.cmd))
                self.proc.wait()
                print(self.cmd + ' exited. Relaunching in 250ms')
                time.sleep(.25)
        except KeyboardInterrupt:
            pass

process = [Run(cmd) for cmd in commands]
for proc in process:
    print('Lauching %s' % proc.cmd.split(' ')[0])
    proc.start()

try:
    for proc in process:
        proc.join()
    print('Joined')
except KeyboardInterrupt:
    print('\nGot [ctrl]+[c] -- bye bye')
