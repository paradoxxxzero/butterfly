#!/bin/sh

compass compile --force -e production butterfly/static
coffee -cb -j butterfly/static/javascripts/main.js \
    butterfly/static/coffees/term.coffee \
    butterfly/static/coffees/selection.coffee \
    butterfly/static/coffees/virtual_input.coffee \
    butterfly/static/coffees/main.coffee
uglifyjs butterfly/static/javascripts/main.js -c -m > butterfly/static/javascripts/main.js
