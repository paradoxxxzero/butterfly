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


if /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
.test navigator.userAgent
  ctrl = false
  alt = false
  first = true
  virtualInput = document.createElement 'input'
  virtualInput.type = 'password'
  virtualInput.style.position = 'fixed'
  virtualInput.style.top = 0
  virtualInput.style.left = 0
  virtualInput.style.border = 'none'
  virtualInput.style.outline = 'none'
  virtualInput.style.opacity = 0
  virtualInput.value = '0'
  document.body.appendChild virtualInput

  virtualInput.addEventListener 'blur', ->
    setTimeout((=> @focus()), 10)

  addEventListener 'click', ->
    virtualInput.focus()

  addEventListener 'touchstart', (e) ->
    if e.touches.length == 2
      ctrl = true
    else if e.touches.length == 3
      ctrl = false
      alt = true
    else if e.touches.length == 4
      ctrl = true
      alt = true

  virtualInput.addEventListener 'keydown', (e) ->
    butterfly.keyDown(e)
    return true

  virtualInput.addEventListener 'input', (e) ->
    len = @value.length

    if len == 0
      e.keyCode = 8
      butterfly.keyDown e
      @value = '0'
      return true

    e.keyCode = @value.charAt(1).charCodeAt(0)

    if (ctrl or alt) and not first
      e.keyCode = @value.charAt(1).charCodeAt(0)
      e.ctrlKey = ctrl
      e.altKey = alt
      if e.keyCode >= 97 && e.keyCode <= 122
        e.keyCode -= 32
      butterfly.keyDown e
      @value = '0'
      ctrl = alt = false
      return true

    butterfly.keyPress e
    first = false
    @value = '0'
    true
