#!/usr/bin/env python
import sys
import os
import base64
import mimetypes
import subprocess
from butterfly.escapes import image
import argparse

parser = argparse.ArgumentParser(description='Butterfly cat wrapper.')
parser.add_argument('-o', action="store_true",
                    dest='original', help='Force original cat')
parser.add_argument(
    'files', metavar='FILES', nargs='+',
    help='Force original cat')

args, remaining = parser.parse_known_args()
if args.original:
    os.execvp('/usr/bin/cat', remaining + args.files)


for file in args.files:
    if (not os.path.exists(sys.argv[1])):
        print('%s: No such file' % file)
    else:
        mime = mimetypes.guess_type(file)[0]
        if mime and 'image' in mime:
            with image(mime):
                with open(file, 'rb') as f:
                    print(base64.b64encode(f.read()).decode('ascii'))
        else:
            subprocess.call(['cat'] + remaining + [file])
