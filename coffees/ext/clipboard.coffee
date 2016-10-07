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

addEventListener 'copy', copy = (e) ->
  butterfly.bell "copied"
  e.clipboardData.clearData()
  sel = getSelection().toString().replace(
    /\u00A0/g, ' ').replace(/\u2007/g, ' ')

  data = ''
  for line in sel.split('\n')
    if line.slice(-1) is '\u23CE'
      end = ''
      line = line.slice(0, -1)
    else
      end = '\n'
    data += line.replace(/\s*$/, '') + end

  e.clipboardData.setData 'text/plain', data.slice(0, -1)
  e.preventDefault()


addEventListener 'paste', (e) ->
  butterfly.bell "pasted"
  data = e.clipboardData.getData 'text/plain'
  data = data.replace(/\r\n/g, '\n').replace(/\n/g, '\r')
  # Send big data in chunks to prevent data loss
  size = 1024
  send = ->
    butterfly.send data.substring(0, size)
    data = data.substring(size)
    if data.length
      setTimeout send, 25
  send()

  e.preventDefault()
