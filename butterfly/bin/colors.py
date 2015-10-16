#!/usr/bin/env python
import argparse
import sys

parser = argparse.ArgumentParser(description='Butterfly terminal color tester.')
parser.add_argument(
    '--colors',
    default='16',
    choices=['8', '16', '256', '16M'],
    help='Set the color mode to test')
args = parser.parse_args()

print()


if args.colors in ['8', '16']:
    print('Background\n')
    for l in range(3):
        sys.stdout.write(' ')
        for i in range(8):
            sys.stdout.write('\x1b[%dm      \x1b[m ' % (40 + i))
        sys.stdout.write('\n')
        sys.stdout.flush()

    if args.colors == '16':
        print()
        for l in range(3):
            sys.stdout.write(' ')
            for i in range(8):
                sys.stdout.write('\x1b[%dm      \x1b[m ' % (100 + i))
            sys.stdout.write('\n')
            sys.stdout.flush()

    print('\nForeground\n')

    for l in range(3):
        sys.stdout.write(' ')
        for i in range(8):
            sys.stdout.write('\x1b[%dm ░▒▓██\x1b[m ' % (30 + i))
        sys.stdout.write('\n')
        sys.stdout.flush()

    if args.colors == '16':
        print()
        for l in range(3):
            sys.stdout.write(' ')
            for i in range(8):
                sys.stdout.write('\x1b[1;%dm ░▒▓██\x1b[m ' % (30 + i))
            sys.stdout.write('\n')
            sys.stdout.flush()

if args.colors == '256':
    for i in range(16):
        sys.stdout.write('\x1b[48;5;%dm    \x1b[m' % (i))
    print()
    for i in range(16):
        sys.stdout.write('\x1b[48;5;%dm %03d\x1b[m' % (i, i))
    print()

    for j in range(6):
        for i in range(36):
            sys.stdout.write('\x1b[48;5;%dm    \x1b[m' % (16 + j * 36 + i))
        print()
        for i in range(36):
            sys.stdout.write('\x1b[48;5;%dm %03d\x1b[m' % (
                16 + j * 36 + i, 16 + j * 36 + i))
        print()
    for i in range(24):
        sys.stdout.write('\x1b[48;5;%dm    \x1b[m' % (232 + i))
    print()
    for i in range(24):
        sys.stdout.write('\x1b[48;5;%dm %03d\x1b[m' % (232 + i, 232 + i))

if args.colors == '16M':
    b = 0
    g = 0
    for r in range(256):
        if r == 128:
            print()
        sys.stdout.write('\x1b[48;2;%d;%d;%dm \x1b[m' % (r, g, b))
    print()

    r = 255
    b = 0
    for g in range(256):
        if g == 128:
            print()
        sys.stdout.write('\x1b[48;2;%d;%d;%dm \x1b[m' % (r, g, b))
    print()

    r = 255
    g = 255
    for b in range(256):
        if b == 128:
            print()
        sys.stdout.write('\x1b[48;2;%d;%d;%dm \x1b[m' % (r, g, b))
    print()

    r = 255
    b = 255
    for g in reversed(range(256)):
        if g == 127:
            print()
        sys.stdout.write('\x1b[48;2;%d;%d;%dm \x1b[m' % (r, g, b))
    print()

    g = 0
    b = 255
    for r in reversed(range(256)):
        if r == 127:
            print()
        sys.stdout.write('\x1b[48;2;%d;%d;%dm \x1b[m' % (r, g, b))
    print()

    r = 0
    g = 0
    for b in reversed(range(256)):
        if b == 127:
            print()
        sys.stdout.write('\x1b[48;2;%d;%d;%dm \x1b[m' % (r, g, b))
    print()

    r = 0
    b = 0
    for g in range(256):
        if g == 128:
            print()
        sys.stdout.write('\x1b[48;2;%d;%d;%dm \x1b[m' % (r, g, b))
    print()

    r = 0
    g = 255
    for b in range(256):
        if b == 128:
            print()
        sys.stdout.write('\x1b[48;2;%d;%d;%dm \x1b[m' % (r, g, b))
    print()

    b = 255
    g = 255
    for r in range(256):
        if r == 128:
            print()
        sys.stdout.write('\x1b[48;2;%d;%d;%dm \x1b[m' % (r, g, b))
    print()
