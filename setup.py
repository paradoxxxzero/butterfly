#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
Butterfly - A sleek web based terminal emulator
"""
import os
import re
from setuptools import setup

ROOT = os.path.dirname(__file__)
with open(os.path.join(ROOT, 'butterfly', '__init__.py')) as fd:
    __version__ = re.search("__version__ = '([^']+)'", fd.read()).group(1)

options = dict(
    name="butterfly",
    version=__version__,
    description="A sleek web based terminal emulator",
    long_description="See http://github.com/paradoxxxzero/butterfly",
    author="Florian Mounier",
    author_email="paradoxxx.zero@gmail.com",
    url="http://github.com/paradoxxxzero/butterfly",
    license="GPLv3",
    platforms="Any",
    scripts=['butterfly.server.py'],
    packages=['butterfly'],
    install_requires=["tornado>=3.2"],
    package_data={
        'butterfly': [
            'static/fonts/*',
            'static/images/favicon.png',
            'static/stylesheets/main.css',
            'static/javascripts/main.js',
            'templates/index.html'
        ]
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: GNU General Public License v3 (GPLv3)",
        "Operating System :: POSIX :: Linux",
        "Programming Language :: Python :: 2",
        "Programming Language :: Python :: 3",
        "Topic :: Terminals"])

setup(**options)
