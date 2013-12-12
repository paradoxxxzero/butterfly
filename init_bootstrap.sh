#!/bin/bash
sass-convert -R -F scss -T sass ext/sass-bootstrap/lib project/static/sass
cp -vf ext/sass-bootstrap/dist/js/bootstrap.min.js project/static/javascripts/
cp -vf ext/sass-bootstrap/dist/fonts/glyphicons-halflings-regular.* project/static/fonts/
