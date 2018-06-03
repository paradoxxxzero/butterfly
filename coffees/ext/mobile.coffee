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

ctrl = false
alt = false

addEventListener 'touchstart', (e) ->
  if e.touches.length == 2
    ctrl = true
  else if e.touches.length == 3
    ctrl = false
    alt = true
  else if e.touches.length == 4
    ctrl = true
    alt = true

# Dispatch a new event if the current event need to
# be modified with ctrlKey and altKey from touch events
# If so, this function will return true and dispatch the new event.
# The caller should return immediately upon receiving true.
window.mobileKeydown = (e) ->
  if ctrl or alt
    _ctrlKey = ctrl
    _altKey = alt
    _keyCode = e.keyCode
    if e.keyCode >= 97 && e.keyCode <= 122
      _keyCode -= 32
    e = new KeyboardEvent 'keydown',
      ctrlKey: _ctrlKey,
      altKey: _altKey,
      keyCode: _keyCode
    ctrl = alt = false
    setTimeout ->
      window.dispatchEvent e
    , 0
    return true
  else
    return false