#!/bin/bash
sass-convert -R -F scss -T sass ext/sass-bootstrap/lib app/static/sass/bootstrap
cp -vf ext/sass-bootstrap/dist/js/bootstrap.min.js app/static/javascripts/
cp -vf ext/sass-bootstrap/dist/fonts/glyphicons-halflings-regular.* app/static/stylesheets/fonts/
