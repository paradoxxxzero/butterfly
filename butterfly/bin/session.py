#!/usr/bin/env python
import os
import webbrowser
import argparse

parser = argparse.ArgumentParser(description='Butterfly session opener.')
parser.add_argument(
    'session',
    help='Open or rattach a butterfly session. '
    '(Only in secure mode or in user unsecure mode (no su login))')
args = parser.parse_args()

url = '%ssession/%s' % (os.getenv('LOCATION', '/'), args.session)
if not webbrowser.open(url):
    print('Unable to open browser, please go to %s' % url)
