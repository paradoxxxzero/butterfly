#!/usr/bin/env python
import os
import webbrowser
import argparse

parser = argparse.ArgumentParser(description='Butterfly tab opener.')
parser.add_argument(
    'location',
    nargs='?',
    default=os.getcwd(),
    help='Directory to open the new tab in. (Defaults to current)')
args = parser.parse_args()

url = '%swd%s' % (os.getenv('LOCATION', '/'), os.path.abspath(args.location))
if not webbrowser.open(url):
    print('Unable to open browser, please go to %s' % url)
