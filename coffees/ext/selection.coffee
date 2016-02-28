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
selection = null

cancel = (ev) ->
  ev.preventDefault() if ev.preventDefault
  ev.stopPropagation() if ev.stopPropagation
  ev.cancelBubble = true
  false

previousLeaf = (node) ->
  previous = node.previousSibling
  if not previous
    previous = node.parentNode.previousSibling
  if not previous
    previous = node.parentNode.parentNode.previousSibling
  while previous.lastChild
    previous = previous.lastChild
  previous

nextLeaf = (node) ->
  next = node.nextSibling
  if not next
    next = node.parentNode.nextSibling
  if not next
    next = node.parentNode.parentNode.nextSibling
  while next?.firstChild
    next = next.firstChild
  next

class Selection
  constructor: ->
    butterfly.body.classList.add('selection')
    @selection = getSelection()

  reset: ->
    @selection = getSelection()
    fakeRange = document.createRange()
    fakeRange.setStart(@selection.anchorNode, @selection.anchorOffset)
    fakeRange.setEnd(@selection.focusNode, @selection.focusOffset)
    @start =
      node: @selection.anchorNode
      offset: @selection.anchorOffset
    @end =
      node: @selection.focusNode
      offset: @selection.focusOffset

    if fakeRange.collapsed
      [@start, @end] = [@end, @start]

    @startLine = @start.node
    while not @startLine.classList or 'line' not in @startLine.classList
      @startLine = @startLine.parentNode

    @endLine = @end.node
    while not @endLine.classList or 'line' not in @endLine.classList
      @endLine = @endLine.parentNode

  clear: ->
    @selection.removeAllRanges()

  destroy: ->
    butterfly.body.classList.remove('selection')
    @clear()

  text: ->
    @selection.toString().replace(/\u00A0/g, ' ').replace(/\u2007/g, ' ')

  up: ->
    @go -1

  down: ->
    @go +1

  go: (n) ->
    index = butterfly.children.indexOf(@startLine) + n
    return unless 0 <= index < butterfly.children.length

    until butterfly.children[index].textContent.match /\S/
      index += n
      return unless 0 <= index < butterfly.children.length

    @selectLine index

  apply: ->
    @clear()
    range = document.createRange()
    range.setStart @start.node, @start.offset
    range.setEnd @end.node, @end.offset
    @selection.addRange range

  selectLine: (index) ->
    line = butterfly.children[index]
    lineStart =
      node: line.firstChild
      offset: 0

    lineEnd =
      node: line.lastChild
      offset: line.lastChild.textContent.length

    @start = @walk lineStart, /\S/
    @end = @walk lineEnd, /\S/, true

  collapsed: (start, end) ->
    fakeRange = document.createRange()
    fakeRange.setStart(start.node, start.offset)
    fakeRange.setEnd(end.node, end.offset)
    fakeRange.collapsed

  shrinkRight: ->
    node = @walk @end, /\s/, true
    end = @walk node, /\S/, true
    if not @collapsed(@start, end)
      @end = end

  shrinkLeft: ->
    node = @walk @start, /\s/
    start = @walk node, /\S/
    if not @collapsed(start, @end)
      @start = start

  expandRight: ->
    node = @walk @end, /\S/
    @end = @walk node, /\s/

  expandLeft: ->
    node = @walk @start, /\S/, true
    @start = @walk node, /\s/, true

  walk: (needle, til, backward=false) ->
    if needle.node.firstChild
      node = needle.node.firstChild
    else
      node = needle.node

    text = node?.textContent
    i = needle.offset
    if backward
      while node
        while i > 0
          if text[--i].match til
            return node: node, offset: i + 1
        node = previousLeaf node
        text = node?.textContent
        i = text.length
    else
      while node
        while i < text.length
          if text[i++].match til
            return node: node, offset: i - 1
        node = nextLeaf node
        text = node?.textContent
        i = 0

    return needle

document.addEventListener 'keydown', (e) ->
  return true if e.keyCode in [16..19]

  # Paste natural selection too if shiftkey
  if e.shiftKey and e.keyCode is 13 and
      not selection and not getSelection().isCollapsed
    butterfly.send getSelection().toString()
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
      selection.shrinkLeft()
    else if e.keyCode == 38
      selection.expandLeft()
    else if e.keyCode == 37
      selection.shrinkRight()
    else if e.keyCode == 40
      selection.expandRight()
    else
      return cancel e

    selection?.apply()
    return cancel e

  # Start selection mode with shift up
  if not selection and e.ctrlKey and e.shiftKey and e.keyCode == 38
    selection = new Selection()
    selection.selectLine butterfly.y - 1
    selection.apply()
    return cancel e
  true

document.addEventListener 'keyup', (e) ->
  return true if e.keyCode in [16..19]

  if selection
    if e.keyCode == 13
      butterfly.send selection.text()
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
    newRange = document.createRange()
    newRange.setStart(sel.focusNode, sel.focusOffset)
    newRange.setEnd(sel.anchorNode, sel.anchorOffset)
    sel.addRange(newRange)

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
