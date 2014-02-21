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
selection = null

# get_line_range = (y) ->
#     first_node = term.children[y].firstChild
#     last_node = term.children[y].lastChild

#     range = document.createRange()
#     range.setStart first_node, 0
#     range.setEnd last_node, last_node.length
#     range
class Selection
    constructor: ->
        @reset()

    reset: ->
        @selection = getSelection()
        fake_range = document.createRange()
        fake_range.setStart(@selection.anchorNode, @selection.anchorOffset)
        fake_range.setEnd(@selection.focusNode, @selection.focusOffset)
        @start =
            node: @selection.anchorNode
            off: @selection.anchorOffset
        @end =
            node: @selection.focusNode
            off: @selection.focusOffset

        if fake_range.collapsed
            [@start, @end] = [@end, @start]

    clear: ->
        @selection.removeAllRanges()

    text: ->
        @selection.toString()

    up: ->
        @go -1

    down: ->
        @go +1

    go: (n) ->
        index = term.children.indexOf @get_selected_line()

        if 0 <= index + n < term.children.length
            @clear()
            @selection.addRange get_line_range(index + n)

    get_selected_line: ->
        node = @start.node
        while not node.classList or 'line' not in node.classList
            node = node.parentNode
        node


nextLeaf = (node) ->
    next = node.nextSibling
    if not next
        next = node.parentNode.nextSibling
    if not next
        next = node.parentNode.parentNode.nextSibling.firstChild
    next

find_node_offset = (line, backward=false) ->
    step = if backward then -1 else 1

    for node in line.childNodes by step
        if node.nodeType != node.TEXT_NODE
            node = node.firstChild
        for c, offset in node.textContent by step
            if not c.match  /\s/
                return [node, offset + if backward then 1 else 0]
    return [line.firstChild, 0]

get_line_range = (y) ->
    line = term.children[y]
    range = document.createRange()
    range.setStart.apply range, find_node_offset(line)
    range.setEnd.apply range, find_node_offset(line, true)
    range


sel_to_line = (y) ->
    selection = getSelection()
    selection.removeAllRanges()
    selection.addRange get_line_range(y)


document.addEventListener 'keydown', (e) ->
    if selection
        selection.reset()
        if not e.ctrlKey and e.shiftKey and 37 <= e.keyCode <= 40
            return true
        if e.shiftKey and e.ctrlKey
            if e.keyCode == 38
                selection.up()
                return cancel e
            else if e.keyCode == 40
                selection.down()
                return cancel e

        else if e.keyCode == 13
            term.handler selection.text()
            selection.clear()
            selection = null
        else
            selection.clear()
            selection = null
            return true
        return cancel e

    # Start selection mode with shift up
    if not selection and e.ctrlKey and e.shiftKey and e.keyCode == 38
        sel_to_line term.y - 1
        selection = new Selection()
        return cancel e

document.addEventListener 'dblclick', (e) ->
    return if e.ctrlKey or e.altkey
    sel = getSelection()
    return if sel.isCollapsed or sel.toString().match /\s/

    range = document.createRange()
    range.setStart(sel.anchorNode, sel.anchorOffset)
    range.setEnd(sel.focusNode, sel.focusOffset)
    if range.collapsed
        sel.removeAllRanges()
        new_range = document.createRange()
        new_range.setStart(sel.focusNode, sel.focusOffset)
        new_range.setEnd(sel.anchorNode, sel.anchorOffset)
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
