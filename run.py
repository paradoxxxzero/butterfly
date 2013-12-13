#!/usr/bin/env python
from multiprocessing import Process
from subprocess import Popen
from glob import glob
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
        self.proc = Popen(shlex.split(self.cmd))
        try:
            self.proc.wait()
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
