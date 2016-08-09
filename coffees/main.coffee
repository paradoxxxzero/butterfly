# *-* coding: utf-8 *-*
# This file is part of butterfly
#
# butterfly Copyright (C) 2015  Florian Mounier
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
openTs = (new Date()).getTime()
cutMessage = '\r\nCutting...... 8< ...... 8< ...... ' +
             '\r\nYou can release when there is no more output.' +
             '\r\nCutting...... 8< ...... 8< ......' +
             '\r\nCutting...... 8< ...... 8< ......'

$ = document.querySelectorAll.bind(document)

document.addEventListener 'DOMContentLoaded', ->
  term = null
  send = (data) ->
    ws.send 'S' + data

  ctl = (type, args...) ->
    params = args.join(',')
    if type == 'Resize'
      ws.send 'R' + params

  if location.protocol == 'https:'
    wsUrl = 'wss://'
  else
    wsUrl = 'ws://'

  root_path = document.body.getAttribute('data-root-path')
  if root_path.length
    root_path = "/#{root_path}"

  wsUrl += document.location.host + root_path + '/ws' + location.pathname
  ws = new WebSocket wsUrl

  ws.addEventListener 'open', ->
    console.log "WebSocket open", arguments
    term = new Terminal document.body, send, ctl
    term.ws = ws
    window.butterfly = term
    ws.send 'R' + term.cols + ',' + term.rows
    openTs = (new Date()).getTime()

  ws.addEventListener 'error', ->
    console.log "WebSocket error", arguments

  ws.addEventListener 'message', (e) ->
    if e.data[0] is 'R'
      [cols, rows] = e.data.slice(1).split(',')
      term.resize cols, rows, true
      return

    if e.data[0] isnt 'S'
      console.error 'Garbage message'
      return

    unless term.stop?
      term.write e.data.slice(1)
    else
      if term.stop < cutMessage.length
        letter = cutMessage[term.stop++]
      else
        letter = '.'
      term.write letter

  ws.addEventListener 'close', ->
    console.log "WebSocket closed", arguments
    setTimeout ->
      term.write 'Closed'
      # Allow quick reload
      term.skipNextKey = true
      term.body.classList.add('dead')
      # Don't autoclose if websocket didn't last 1 minute
      if (new Date()).getTime() - openTs > 60 * 1000
        open('','_self').close()
    , 1
    quit = true

  addEventListener 'beforeunload', ->
    if not quit
      'This will exit the terminal session'

  window.bench = (n=100000000) ->
    rnd = ''
    while rnd.length < n
      rnd += Math.random().toString(36).substring(2)

    console.time('bench')
    console.profile('bench')
    term.write rnd
    console.profileEnd()
    console.timeEnd('bench')


  window.cbench = (n=100000000) ->
    rnd = ''
    while rnd.length < n
      rnd += "\x1b[#{30 + parseInt(Math.random() * 20)}m"
      rnd += Math.random().toString(36).substring(2)

    console.time('cbench')
    console.profile('cbench')
    term.write rnd
    console.profileEnd()
    console.timeEnd('cbench')
