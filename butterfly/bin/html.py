#!/usr/bin/env python
from butterfly.escapes import html
import argparse
import fileinput
import sys

parser = argparse.ArgumentParser(
    description="Butterfly html converter.\n\n"
    "Output in html standard input.\n"
    "Example: $ echo \"<b>Bold</b>\" | b html",
    formatter_class=argparse.RawTextHelpFormatter)

parser.parse_known_args()


with html():
    for line in fileinput.input():
        sys.stdout.write(line)
