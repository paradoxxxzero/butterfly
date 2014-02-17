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

document.addEventListener 'dblclick', (e) ->
    return if e.ctrlKey or e.altkey
    sel = window.getSelection()
    return if sel.isCollapsed or sel.toString().match /\s/

    range = document.createRange()
    range.setStart(sel.anchorNode, sel.anchorOffset)
    range.setEnd(sel.focusNode, sel.focusOffset)
    if range.collapsed
        sel.removeAllRanges()
        new_range = document.createRange()
        new_range.setEnd(sel.anchorNode, sel.anchorOffset)
        new_range.setStart(sel.focusNode, sel.focusOffset)
        sel.addRange(new_range)
    range.detach()

    until sel.toString().match(/\s/) or not sel.toString()
        sel.modify 'extend', 'forward', 'character'

    sel.modify 'extend', 'backward', 'character'

    # Return selection
    anchorNode = sel.anchorNode
    anchorOffset = sel.anchorOffset
    sel.collapseToEnd()
    sel.extend(anchorNode, anchorOffset)

    until sel.toString().match(/\s/) or not sel.toString()
        sel.modify 'extend', 'backward', 'character'

    sel.modify 'extend', 'forward', 'character'
