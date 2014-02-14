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

worker = new Worker('/static/javascripts/worker.js')

worker.addEventListener 'message', (e) ->
    switch e.data.cmd
        when 'refresh'
            frontterm.refresh e.data.lines, e.data.start, e.data.end

cols = rows = null
quit = false

$ = document.querySelectorAll.bind(document)

send = (data) ->
    worker.postMessage
        cmd: 'data'
        data: data

ctl = (type, args...) ->
    params = args.join(',')
    if type == 'Resize'
        worker.postMessage 'R' + params
        # ws.send 'R' + params

addEventListener 'beforeunload', ->
    if not quit
        'This will exit the terminal session'

cancel = (ev) ->
  ev.preventDefault() if ev.preventDefault
  ev.stopPropagation() if ev.stopPropagation
  ev.cancelBubble = true
  false


class FrontTerminal
    constructor: (@parent) ->
        # Global elements
        @context = @parent.ownerDocument.defaultView
        @document = @parent.ownerDocument
        @body = @document.getElementsByTagName('body')[0]

        # Main terminal element
        @element = @document.createElement('div')
        @element.className = 'terminal focus'
        @element.style.outline = 'none'
        @element.setAttribute 'tabindex', 0

        @parent.appendChild(@element)

        # Adding one line to compute char size
        div = @document.createElement('div')
        div.className = 'line'
        @element.appendChild(div)
        @children = [div]

        @compute_char_size()
        div.style.height = @char_size.height + 'px'
        term_size = @parent.getBoundingClientRect()
        @cols = Math.floor(term_size.width / @char_size.width) - 1 # ?
        @rows = Math.floor(term_size.height / @char_size.height)

        i = @rows - 1
        while i--
            div = @document.createElement('div')
            div.style.height = @char_size.height + 'px'
            div.className = 'line'
            @element.appendChild(div)
            @children.push(div)

        @visualBell = 100
        @cursorHidden = false
        @queue = ''

        # stream
        @defAttr = (0 << 18) | (257 << 9) | (256 << 0)
        @skipNextKey = null
        @cursorState = 0

        # Draw screen
        # @refresh 0, @rows - 1

        @focus()

        @startBlink()
        addEventListener 'keydown', @keyDown.bind(@)
        addEventListener 'keypress', @keyPress.bind(@)
        addEventListener 'focus', @focus.bind(@)
        addEventListener 'blur', @blur.bind(@)
        addEventListener 'paste', @paste.bind(@)
        addEventListener 'resize', @resize.bind(@)

        # Horrible Firefox paste workaround
        if typeof InstallTrigger isnt "undefined"
            @element.contentEditable = 'true'
            @element.addEventListener "mouseup", (ev) =>
                sel = getSelection().getRangeAt(0)
                if sel.startOffset is sel.endOffset
                    getSelection().removeAllRanges()

        @initmouse()

    compute_char_size: ->
        test_span = document.createElement('span')
        test_span.textContent = '0123456789'
        @children[0].appendChild(test_span)
        @char_size =
            width: test_span.getBoundingClientRect().width / 10
            height: @children[0].getBoundingClientRect().height
        @children[0].removeChild(test_span)

    focus: ->
        @send('\x1b[I') if @sendFocus
        @showCursor()
        @element.classList.add('focus')
        @element.classList.remove('blur')

    blur: ->
        @cursorState = 1
        # @refresh(@y, @y)
        @send('\x1b[O') if @sendFocus
        @element.classList.add('blur')
        @element.classList.remove('focus')

    paste: (ev) ->
        if ev.clipboardData
            @send ev.clipboardData.getData('text/plain')
        else if @context.clipboardData
            @send @context.clipboardData.getData('Text')
        cancel(ev)

    # XTerm mouse events
    # http://invisible-island.net/xterm/ctlseqs/ctlseqs.html#Mouse%20Tracking
    # To better understand these
    # the xterm code is very helpful:
    # Relevant files:
    #     button.c, charproc.c, misc.c
    # Relevant functions in xterm/button.c:
    #     BtnCode, EmitButtonCode, EditorButton, SendMousePosition
    initmouse: ->
        pressed = 32

        # mouseup, mousedown, mousewheel
        # left click: ^[[M 3<^[[M#3<
        # mousewheel up: ^[[M`3>
        sendButton = (ev) =>
            # get the xterm-style button
            button = getButton(ev)

            # get mouse coordinates
            pos = getCoords(ev)
            return unless pos
            sendEvent button, pos
            switch ev.type
                when "mousedown"
                    pressed = button

                when "mouseup"
                    # keep it at the left
                    # button, just in case.
                    pressed = 32

        # motion example of a left click:
        # ^[[M 3<^[[M@4<^[[M@5<^[[M@6<^[[M@7<^[[M#7<
        sendMove = (ev) =>
            button = pressed
            pos = getCoords(ev)
            return unless pos

            # buttons marked as motions
            # are incremented by 32
            button += 32
            sendEvent button, pos

        # encode button and
        # position to characters
        encode = (data, ch) =>
            unless @utfMouse
                return data.push(0) if ch is 255
                ch = 127 if ch > 127
                data.push ch
            else
                return data.push(0) if ch is 2047
                if ch < 127
                    data.push ch
                else
                    ch = 2047 if ch > 2047
                    data.push 0xC0 | (ch >> 6)
                    data.push 0x80 | (ch & 0x3F)


        # send a mouse event:
        # regular/utf8: ^[[M Cb Cx Cy
        # urxvt: ^[[ Cb ; Cx ; Cy M
        # sgr: ^[[ Cb ; Cx ; Cy M/m
        # vt300: ^[[ 24(1/3/5)~ [ Cx , Cy ] \r
        # locator: CSI P e ; P b ; P r ; P c ; P p & w
        sendEvent = (button, pos) =>

            if @urxvtMouse
                pos.x -= 32
                pos.y -= 32
                pos.x++
                pos.y++
                @send "\x1b[" + button + ";" + pos.x + ";" + pos.y + "M"
                return

            if @sgrMouse
                pos.x -= 32
                pos.y -= 32
                @send "\x1b[<" + (if (button & 3) is 3 then button & ~3 else button) + ";" + pos.x + ";" + pos.y + (if (button & 3) is 3 then "m" else "M")
                return

            data = []
            encode data, button
            encode data, pos.x
            encode data, pos.y
            @send "\x1b[M" + String.fromCharCode.apply(String, data)

        getButton = (ev) =>
            # two low bits:
            # 0 = left
            # 1 = middle
            # 2 = right
            # 3 = release
            # wheel up/down:
            # 1, and 2 - with 64 added
            switch ev.type
                when "mousedown"
                    button = if ev.button? then +ev.button else (if ev.which? then ev.which - 1 else null)
                when "mouseup"
                    button = 3
                when "wheel"
                    button = if ev.deltaY < 0 then 64 else 65

            # next three bits are the modifiers:
            # 4 = shift, 8 = meta, 16 = control
            shift = if ev.shiftKey then 4 else 0
            meta = if ev.metaKey then 8 else 0
            ctrl = if ev.ctrlKey then 16 else 0
            mod = shift | meta | ctrl

            # no mods
            if @vt200Mouse
                # ctrl only
                mod &= ctrl
            else
                 mod = 0 unless @normalMouse

            # increment to SP
            (32 + (mod << 2)) + button

        # mouse coordinates measured in cols/rows
        getCoords = (ev) =>
            x = ev.pageX
            y = ev.pageY

            # should probably check offsetParent
            # but this is more portable
            el = @element
            while el and el isnt @document.documentElement
                x -= el.offsetLeft
                y -= el.offsetTop
                el = if "offsetParent" of el then el.offsetParent else el.parentNode

            # convert to cols/rows
            w = @element.clientWidth
            h = @element.clientHeight
            x = Math.ceil((x / w) * @cols)
            y = Math.ceil((y / h) * @rows)

            # be sure to avoid sending
            # bad positions to the program
            x = 0     if x < 0
            x = @cols if x > @cols
            y = 0     if y < 0
            y = @rows if y > @rows

            # xterm sends raw bytes and
            # starts at 32 (SP) for each.
            x += 32
            y += 32

            x: x
            y: y
            type: ev.type

        addEventListener "mousedown", (ev) =>
            return unless @mouseEvents

            # send the button
            sendButton ev

            # fix for odd bug
            #if (@vt200Mouse && !@normalMouse) {
            if @vt200Mouse
                sendButton
                    __proto__: ev
                    type: "mouseup"

                return cancel(ev)

            addEventListener "mousemove", sendMove.bind(this) if @normalMouse

            # x10 compatibility mode can't send button releases
            unless @x10Mouse
                addEventListener "mouseup", up = (ev) =>
                    sendButton ev
                    removeEventListener "mousemove", sendMove if @normalMouse
                    removeEventListener "mouseup", up
                    cancel ev
            cancel ev

        addEventListener "wheel", (ev) =>
            if @mouseEvents
                return if @x10Mouse
                sendButton ev
            else
                return if @applicationKeypad
                @scrollDisp if ev.deltaY > 0 then 5 else -5
            cancel ev


    refresh: (lines, start, end) ->
        if end - start >= @rows / 3
            parent = @element.parentNode
            parent?.removeChild @element

        width = @cols
        y = start

        if end >= lines.length
            end = lines.length - 1

        while y <= end
            row = y
            line = lines[row]
            out = ""

            if y is @y and (@ydisp is @ybase or @selectMode) and not @cursorHidden
                x = @x
            else
                x = -Infinity

            attr = @defAttr
            i = 0
            while i < width
                data = line[i][0]
                ch = line[i][1]
                if data isnt attr
                    out += "</span>" if attr isnt @defAttr
                    if data isnt @defAttr
                        classes = []
                        out += "<span "
                        bg = data & 0x1ff
                        fg = (data >> 9) & 0x1ff
                        flags = data >> 18

                        # bold
                        classes.push "bold" if flags & 1
                        # underline
                        classes.push "underline" if flags & 2
                        # blink
                        classes.push "blink" if flags & 4
                        # inverse
                        classes.push "reverse-video" if flags & 8
                        # invisible
                        classes.push "invisible" if flags & 16

                        fg += 8 if flags & 1 and fg < 8
                        classes.push "bg-color-" + bg
                        classes.push "fg-color-" + fg

                        out += "class=\""
                        out += classes.join(" ")
                        out += "\">"
                out += "<span class=\"" + (if @cursorState then "reverse-video " else "") + "cursor\">" if i is x

                # This is a temporary dirty hack for raw html insertion
                if ch.length > 1
                    out += ch
                else
                    switch ch
                        when "&"
                            out += "&amp;"
                        when "<"
                            out += "&lt;"
                        when ">"
                            out += "&gt;"
                        else
                            if ch <= " "
                                out += "&nbsp;"
                            else
                                i++ if "\uff00" < ch < "\uffef"
                                out += ch
                out += "</span>" if i is x
                attr = data
                i++
            out += "</span>" if attr isnt @defAttr
            @children[y].innerHTML = out
            y++

        parent?.appendChild @element


    _cursorBlink: ->
        @cursorState ^= 1
        cursor = @element.querySelector(".cursor")
        return unless cursor
        if cursor.classList.contains("reverse-video")
            cursor.classList.remove "reverse-video"
        else
            cursor.classList.add "reverse-video"


    showCursor: ->
        return
        # unless @cursorState
            # @cursorState = 1
            # @refresh @y, @y


    startBlink: ->
        return unless @cursorBlink
        @_blinker = => @_cursorBlink()
        @_blink = setInterval(@_blinker, 500)


    refreshBlink: ->
        return unless @cursorBlink
        clearInterval @_blink
        @_blink = setInterval(@_blinker, 500)


    scrollDisp: (disp) ->
        @ydisp += disp
        if @ydisp > @ybase
            @ydisp = @ybase

        else
            @ydisp = 0  if @ydisp < 0

        # @refresh 0, @rows - 1

    keyDown: (ev) ->
        # Key Resources:
        # https://developer.mozilla.org/en-US/docs/DOM/KeyboardEvent
        # Don't handle modifiers alone
        return true if ev.keyCode > 15 and ev.keyCode < 19

        # Handle shift insert and ctrl insert copy/paste usefull for typematrix keyboard
        return true if (ev.shiftKey or ev.ctrlKey) and ev.keyCode is 45

        # Alt-z works as an escape to relay the following keys to the browser.
        # usefull to trigger browser shortcuts, i.e.: Alt+Z F5 to reload
        # May be redundant with keyPrefix
        if ev.altKey and ev.keyCode is 90 and not @skipNextKey
            @skipNextKey = true
            @element.classList.add('skip')
            return cancel(ev)

        if @skipNextKey
            @skipNextKey = false
            @element.classList.remove('skip')
            return true

        switch ev.keyCode
            # backspace
            when 8
                key = if ev.altKey then "\x1b" else ""
                if ev.shiftKey
                    key += "\x08" # ^H
                    break
                key += "\x7f" # ^?

            # tab
            when 9
                if ev.shiftKey
                    key = "\x1b[Z"
                    break
                key = "\t"

            # return/enter
            when 13
                key = "\r"

            # escape
            when 27
                key = "\x1b"

            # left-arrow
            when 37
                if @applicationCursor
                    key = "\x1bOD" # SS3 as ^[O for 7-bit
                    #key = '\x8fD'; // SS3 as 0x8f for 8-bit
                    break
                return true if ev.shiftKey
                key = "\x1b[D"

            # right-arrow
            when 39
                if @applicationCursor
                    key = "\x1bOC"
                    break
                return true if ev.shiftKey
                key = "\x1b[C"

            # up-arrow
            when 38
                if @applicationCursor
                    key = "\x1bOA"
                    break
                if ev.ctrlKey
                    @scrollDisp -1
                    return cancel(ev)
                else if ev.shiftKey
                    return true
                else
                    key = "\x1b[A"

            # down-arrow
            when 40
                if @applicationCursor
                    key = "\x1bOB"
                    break
                if ev.ctrlKey
                    @scrollDisp 1
                    return cancel(ev)
                else if ev.shiftKey
                    return true
                else
                    key = "\x1b[B"

            # delete
            when 46
                key = "\x1b[3~"

            # insert
            when 45
                key = "\x1b[2~"

            # home
            when 36
                if @applicationKeypad
                    key = "\x1bOH"
                    break
                key = "\x1bOH"

            # end
            when 35
                if @applicationKeypad
                    key = "\x1bOF"
                    break
                key = "\x1bOF"

            # page up
            when 33
                if ev.shiftKey
                    @scrollDisp -(@rows - 1)
                    return cancel(ev)
                else
                    key = "\x1b[5~"

            # page down
            when 34
                if ev.shiftKey
                    @scrollDisp @rows - 1
                    return cancel(ev)
                else
                    key = "\x1b[6~"

            # F1
            when 112
                key = "\x1bOP"

            # F2
            when 113
                key = "\x1bOQ"

            # F3
            when 114
                key = "\x1bOR"

            # F4
            when 115
                key = "\x1bOS"

            # F5
            when 116
                key = "\x1b[15~"

            # F6
            when 117
                key = "\x1b[17~"

            # F7
            when 118
                key = "\x1b[18~"

            # F8
            when 119
                key = "\x1b[19~"

            # F9
            when 120
                key = "\x1b[20~"

            # F10
            when 121
                key = "\x1b[21~"

            # F11
            when 122
                key = "\x1b[23~"

            # F12
            when 123
                key = "\x1b[24~"

            else
                # a-z and space
                if ev.ctrlKey
                    if ev.keyCode >= 65 and ev.keyCode <= 90

                        # Ctrl-A
                        if @screenKeys
                            if not @prefixMode and not @selectMode and ev.keyCode is 65
                                @enterPrefix()
                                return cancel(ev)

                        # Ctrl-V
                        if @prefixMode and ev.keyCode is 86
                            @leavePrefix()
                            return

                        # Ctrl-C
                        if (@prefixMode or @selectMode) and ev.keyCode is 67
                            if @visualMode
                                setTimeout (=>
                                    @leaveVisual()
                                    return
                                ), 1
                            return
                        key = String.fromCharCode(ev.keyCode - 64)
                    else if ev.keyCode is 32

                        # NUL
                        key = String.fromCharCode(0)
                    else if ev.keyCode >= 51 and ev.keyCode <= 55

                        # escape, file sep, group sep, record sep, unit sep
                        key = String.fromCharCode(ev.keyCode - 51 + 27)
                    else if ev.keyCode is 56

                        # delete
                        key = String.fromCharCode(127)
                    else if ev.keyCode is 219

                        # ^[ - escape
                        key = String.fromCharCode(27)

                    # ^] - group sep
                    else
                         key = String.fromCharCode(29) if ev.keyCode is 221

                else if ev.altKey
                    if ev.keyCode >= 65 and ev.keyCode <= 90
                        key = "\x1b" + String.fromCharCode(ev.keyCode + 32)
                    else if ev.keyCode is 192
                        key = "\x1b`"
                    else
                        key = "\x1b" + (ev.keyCode - 48) if ev.keyCode >= 48 and ev.keyCode <= 57

        if ev.keyCode >= 37 and ev.keyCode <= 40
            if ev.ctrlKey
                key = key.slice(0, -1) + "1;5" + key.slice(-1)
            else if ev.altKey
                key = key.slice(0, -1) + "1;3" + key.slice(-1)
            else key = key.slice(0, -1) + "1;4" + key.slice(-1) if ev.shiftKey

        return true unless key

        if @prefixMode
            @leavePrefix()
            return cancel(ev)

        if @selectMode
            @keySelect ev, key
            return cancel(ev)

        @showCursor()
        @handler(key)
        cancel ev

    keyPress: (ev) ->
        if @skipNextKey is false
            @skipNextKey = null
            return true

        cancel ev

        if ev.charCode
            key = ev.charCode
        else unless ev.which?
            key = ev.keyCode
        else if ev.which isnt 0 and ev.charCode isnt 0
            key = ev.which
        else
            return false

        return false if not key or ev.ctrlKey or ev.altKey or ev.metaKey
        key = String.fromCharCode(key)

        @showCursor()
        @handler key
        false

    handler: (data) ->
        worker.postMessage
            cmd: 'data',
            data: data

    send: (data) ->
        unless @queue
            setTimeout (=>
                @handler @queue
                @queue = ""
                return
            ), 1

        @queue += data

    bell: ->
        return unless @visualBell
        @element.classList.add "bell"
        setTimeout (=>
            @element.classList.remove "bell"
        ), @visualBell

    resize: ->
        old_cols = @cols
        old_rows = @rows
        term_size = @parent.getBoundingClientRect()
        @cols = Math.floor(term_size.width / @char_size.width) - 1 # ?
        @rows = Math.floor(term_size.height / @char_size.height)
        if old_cols == @cols and old_rows == @rows
            return

        @ctl 'Resize', @cols, @rows

        # resize rows
        j = old_rows
        if j < @rows
            el = @element
            while j++ < @rows
                if @children.length < @rows
                    line = @document.createElement("div")
                    line.className = 'line'
                    line.style.height = @char_size.height + 'px'
                    el.appendChild line
                    @children.push line
        else if j > @rows
            while j-- > @rows
                if @children.length > @rows
                    el = @children.pop()
                    continue unless el
                    el.parentNode.removeChild el


    get_html_height_in_lines: (html) ->
        temp_node = document.createElement("div")
        temp_node.innerHTML = html
        @element.appendChild temp_node
        html_height = temp_node.getBoundingClientRect().height
        @element.removeChild temp_node
        Math.ceil(html_height / @char_size.height)


frontterm = new FrontTerminal $('#wrapper')[0], send, ctl
worker.postMessage
    cmd: 'init'
    cols: frontterm.cols
    rows: frontterm.rows
    wsurl: 'ws://' + document.location.host + '/ws' + location.pathname
