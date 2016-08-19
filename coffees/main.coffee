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
ws =
  shell: null
  termctl: null

$ = document.querySelectorAll.bind(document)

uuid = ->
  'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace /[xy]/g, (c) ->
    r = Math.random() * 16 | 0
    v = if c is 'x' then r else (r & 0x3|0x8)
    v.toString(16)

document.addEventListener 'DOMContentLoaded', ->
  term = null
  send = (data) ->
    ws.shell.send data

  ctl = (type, args...) ->
    if type == 'Resize'
      ws.termctl.send JSON.stringify(
        cmd: 'size', cols: args[0], rows: args[1])

  if location.protocol == 'https:'
    wsUrl = 'wss://'
  else
    wsUrl = 'ws://'

  rootPath = document.body.getAttribute('data-root-path')
  if rootPath.length
    rootPath = "/#{rootPath}"

  wsUrl += document.location.host + rootPath
  path = location.pathname
  if path.indexOf('/session') < 0
    path += "session/#{uuid()}"

  path += location.search

  ws.shell = new WebSocket wsUrl + '/ws' + path
  ws.termctl = new WebSocket wsUrl + '/ctl' + path

  open = ->
    console.log "WebSocket open", arguments
    if (ws.shell.readyState is WebSocket.OPEN and
        ws.termctl.readyState is WebSocket.OPEN)

      term = new Terminal document.body, send, ctl
      term.ws = ws
      window.butterfly = term
      ws.termctl.send JSON.stringify(cmd: 'open')
      ws.termctl.send JSON.stringify(
        cmd: 'size', cols: term.cols, rows: term.rows)
      openTs = (new Date()).getTime()

  error = ->
    console.log "WebSocket error", arguments

  close = ->
    console.log "WebSocket closed", arguments
    return if quit

    setTimeout ->
      term.write 'Closed'
      # Allow quick reload
      term.skipNextKey = true
      term.body.classList.add('dead')
      # Don't autoclose if websocket didn't last 1 minute
      if (new Date()).getTime() - openTs > 60 * 1000
        window.open('','_self').close()
    , 1
    quit = true

  ws.shell.addEventListener 'open', open
  ws.termctl.addEventListener 'open', open

  ws.shell.addEventListener 'error', error
  ws.termctl.addEventListener 'error', error

  ws.shell.addEventListener 'close', close
  ws.termctl.addEventListener 'close', close

  ws.shell.addEventListener 'message', (e) ->
    unless term.stop?
      term.write e.data
    else
      if term.stop < cutMessage.length
        letter = cutMessage[term.stop++]
      else
        letter = '.'
      term.write letter

  ws.termctl.addEventListener 'message', (e) ->
    cmd = JSON.parse(e.data)
    if cmd.cmd is 'size'
      term.resize cmd.cols, cmd.rows, true

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
