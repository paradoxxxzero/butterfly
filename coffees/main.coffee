# *-* coding: utf-8 *-*
# This file is part of butterfly
#
# butterfly Copyright(C) 2015-2017 Florian Mounier
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

ws =
  shell: null
  ctl: null

$ = document.querySelectorAll.bind(document)

document.addEventListener 'DOMContentLoaded', ->
  term = null

  if location.protocol == 'https:'
    wsUrl = 'wss://'
  else
    wsUrl = 'ws://'

  rootPath = document.body.getAttribute('data-root-path')
  rootPath = rootPath.replace(/^\/+|\/+$/g, '')
  if rootPath.length
    rootPath = "/#{rootPath}"

  wsUrl += document.location.host + rootPath
  path = '/'
  if path.indexOf('/session') < 0
    path += "session/#{document.body.getAttribute('data-session-token')}"

  path += location.search

  ws.shell = new WebSocket wsUrl + '/ws' + path
  ws.ctl = new WebSocket wsUrl + '/ctl' + path

  open = ->
    console.log "WebSocket open", arguments

    if term
      term.body.classList.remove 'stopped'
      term.out = ws.shell.send.bind(ws.shell)
      term.out '\x03\n'
      return

    if (ws.shell.readyState is WebSocket.OPEN and
        ws.ctl.readyState is WebSocket.OPEN)

      term = new Terminal(
        document.body, ws.shell.send.bind(ws.shell), ws.ctl.send.bind(ws.ctl))
      term.ws = ws
      window.butterfly = term
      ws.ctl.send JSON.stringify(cmd: 'open')
      ws.ctl.send JSON.stringify(
        cmd: 'size', cols: term.cols, rows: term.rows)
      openTs = (new Date()).getTime()
    console.log "WebSocket open end", arguments

  error = ->
    console.error "WebSocket error", arguments

  close = ->
    console.log "WebSocket closed", arguments
    return if quit
    quit = true

    term.write 'Closed'
    # Allow quick reload
    term.skipNextKey = true
    term.body.classList.add('dead')
    # Don't autoclose if websocket didn't last 1 minute
    if (new Date()).getTime() - openTs > 60 * 1000
      window.open('','_self').close()

  reopenOnClose = ->
    setTimeout ->
      return if quit
      ws.shell = new WebSocket wsUrl + '/ws' + path
      init_shell_ws()
    , 100

  write = (data) ->
    if term
      term.write data

  write_request = (e) ->
    setTimeout write, 1, e.data

  ctl = (e) ->
    cmd = JSON.parse(e.data)
    if cmd.cmd is 'size'
      term.resize cmd.cols, cmd.rows, true

  init_shell_ws = ->
    ws.shell.addEventListener 'open', open
    ws.shell.addEventListener 'message', write_request
    ws.shell.addEventListener 'error', error
    ws.shell.addEventListener 'close', reopenOnClose

  init_ctl_ws = ->
    ws.ctl.addEventListener 'open', open
    ws.ctl.addEventListener 'message', ctl
    ws.ctl.addEventListener 'error', error
    ws.ctl.addEventListener 'close', close

  init_shell_ws()
  init_ctl_ws()

  addEventListener 'beforeunload', ->
    if not quit
      'This will exit the terminal session'
