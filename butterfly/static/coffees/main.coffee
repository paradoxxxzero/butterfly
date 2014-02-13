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


term = ws = null
cols = rows = null
quit = false


$ = document.querySelectorAll.bind(document)

ws_url = 'ws://' + document.location.host + '/ws' + location.pathname
ws = new WebSocket ws_url
ws.onopen = ->
    console.log "WebSocket open", arguments

    term = new Terminal (data) -> ws.send 'SH|' + data

    term.open $('main')[0]
    $('.terminal')[0].style = ''
    resize()


ws.onerror = -> console.log "WebSocket error", arguments
ws.onmessage = (e) ->
    setTimeout ->
        term.write e.data
    , 1


ws.onclose = ->
    console.log "WebSocket closed", arguments
    quit = true
    open('','_self').close()

addEventListener 'beforeunload', ->
    if not quit
        'This will exit the terminal session'

addEventListener 'resize', resize =  ->
    main = $('main')[0]
    fake_term = document.createElement('div')
    fake_term.className = 'terminal test'
    fake_term_div = document.createElement('div')
    fake_term_line = document.createElement('span')
    fake_term_line.textContent = '0123456789'
    fake_term_div.appendChild(fake_term_line)
    fake_term.appendChild(fake_term_div)
    main.appendChild(fake_term)

    ew = fake_term_line.getBoundingClientRect().width
    eh = fake_term_div.getBoundingClientRect().height
    main.removeChild(fake_term)

    main_bb = main.getBoundingClientRect()
    cols = Math.floor(10 * main_bb.width / ew) - 1
    rows = Math.floor(main_bb.height / eh)

    console.log "Computed #{cols} cols and #{rows} rows from ", main_bb, ew, eh
    term.resize cols, rows
    for div in $('.terminal div')
        div.style.height = eh + 'px'

    ws.send "RS|#{cols},#{rows}"

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
