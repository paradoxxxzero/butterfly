

class Terminal
    constructor: ->
        @cols = 80
        @rows = 24
        @scrollback = 100000

        @defAttr = (0 << 18) | (257 << 9) | (256 << 0)
        @curAttr = @defAttr


        @sendFocus = false

    eraseAttr: ->
        (@defAttr & ~0x1ff) | (@curAttr & 0x1ff)

    focus: ->
        @send('\x1b[I') if @sendFocus
        @showCursor()

    blur: ->
        @cursorState = 1
        @refresh(@y, @y)
        @send('\x1b[O') if @sendFocus

    open: (parent) ->
        @parent = parent or @parent
        throw new Error('Terminal requires a parent element') unless @parent

        # Global elements
        @context = @parent.ownerDocument.defaultView
        @document = @parent.ownerDocument
        @body = @document.getElementsByTagName('body')[0]

        # Main terminal element
        @element = @document.createElement('div')
        @element.className = 'terminal focus'
        @element.style.outline = 'none'
        @element.setAttribute('tabindex', 0)

        # Terminal lines
        @children = [];
        for i in [0..rows]
            div = @document.createElement('div')
            @element.appendChild(div)
            @children.push(div)

        @parent.appendChild(@element);

        # Draw screen
        @refresh 0, @rows - 1

        @focus()
        @startBlink()


    destroy: ->
        @readable = false
        @writable = false
        @write = -> 0

        @element.parentNode?.removeChild(@element)


    refresh: (start, end) ->
        if end - start >= @rows / 2
            parent = @element.parentNode
            parent?.removeChild @element

        width = @cols
        y = start

        if end >= @lines.length
            @log "`end` is too large. Most likely a bad CSR."
            end = @lines.length - 1

        while y <= end
            row = y + @ydisp
            line = @lines[row]
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
                                i++ if isWide(ch)
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
        unless @cursorState
            @cursorState = 1
            @refresh @y, @y


    startBlink: ->
        return unless @cursorBlink
        @_blinker = => @_cursorBlink()
        @_blink = setInterval(@_blinker, 500)


    refreshBlink: ->
        return unless @cursorBlink
        clearInterval @_blink
        @_blink = setInterval(@_blinker, 500)


    scroll: ->
        if ++@ybase is @scrollback
          @ybase = @ybase / 2 | 0
          @lines = @lines.slice(-(@ybase + @rows) + 1)

        @ydisp = @ybase

        # last line
        row = @ybase + @rows - 1

        # subtract the bottom scroll region
        row -= @rows - 1 - @scrollBottom
        if row is @lines.length
          # potential optimization:
          # pushing is faster than splicing
          # when they amount to the same
          # behavior.
          @lines.push @blankLine()
        else
          # add our new line
          @lines.splice row, 0, @blankLine()

        if @scrollTop isnt 0
          if @ybase isnt 0
            @ybase--
            @ydisp = @ybase
          @lines.splice @ybase + @scrollTop, 1

        # this.maxRange();
        @updateRange @scrollTop
        @updateRange @scrollBottom

    scrollDisp: (disp) ->
        @ydisp += disp
        if @ydisp > @ybase
            @ydisp = @ybase

        else
            @ydisp = 0  if @ydisp < 0

        @refresh 0, @rows - 1

    write: (data) ->
        @refreshStart = @y
        @refreshEnd = @y

        if @ybase isnt @ydisp
          @ydisp = @ybase
          @maxRange()

        i = 0
        l = data.length
        while i < l
            ch = data[i]
            switch @state
                when normal
                    switch ch

                        # '\a'
                        when "\u0007"
                            @bell()

                        # '\n', '\v', '\f'
                        when "\n", "\u000b", "\u000c"
                            @x = 0 if @convertEol

                            @y++
                            if @y > @scrollBottom
                                @y--
                                @scroll()

                        # '\r'
                        when "\r"
                            @x = 0

                        # '\b'
                        when "\b"
                            @x-- if @x > 0

                        # '\t'
                        when "\t"
                            @x = @nextStop()

                        # shift out
                        when "\u000e"
                            @setgLevel 1

                        # shift in
                        when "\u000f"
                            @setgLevel 0

                        # '\e'
                        when "\u001b"
                            @state = escaped

                        else
                            # ' '
                            if ch >= " "
                                ch = @charset[ch] if @charset and @charset[ch]
                                if @x >= @cols
                                    @x = 0
                                    @y++
                                    if @y > @scrollBottom
                                        @y--
                                        @scroll()
                                @lines[@y + @ybase][@x] = [this.curAttr, ch]
                                @x++
                                @updateRange @y
                                if isWide(ch)
                                    j = @y + @ybase
                                    if @cols < 2 or @x >= @cols
                                        @lines[j][@x - 1] = [this.curAttr, " "]
                                        break

                                    @lines[j][@x] = [this.curAttr, " "]
                                    @x++

                when escaped
                    switch ch
                        # ESC [ Control Sequence Introducer ( CSI is 0x9b).
                        when "["
                            @params = []
                            @currentParam = 0
                            @state = csi

                        # ESC ] Operating System Command ( OSC is 0x9d).
                        when "]"
                            @params = []
                            @currentParam = 0
                            @state = osc

                        # ESC P Device Control String ( DCS is 0x90).
                        when "P"
                            @params = []
                            @currentParam = 0
                            @state = dcs

                        # ESC _ Application Program Command ( APC is 0x9f).
                        when "_"
                            @state = ignore

                        # ESC ^ Privacy Message ( PM is 0x9e).
                        when "^"
                            @state = ignore

                        # ESC c Full Reset (RIS).
                        when "c"
                            @reset()

                        # ESC E Next Line ( NEL is 0x85).
                        # ESC D Index ( IND is 0x84).
                        when "E"
                            @x = 0
                        when "D"
                            @index()

                        # ESC M Reverse Index ( RI is 0x8d).
                        when "M"
                            @reverseIndex()

                        # ESC % Select default/utf-8 character set.
                        # @ = default, G = utf-8
                        when "%"

                            #this.charset = null;
                            @setgLevel 0
                            @setgCharset 0, Terminal.charsets.US
                            @state = normal
                            i++

                        # ESC (,),*,+,-,. Designate G0-G2 Character Set.
                        # <-- this seems to get all the attention
                        when "(", ")" , "*" , "+" , "-" , "."
                            switch ch
                                when "("
                                    @gcharset = 0
                                when ")"
                                    @gcharset = 1
                                when "*"
                                    @gcharset = 2
                                when "+"
                                    @gcharset = 3
                                when "-"
                                    @gcharset = 1
                                when "."
                                    @gcharset = 2
                            @state = charset

                        # Designate G3 Character Set (VT300).
                        # A = ISO Latin-1 Supplemental.
                        # Not implemented.
                        when "/"
                            @gcharset = 3
                            @state = charset
                            i--

                        # ESC N
                        # Single Shift Select of G2 Character Set
                        # ( SS2 is 0x8e). This affects next character only.

                        # ESC O
                        # Single Shift Select of G3 Character Set
                        # ( SS3 is 0x8f). This affects next character only.
                        when "N", "O"
                                break

                        # ESC n
                        # Invoke the G2 Character Set as GL (LS2).
                        when "n"
                            @setgLevel 2

                        # ESC o
                        # Invoke the G3 Character Set as GL (LS3).
                        when "o"
                            @setgLevel 3

                        # ESC |
                        # Invoke the G3 Character Set as GR (LS3R).
                        when "|"
                            @setgLevel 3

                        # ESC }
                        # Invoke the G2 Character Set as GR (LS2R).
                        when "}"
                            @setgLevel 2

                        # ESC ~
                        # Invoke the G1 Character Set as GR (LS1R).
                        when "~"
                            @setgLevel 1

                        # ESC 7 Save Cursor (DECSC).
                        when "7"
                            @saveCursor()
                            @state = normal

                        # ESC 8 Restore Cursor (DECRC).
                        when "8"
                            @restoreCursor()
                            @state = normal

                        # ESC # 3 DEC line height/width
                        when "#"
                            @state = normal
                            i++

                        # ESC H Tab Set (HTS is 0x88).
                        when "H"
                            @tabSet()

                        # ESC = Application Keypad (DECPAM).
                        when "="
                            @log "Serial port requested application keypad."
                            @applicationKeypad = true
                            @state = normal

                        # ESC > Normal Keypad (DECPNM).
                        when ">"
                            @log "Switching back to normal keypad."
                            @applicationKeypad = false
                            @state = normal
                        else
                            @state = normal
                            @error "Unknown ESC control: %s.", ch
                when charset
                    switch ch
                        when "0" # DEC Special Character and Line Drawing Set.
                            cs = Terminal.charsets.SCLD
                        when "A" # UK
                            cs = Terminal.charsets.UK
                        when "B" # United States (USASCII).
                            cs = Terminal.charsets.US
                        when "4" # Dutch
                            cs = Terminal.charsets.Dutch
                        # Finnish
                        when "C", "5"
                            cs = Terminal.charsets.Finnish
                        when "R" # French
                            cs = Terminal.charsets.French
                        when "Q" # FrenchCanadian
                            cs = Terminal.charsets.FrenchCanadian
                        when "K" # German
                            cs = Terminal.charsets.German
                        when "Y" # Italian
                            cs = Terminal.charsets.Italian
                        # NorwegianDanish
                        when "E", "6"
                            cs = Terminal.charsets.NorwegianDanish
                        when "Z" # Spanish
                            cs = Terminal.charsets.Spanish
                        # Swedish
                        when "H", "7"
                            cs = Terminal.charsets.Swedish
                        when "=" # Swiss
                            cs = Terminal.charsets.Swiss
                        when "/" # ISOLatin (actually /A)
                            cs = Terminal.charsets.ISOLatin
                            i++
                        else # Default
                            cs = Terminal.charsets.US
                    @setgCharset @gcharset, cs
                    @gcharset = null
                    @state = normal
                when osc

                    # OSC Ps ; Pt ST
                    # OSC Ps ; Pt BEL
                    #     Set Text Parameters.
                    if ch is "\u001b" or ch is "\u0007"
                        i++ if ch is "\u001b"
                        @params.push @currentParam
                        switch @params[0]
                            when 0, 1 , 2
                                if @params[1]
                                    @title = @params[1] + " - ƸӜƷ butterfly"
                                    @handleTitle @title

                            when 99
                                # Custom escape to produce raw html
                                html = "<div class=\"inline-html\">" + @params[1] + "</div>"
                                @lines[@y + @ybase][@x] = [
                                    this.curAttr
                                    html
                                ]
                                line = 0

                                while line < @get_html_height_in_lines(html) - 1
                                    @y++
                                    if @y > @scrollBottom
                                        @y--
                                        @scroll()
                                    line++
                                @updateRange @y

                        # reset colors
                        @params = []
                        @currentParam = 0
                        @state = normal
                    else
                        unless @params.length
                            if ch >= "0" and ch <= "9"
                                @currentParam = @currentParam * 10 + ch.charCodeAt(0) - 48
                            else if ch is ";"
                                @params.push @currentParam
                                @currentParam = ""
                        else
                            @currentParam += ch

                when csi
                    # '?', '>', '!'
                    if ch is "?" or ch is ">" or ch is "!"
                        @prefix = ch
                        break

                    # 0 - 9
                    if ch >= "0" and ch <= "9"
                        @currentParam = @currentParam * 10 + ch.charCodeAt(0) - 48
                        break

                    # '$', '"', ' ', '\''
                    if ch is "$" or ch is "\"" or ch is " " or ch is "'"
                        @postfix = ch
                        break
                    @params.push @currentParam
                    @currentParam = 0

                    # ';'
                    break if ch is ";"
                    @state = normal
                    switch ch
                        # CSI Ps A
                        # Cursor Up Ps Times (default = 1) (CUU).
                        when "A"
                            @cursorUp @params

                        # CSI Ps B
                        # Cursor Down Ps Times (default = 1) (CUD).
                        when "B"
                            @cursorDown @params

                        # CSI Ps C
                        # Cursor Forward Ps Times (default = 1) (CUF).
                        when "C"
                            @cursorForward @params

                        # CSI Ps D
                        # Cursor Backward Ps Times (default = 1) (CUB).
                        when "D"
                            @cursorBackward @params

                        # CSI Ps ; Ps H
                        # Cursor Position [row;column] (default = [1,1]) (CUP).
                        when "H"
                            @cursorPos @params

                        # CSI Ps J    Erase in Display (ED).
                        when "J"
                            @eraseInDisplay @params

                        # CSI Ps K    Erase in Line (EL).
                        when "K"
                            @eraseInLine @params

                        # CSI Pm m    Character Attributes (SGR).
                        when "m"
                            @charAttributes @params    unless @prefix

                        # CSI Ps n    Device Status Report (DSR).
                        when "n"
                            @deviceStatus @params    unless @prefix

                        # CSI Ps @
                        # Insert Ps (Blank) Character(s) (default = 1) (ICH).
                        when "@"
                            @insertChars @params

                        # CSI Ps E
                        # Cursor Next Line Ps Times (default = 1) (CNL).
                        when "E"
                            @cursorNextLine @params

                        # CSI Ps F
                        # Cursor Preceding Line Ps Times (default = 1) (CNL).
                        when "F"
                            @cursorPrecedingLine @params

                        # CSI Ps G
                        # Cursor Character Absolute    [column] (default = [row,1]) (CHA).
                        when "G"
                            @cursorCharAbsolute @params

                        # CSI Ps L
                        # Insert Ps Line(s) (default = 1) (IL).
                        when "L"
                            @insertLines @params

                        # CSI Ps M
                        # Delete Ps Line(s) (default = 1) (DL).
                        when "M"
                            @deleteLines @params

                        # CSI Ps P
                        # Delete Ps Character(s) (default = 1) (DCH).
                        when "P"
                            @deleteChars @params

                        # CSI Ps X
                        # Erase Ps Character(s) (default = 1) (ECH).
                        when "X"
                            @eraseChars @params

                        # CSI Pm `    Character Position Absolute
                        #     [column] (default = [row,1]) (HPA).
                        when "`"
                            @charPosAbsolute @params

                        # 141 61 a * HPR -
                        # Horizontal Position Relative
                        when "a"
                            @HPositionRelative @params

                        # CSI P s c
                        # Send Device Attributes (Primary DA).
                        # CSI > P s c
                        # Send Device Attributes (Secondary DA)
                        when "c"
                            @sendDeviceAttributes @params

                        # CSI Pm d
                        # Line Position Absolute    [row] (default = [1,column]) (VPA).
                        when "d"
                            @linePosAbsolute @params

                        # 145 65 e * VPR - Vertical Position Relative
                        when "e"
                            @VPositionRelative @params

                        # CSI Ps ; Ps f
                        #     Horizontal and Vertical Position [row;column] (default =
                        #     [1,1]) (HVP).
                        when "f"
                            @HVPosition @params

                        # CSI Pm h    Set Mode (SM).
                        # CSI ? Pm h - mouse escape codes, cursor escape codes
                        when "h"
                            @setMode @params

                        # CSI Pm l    Reset Mode (RM).
                        # CSI ? Pm l
                        when "l"
                            @resetMode @params

                        # CSI Ps ; Ps r
                        #     Set Scrolling Region [top;bottom] (default = full size of win-
                        #     dow) (DECSTBM).
                        # CSI ? Pm r
                        when "r"
                            @setScrollRegion @params

                        # CSI s
                        #     Save cursor (ANSI.SYS).
                        when "s"
                            @saveCursor @params

                        # CSI u
                        #     Restore cursor (ANSI.SYS).
                        when "u"
                            @restoreCursor @params

                        # CSI Ps I
                        # Cursor Forward Tabulation Ps tab stops (default = 1) (CHT).
                        when "I"
                            @cursorForwardTab @params

                        # CSI Ps S    Scroll up Ps lines (default = 1) (SU).
                        when "S"
                            @scrollUp @params

                        # CSI Ps T    Scroll down Ps lines (default = 1) (SD).
                        # CSI Ps ; Ps ; Ps ; Ps ; Ps T
                        # CSI > Ps; Ps T
                        when "T"
                            @scrollDown @params if @params.length < 2 and not @prefix

                        # CSI Ps Z
                        # Cursor Backward Tabulation Ps tab stops (default = 1) (CBT).
                        when "Z"
                            @cursorBackwardTab @params

                        # CSI Ps b    Repeat the preceding graphic character Ps times (REP).
                        when "b"
                            @repeatPrecedingCharacter @params

                        # CSI Ps g    Tab Clear (TBC).
                        when "g"
                            @tabClear @params

                        # CSI > Ps p    Set pointer mode.
                        # CSI ! p     Soft terminal reset (DECSTR).
                        # CSI Ps$ p
                        #     Request ANSI mode (DECRQM).
                        # CSI ? Ps$ p
                        #     Request DEC private mode (DECRQM).
                        # CSI Ps ; Ps " p
                        when "p"
                            switch @prefix

                                # case '>':
                                #     this.setPointerMode(this.params);
                                #     break;
                                when "!"
                                    @softReset @params

                        else
                            @error "Unknown CSI code: %s.", ch
                    @prefix = ""
                    @postfix = ""
                when dcs
                    if ch is "\u001b" or ch is "\u0007"
                        i++ if ch is "\u001b"
                        switch @prefix
                            # User-Defined Keys (DECUDK).
                            when ""
                                break

                            # Request Status String (DECRQSS).
                            # test: echo -e '\eP$q"p\e\\'
                            when "$q"
                                pt = @currentParam
                                valid = false
                                switch pt

                                    # DECSCA
                                    when "\"q"
                                        pt = "0\"q"

                                    # DECSCL
                                    when "\"p"
                                        pt = "61\"p"

                                    # DECSTBM
                                    when "r"
                                        pt = "" + (@scrollTop + 1) + ";" + (@scrollBottom + 1) + "r"

                                    # SGR
                                    when "m"
                                        pt = "0m"

                                    else
                                        @error "Unknown DCS Pt: %s.", pt
                                        pt = ""

                                @send "\u001bP" + +valid + "$r" + pt + "\u001b\\"

                            # Set Termcap/Terminfo Data (xterm, experimental).
                            when "+p"
                                break
                            # Request Termcap/Terminfo String (xterm, experimental)
                            # Regular xterm does not even respond to this sequence.
                            # This can cause a small glitch in vim.
                            # test: echo -ne '\eP+q6b64\e\\'
                            when "+q"
                                pt = @currentParam
                                valid = false
                                @send "\u001bP" + +valid + "+r" + pt + "\u001b\\"

                            else
                                @error "Unknown DCS prefix: %s.", @prefix

                        @currentParam = 0
                        @prefix = ""
                        @state = normal

                    else unless @currentParam
                        if not @prefix and ch isnt "$" and ch isnt "+"
                            @currentParam = ch
                        else if @prefix.length is 2
                            @currentParam = ch
                        else
                            @prefix += ch
                    else
                        @currentParam += ch

                when ignore
                    # For PM and APC.
                    if ch is "\u001b" or ch is "\u0007"
                        i++ if ch is "\u001b"
                        @state = normal
            i++
        @updateRange @y
        @refresh @refreshStart, @refreshEnd

    writeln: (data) ->
        @write "#{data}\r\n"

    keydown: (ev) ->
        # Key Resources:
        # https://developer.mozilla.org/en-US/docs/DOM/KeyboardEvent
        # Don't handle modifiers alone
        return true if ev.keyCode > 15 and ev.keyCode < 19

        # Handle shift insert and ctrl insert copy/paste usefull for typematrix keyboard
        # TODO
        # if ev.shiftKey and ev.keyCode is 45
        #     @emit "paste"
        #     return true
        # if ev.ctrlKey and ev.keyCode is 45
        #     @emit "copy"
        #     return true

        # Alt-z works as an escape to relay the following keys to the browser.
        # usefull to trigger browser shortcuts, i.e.: Alt+Z F5 to reload
        # May be redundant with keyPrefix
        if ev.altKey and ev.keyCode is 90 and not @skipNextKey
            @skipNextKey = true
            return cancel(ev)

        if @skipNextKey
            @skipNextKey = false
            return true

        switch ev.keyCode
            # backspace
            when 8
                key = if ev.altKey then "\u001b" else ""
                if ev.shiftKey
                    key += "\x08" # ^H
                    break
                key += "\x7f" # ^?

            # tab
            when 9
                if ev.shiftKey
                    key = "\u001b[Z"
                    break
                key = "\t"

            # return/enter
            when 13
                key = "\r"

            # escape
            when 27
                key = "\u001b"

            # left-arrow
            when 37
                if @applicationCursor
                    key = "\u001bOD" # SS3 as ^[O for 7-bit
                    #key = '\x8fD'; // SS3 as 0x8f for 8-bit
                    break
                return true if ev.shiftKey
                key = "\u001b[D"

            # right-arrow
            when 39
                if @applicationCursor
                    key = "\u001bOC"
                    break
                return true if ev.shiftKey
                key = "\u001b[C"

            # up-arrow
            when 38
                if @applicationCursor
                    key = "\u001bOA"
                    break
                if ev.ctrlKey
                    @scrollDisp -1
                    return cancel(ev)
                else if ev.shiftKey
                    return true
                else
                    key = "\u001b[A"

            # down-arrow
            when 40
                if @applicationCursor
                    key = "\u001bOB"
                    break
                if ev.ctrlKey
                    @scrollDisp 1
                    return cancel(ev)
                else if ev.shiftKey
                    return true
                else
                    key = "\u001b[B"

            # delete
            when 46
                key = "\u001b[3~"

            # insert
            when 45
                key = "\u001b[2~"

            # home
            when 36
                if @applicationKeypad
                    key = "\u001bOH"
                    break
                key = "\u001bOH"

            # end
            when 35
                if @applicationKeypad
                    key = "\u001bOF"
                    break
                key = "\u001bOF"

            # page up
            when 33
                if ev.shiftKey
                    @scrollDisp -(@rows - 1)
                    return cancel(ev)
                else
                    key = "\u001b[5~"

            # page down
            when 34
                if ev.shiftKey
                    @scrollDisp @rows - 1
                    return cancel(ev)
                else
                    key = "\u001b[6~"

            # F1
            when 112
                key = "\u001bOP"

            # F2
            when 113
                key = "\u001bOQ"

            # F3
            when 114
                key = "\u001bOR"

            # F4
            when 115
                key = "\u001bOS"

            # F5
            when 116
                key = "\u001b[15~"

            # F6
            when 117
                key = "\u001b[17~"

            # F7
            when 118
                key = "\u001b[18~"

            # F8
            when 119
                key = "\u001b[19~"

            # F9
            when 120
                key = "\u001b[20~"

            # F10
            when 121
                key = "\u001b[21~"

            # F11
            when 122
                key = "\u001b[23~"

            # F12
            when 123
                key = "\u001b[24~"

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
                                setTimeout (->
                                    self.leaveVisual()
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
                        key = "\u001b" + String.fromCharCode(ev.keyCode + 32)
                    else if ev.keyCode is 192
                        key = "\u001b`"
                    else
                        key = "\u001b" + (ev.keyCode - 48) if ev.keyCode >= 48 and ev.keyCode <= 57

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

        # TODO
        # @emit "keydown", ev
        # @emit "key", key, ev
        @showCursor()
        cancel ev
