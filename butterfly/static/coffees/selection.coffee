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

previous_leaf = (node) ->
    previous = node.previousSibling
    if not previous
        previous = node.parentNode.previousSibling
    if not previous
        previous = node.parentNode.parentNode.previousSibling
    while previous.lastChild
        previous = previous.lastChild
    previous

next_leaf = (node) ->
    next = node.nextSibling
    if not next
        next = node.parentNode.nextSibling
    if not next
        next = node.parentNode.parentNode.nextSibling
    while next.firstChild
        next = next.firstChild
    next

class Selection
    constructor: ->
        term.element.classList.add('selection')
        @selection = getSelection()

    reset: ->
        @selection = getSelection()
        fake_range = document.createRange()
        fake_range.setStart(@selection.anchorNode, @selection.anchorOffset)
        fake_range.setEnd(@selection.focusNode, @selection.focusOffset)
        @start =
            node: @selection.anchorNode
            offset: @selection.anchorOffset
        @end =
            node: @selection.focusNode
            offset: @selection.focusOffset

        if fake_range.collapsed
            [@start, @end] = [@end, @start]

        @start_line = @start.node
        while not @start_line.classList or 'line' not in @start_line.classList
            @start_line = @start_line.parentNode

        @end_line = @end.node
        while not @end_line.classList or 'line' not in @end_line.classList
            @end_line = @end_line.parentNode

    clear: ->
        @selection.removeAllRanges()

    destroy: ->
        term.element.classList.remove('selection')
        @clear()

    text: ->
        @selection.toString()

    up: ->
        @go -1

    down: ->
        @go +1

    go: (n) ->
        index = term.children.indexOf(@start_line) + n
        return unless 0 <= index < term.children.length

        until term.children[index].textContent.match /\S/
            index += n
            return unless 0 <= index < term.children.length

        @select_line index

    apply: ->
        @clear()
        range = document.createRange()
        range.setStart @start.node, @start.offset
        range.setEnd @end.node, @end.offset
        @selection.addRange range

    select_line: (index) ->
        line = term.children[index]
        line_start =
            node: line.firstChild
            offset: 0

        line_end =
            node: line.lastChild
            offset: line.lastChild.textContent.length

        @start = @walk line_start, /\S/
        @end = @walk line_end, /\S/, true

    shrink_right: ->
        node = @walk @end, /\s/, true
        @end = @walk node, /\S/, true

    shrink_left: ->
        node = @walk @start, /\s/
        @start = @walk node, /\S/

    expand_right: ->
        node = @walk @end, /\S/
        @end = @walk node, /\s/

    expand_left: ->
        node = @walk @start, /\S/, true
        @start = @walk node, /\s/, true

    walk: (needle, til, backward=false) ->
        node = if needle.node.firstChild then needle.node.firstChild else needle.node
        text = node.textContent
        i = needle.offset
        if backward
            while node
                while i > 0
                    if text[--i].match til
                        return node: node, offset: i + 1
                node = previous_leaf node
                text = node.textContent
                i = text.length
        else
            while node
                while i < text.length
                    if text[i++].match til
                        return node: node, offset: i - 1
                node = next_leaf node
                text = node.textContent
                i = 0

        return needle


document.addEventListener 'keydown', (e) ->
    return true if e.keyCode in [16..19]

    # Paste natural selection too if shiftkey
    if e.shiftKey and e.keyCode is 13 and not selection and not getSelection().isCollapsed
        term.handler getSelection().toString()
        getSelection().removeAllRanges()
        return cancel e

    if selection
        selection.reset()
        if not e.ctrlKey and e.shiftKey and 37 <= e.keyCode <= 40
            return true
        if e.shiftKey and e.ctrlKey
            if e.keyCode == 38
                selection.up()
            else if e.keyCode == 40
                selection.down()
        else if e.keyCode == 39
            selection.shrink_left()
        else if e.keyCode == 38
            selection.expand_left()
        else if e.keyCode == 37
            selection.shrink_right()
        else if e.keyCode == 40
            selection.expand_right()
        else
            return cancel e

        selection?.apply()
        return cancel e

    # Start selection mode with shift up
    if not selection and e.ctrlKey and e.shiftKey and e.keyCode == 38
        selection = new Selection()
        selection.select_line term.y - 1
        selection.apply()
        return cancel e
    true

document.addEventListener 'keyup', (e) ->
    return true if e.keyCode in [16..19]

    if selection
        if e.keyCode == 13
            term.handler selection.text()
            selection.destroy()
            selection = null
            return cancel e
        if e.keyCode not in [37..40]
            selection.destroy()
            selection = null
            return true
    true

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
