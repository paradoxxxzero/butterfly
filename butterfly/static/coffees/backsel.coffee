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

state =
    x: null
    y: null

document.addEventListener 'keydown', (e) ->
    if e.shiftKey and (37 <= e.keyCode <= 40)
        if state.y == null
            state.y = term.ybase + term.y
        if e.keyCode == 38
            state.y--
            if state.y < term.ybase
                state.y = term.ybase
        else if e.keyCode == 40
            state.y++
            if state.y > term.ybase + term.y
                state.y = term.ybase + term.y

        term.emit('data', ' \x0b\x15')
        if state.y != term.ybase + term.y
            term.emit('data', term.grabText(0, term.cols - 1, state.y, state.y).replace('\n', ''))
        e.stopPropagation()
        return false
    else
        state.x = state.y = null
