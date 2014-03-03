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

cols = rows = null
quit = false
open_ts = 0

$ = document.querySelectorAll.bind(document)

send = (data) ->
    ws.send 'S' + data

ctl = (type, args...) ->
    params = args.join(',')
    if type == 'Resize'
        ws.send 'R' + params

if location.protocol == 'https:'
    ws_url = 'wss://'
else
    ws_url = 'ws://'
ws_url += document.location.host + '/ws' + location.pathname
ws = new WebSocket ws_url

ws.addEventListener 'open', ->
    console.log "WebSocket open", arguments
    ws.send 'R' + term.cols + ',' + term.rows
    open_ts = (new Date()).getTime()

ws.addEventListener 'error', ->
    console.log "WebSocket error", arguments

ws.addEventListener 'message', (e) ->
    setTimeout ->
        term.write e.data
    , 1

ws.addEventListener 'close', ->
    console.log "WebSocket closed", arguments
    setTimeout ->
        term.write 'Closed'
        # Allow quick reload
        term.skipNextKey = true
        term.element.classList.add('skip')
    , 1
    quit = true
    # Don't autoclose if websocket didn't last 1 minute
    if (new Date()).getTime() - open_ts > 60 * 1000
        open('','_self').close()

term = new Terminal $('#wrapper')[0], send, ctl
addEventListener 'beforeunload', ->
    if not quit
        'This will exit the terminal session'

bench = (n=100000000) ->
    rnd = ''
    while rnd.length < n
        rnd += Math.random().toString(36).substring(2)

    t0 = (new Date()).getTime()
    term.write rnd
    console.log "#{n} chars in #{(new Date()).getTime() - t0} ms"


cbench = (n=100000000) ->
    rnd = ''
    while rnd.length < n
        rnd += "\x1b[#{30 + parseInt(Math.random() * 20)}m"
        rnd += Math.random().toString(36).substring(2)

    t0 = (new Date()).getTime()
    term.write rnd
    console.log "#{n} chars + colors in #{(new Date()).getTime() - t0} ms"
