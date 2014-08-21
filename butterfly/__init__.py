# *-* coding: utf-8 *-*
# This file is part of butterfly
#
# butterfly Copyright (C) 2014  Florian Mounier
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
__version__ = '1.5.6'


import os
import tornado.web
import tornado.options
import tornado.web
from logging import getLogger

log = getLogger('butterfly')


class url(object):
    def __init__(self, url):
        self.url = url

    def __call__(self, cls):
        application.add_handlers(
            r'.*$',
            (tornado.web.url(self.url, cls, name=cls.__name__),)
        )
        return cls


class Route(tornado.web.RequestHandler):
    @property
    def log(self):
        return log


application = tornado.web.Application(
    static_path=os.path.join(os.path.dirname(__file__), "static"),
    template_path=os.path.join(os.path.dirname(__file__), "templates"),
    debug=tornado.options.options.debug
)


import butterfly.routes
