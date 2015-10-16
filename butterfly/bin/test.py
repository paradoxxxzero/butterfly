#!/usr/bin/env python
import sys
w = sys.stdout.write
print('Image injection test')
injection = 'R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==" onload="alert(\'pwnd\')" /><img src="data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw=='
w('\x1bP;IMAGE|image/gif;%s' % injection)
w('\x1bP')


print('HTML script execution test')
w('\x1bP;HTML|<img src="https://imgs.xkcd.com/comics/hack.png" onload="alert(\'pwnd\')" />')
w('\x1bP')
