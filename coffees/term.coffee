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


# This has been forked from term.js
#
#   Copyright (c) 2012-2013, Christopher Jeffrey (MIT License)
#   https://github.com/chjj/term.js
#
#
# which has been forked from jslinux
#
#   Copyright (c) 2011 Fabrice Bellard
#   http://bellard.org/jslinux/


cancel = (ev) ->
  ev.preventDefault() if ev.preventDefault
  ev.stopPropagation() if ev.stopPropagation
  ev.cancelBubble = true
  false

s = 0
State =
  normal: s++
  escaped: s++
  csi: s++
  osc: s++
  charset: s++
  dcs: s++
  ignore: s++


class Terminal
  @hooks: {}
  # Mini implementation of event
  @on: (hook, fun) ->
    unless Terminal.hooks[hook]?
      Terminal.hooks[hook] = []
    Terminal.hooks[hook].push(fun)

  @off: (hook, fun) ->
    unless Terminal.hooks[hook]?
      Terminal.hooks[hook] = []
    Terminal.hooks[hook].pop(fun)

  constructor: (@parent, @out, @ctl=->) ->
    # Global elements
    @document = @parent.ownerDocument
    @html = @document.getElementsByTagName('html')[0]
    @body = @document.getElementsByTagName('body')[0]
    @forceWidth = @body.getAttribute(
      'data-force-unicode-width') is 'yes'

    # Main terminal element
    @body.className = 'terminal focus'
    @body.style.outline = 'none'
    @body.setAttribute 'tabindex', 0
    @body.setAttribute 'spellcheck', 'false'

    # Adding one line to compute char size
    div = @document.createElement('div')
    div.className = 'line'
    @body.appendChild(div)
    @children = [div]

    @computeCharSize()
    @cols = Math.floor(@body.clientWidth / @charSize.width)
    @rows = Math.floor(window.innerHeight / @charSize.height)
    px = window.innerHeight % @charSize.height
    @body.style['padding-bottom'] = "#{px}px"

    @scrollback = 1000000
    @buffSize = 100000

    @visualBell = 100
    @convertEol = false
    @termName = 'xterm'
    @cursorBlink = true
    @cursorState = 0

    @resetVars()

    @focus()

    @startBlink()
    addEventListener 'keydown', @keyDown.bind(@)
    addEventListener 'keyup', @keyUp.bind(@)
    addEventListener 'keypress', @keyPress.bind(@)
    addEventListener 'focus', @focus.bind(@)
    addEventListener 'blur', @blur.bind(@)
    addEventListener 'resize', => @resize()
    @body.addEventListener 'load', =>
      @nativeScrollTo()
    , true

    # # Horrible Firefox paste workaround
    if typeof InstallTrigger isnt "undefined"
      @body.contentEditable = 'true'

    @initmouse()
    addEventListener 'load', => @resize()
    @emit 'load'

  emit: (hook, args...) ->
    unless Terminal.hooks[hook]?
      Terminal.hooks[hook] = []
    for fun in Terminal.hooks[hook]
      fun.apply(@, args)

  cloneAttr: (a, char=null) ->
    bg: a.bg
    fg: a.fg
    ch: unless char is null then char else a.ch
    bold: a.bold
    underline: a.underline
    blink: a.blink
    inverse: a.inverse
    invisible: a.invisible
    italic: a.italic
    faint: a.faint
    crossed: a.crossed

  equalAttr: (a, b) ->
    # Not testing char
    (a.bg is b.bg and a.fg is b.fg and a.bold is b.bold and
     a.underline is b.underline and a.blink is b.blink and
      a.inverse is b.inverse and a.invisible is b.invisible and
      a.italic is b.italic and a.faint is b.faint and
      a.crossed is b.crossed)

  putChar: (c) ->
    if @insertMode
      @screen[@y + @shift].chars.splice(@x, 0, @cloneAttr @curAttr, c)
      @screen[@y + @shift].chars.pop()
    else
      @screen[@y + @shift].chars[@x] = @cloneAttr @curAttr, c

    @screen[@y + @shift].dirty = true

  resetVars: ->
    @x = 0
    @y = 0
    @cursorHidden = false
    @state = State.normal
    @queue = ''

    @scrollTop = 0
    @scrollBottom = @rows - 1
    @scrollLock = false

    # modes
    @applicationKeypad = false
    @applicationCursor = false
    @originMode = false
    @autowrap = true
    @horizontalWrap = false
    @normal = null

    # charset
    @charset = null
    @gcharset = null
    @glevel = 0
    @charsets = [null]

    # stream
    @defAttr =
      bg: 256
      fg: 257
      ch: " "
      bold: false
      underline: false
      blink: 0
      inverse: false
      invisible: false
      italic: false
      faint: false
      crossed: false

    @curAttr = @cloneAttr @defAttr
    @params = []
    @currentParam = 0
    @prefix = ""
    @screen = []
    i = @rows
    @shift = 0
    @screen.push @blankLine(false, false) while i--
    @setupStops()
    @skipNextKey = null

  computeCharSize: ->
    testSpan = document.createElement('span')
    testSpan.textContent = '0123456789'
    @children[0].appendChild(testSpan)
    @charSize =
      width: testSpan.getBoundingClientRect().width / 10
      height: @children[0].getBoundingClientRect().height
    @children[0].removeChild(testSpan)

  eraseAttr: ->
    erased = @cloneAttr @defAttr
    erased.bg = @curAttr.bg
    erased

  focus: ->
    old_sl = @scrollLock
    @scrollLock = true

    @send('\x1b[I') if @sendFocus
    @showCursor()
    @body.classList.add('focus')
    @body.classList.remove('blur')
    @resize()

    @scrollLock = old_sl

  blur: ->
    old_sl = @scrollLock
    @scrollLock = true

    @cursorState = 1
    @screen[@y + @shift].dirty = true
    @refresh()
    @send('\x1b[O') if @sendFocus
    @body.classList.add('blur')
    @body.classList.remove('focus')

    @scrollLock = old_sl

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
    sendButton = (ev) ->
      # get the xterm-style button
      button = getButton(ev)
      # get mouse coordinates
      pos = getCoords(ev)
      return unless pos

      sendEvent button, pos, ev.type
      pressed = button

    # motion example of a left click:
    # ^[[M 3<^[[M@4<^[[M@5<^[[M@6<^[[M@7<^[[M#7<
    sendMove = (ev) ->
      button = pressed
      pos = getCoords(ev)
      return unless pos

      # buttons marked as motions
      # are incremented by 32
      button += 32
      sendEvent button, pos, ev.type

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
    sendEvent = (button, pos, type) =>

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
        button -= 32
        @send "\x1b[<" + button + ";" + pos.x + ";" + pos.y + (
          if type is "mouseup" then "m" else "M"
        )
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
          button = if ev.button? then +ev.button else (
            if ev.which? then ev.which - 1 else null)
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
        unless @normalMouse
          mod = 0

      # increment to SP
      (32 + (mod << 2)) + button

    # mouse coordinates measured in cols/rows
    getCoords = (ev) =>
      x = ev.pageX
      y = ev.pageY - window.scrollY

      # convert to cols/rows
      w = @body.clientWidth
      h = window.innerHeight
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

    addEventListener "contextmenu", (ev) =>
      return unless @mouseEvents
      cancel ev

    addEventListener "mousedown", (ev) =>
      return unless @mouseEvents

      # send the button
      sendButton ev

      # fix for odd bug
      sm = sendMove.bind(this)
      addEventListener "mousemove", sm

      # x10 compatibility mode can't send button releases
      unless @x10Mouse
        addEventListener "mouseup", up = (ev) ->
          sendButton ev
          removeEventListener "mousemove", sm
          removeEventListener "mouseup", up
          cancel ev
      cancel ev

    addEventListener "wheel", (ev) =>
      if @mouseEvents
        return if @x10Mouse
        sendButton ev
        cancel ev

  refresh: (force=false) ->
    for cursor in @body.querySelectorAll(".cursor")
      cursor.parentNode.replaceChild(
        @document.createTextNode(cursor.textContent), cursor)
    for active in @body.querySelectorAll(".line.active")
      active.classList.remove('active')
    # for active in @body.querySelectorAll(".line.extended")
    #   active.classList.remove('extended')

    newOut = ''
    modified = []
    for line, j in @screen
      continue unless line.dirty or force
      out = ""

      if j is @y + @shift and not @cursorHidden
        x = @x
      else
        x = -Infinity

      attr = @cloneAttr @defAttr
      skipnext = false
      for i in [0..@cols - 1]
        data = line.chars[i]
        if data.html
          out += data.html
          break
        if skipnext
          skipnext = false
          continue

        ch = data.ch
        unless @equalAttr data, attr
          out += "</span>" unless @equalAttr attr, @defAttr
          unless @equalAttr data, @defAttr
            classes = []
            styles = []
            out += "<span "

            # bold
            classes.push "bold" if data.bold
            # underline
            classes.push "underline" if data.underline
            # blink
            classes.push "blink" if data.blink is 1
            classes.push "blink-fast" if data.blink is 2
            # inverse
            classes.push "reverse-video" if data.inverse
            # invisible
            classes.push "invisible" if data.invisible
            # italic
            classes.push "italic" if data.italic
            # faint
            classes.push "faint" if data.faint
            # crossed
            classes.push "crossed" if data.crossed

            if typeof data.fg is 'number'
              fg = data.fg
              if data.bold and fg < 8
                fg += 8
              classes.push "fg-color-" + fg

            if typeof data.fg is 'string'
              styles.push "color: " + data.fg

            if typeof data.bg is 'number'
              classes.push "bg-color-" + data.bg

            if typeof data.bg is 'string'
              styles.push "background-color: " + data.bg

            out += "class=\""
            out += classes.join(" ")
            out += "\""
            if styles.length
              out += " style=\"" + styles.join("; ") + "\""
            out += ">"

        out += "<span class=\"" + (
          if @cursorState then "reverse-video " else ""
        ) + "cursor\">" if i is x

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
              if ch == " "
                out += '<span class="nbsp">\u2007</span>'
              else if ch <= " "
                out += "&nbsp;"
              else if not @forceWidth or ch <= "~" # Ascii chars
                out += ch
              else if "\uff00" < ch < "\uffef"
                skipnext = true
                out += "<span style=\"display: inline-block;
                  width: #{2 * @charSize.width}px\">#{ch}</span>"
              else
                out += "<span style=\"display: inline-block;
                  width: #{@charSize.width}px\">#{ch}</span>"

        out += "</span>" if i is x
        attr = data
      out += "</span>" unless @equalAttr attr, @defAttr
      out += '\u23CE' if line.wrap
      if line.extra
        out += '<span class="extra">' + line.extra + '</span>'
      if @children[j]
        @children[j].innerHTML = out
        modified.push @children[j]
        if x isnt -Infinity
          @children[j].classList.add 'active'
        if line.extra
          @children[j].classList.add 'extended'
      else
        cls = ['line']
        if x isnt -Infinity
          cls.push 'active'
        if line.extra
          cls.push 'extended'
        newOut += "<div class=\"#{cls.join(' ')}\">#{out}</div>"
      @screen[j].dirty = false

    if newOut isnt ''
      group = @document.createElement('div')
      group.className = 'group'
      group.innerHTML = newOut
      modified.push group
      @body.appendChild group
      @screen = @screen.slice(-@rows)
      @shift = 0

      lines = document.querySelectorAll('.line')
      if lines.length > @scrollback
        for line in Array.prototype.slice.call(
          lines, 0, lines.length - @scrollback)
            line.remove()
        for group in document.querySelectorAll('.group:empty')
          group.remove()
        lines = document.querySelectorAll('.line')
      @children = Array.prototype.slice.call(
        lines, -@rows)

    @nativeScrollTo()
    @emit 'change', modified

  _cursorBlink: ->
    @cursorState ^= 1
    cursor = @body.querySelector(".cursor")
    return unless cursor
    if cursor.classList.contains("reverse-video")
      cursor.classList.remove "reverse-video"
    else
      cursor.classList.add "reverse-video"


  showCursor: ->
    unless @cursorState
      @cursorState = 1
      @screen[@y + @shift].dirty = true
      @refresh()


  startBlink: ->
    return unless @cursorBlink
    @_blinker = => @_cursorBlink()
    @t_blink = setInterval(@_blinker, 500)


  refreshBlink: ->
    return unless @cursorBlink
    clearInterval @t_blink
    @t_blink = setInterval(@_blinker, 500)


  scroll: ->
    # Use emulated scroll in alternate buffer or when scroll region is defined
    if @normal or @scrollTop isnt 0 or @scrollBottom isnt @rows - 1
      # inner scroll
      @screen.splice @shift + @scrollBottom + 1, 0, @blankLine()
      @screen.splice @shift + @scrollTop, 1

      for i in [@scrollTop..@scrollBottom]
        @screen[i + @shift].dirty = true
    else
      @screen.push @blankLine()
      @shift++

  unscroll: ->
    @screen.splice @shift + @scrollTop , 0, @blankLine(true)
    @screen.splice @shift + @scrollBottom + 1, 1

    for i in [@scrollTop..@scrollBottom]
      @screen[i + @shift].dirty = true


  nativeScrollTo: (scroll=2000000000) -> # ~ Max ff number
    return if @scrollLock
    window.scrollTo 0, scroll

  scrollDisplay: (disp) ->
    @nativeScrollTo window.scrollY + disp * @charSize.height

  nextLine: ->
    @y++
    if @y > @scrollBottom
      @y--
      @scroll()

  prevLine: ->
    @y--
    if @y < @scrollTop
      @y++
      @unscroll()

  write: (data) ->
    i = 0
    l = data.length
    while i < l
      ch = data.charAt(i)
      switch @state
        when State.normal
          switch ch

            # '\a'
            when "\x07"
              @bell()

            # '\n', '\v', '\f'
            when "\n", "\x0b", "\x0c"
              # @x = 0 if @convertEol
              if @horizontalWrap
                @screen[@y + @shift].extra += ch
              else
                @screen[@y + @shift].dirty = true
                @nextLine()

            # '\r'
            when "\r"
              unless @horizontalWrap
                @x = 0

            # '\b'
            when "\b"
              # Cap on overflow
              @x-- if @x >= @cols
              @x-- if @x > 0

            # '\t'
            when "\t"
              @x = @nextStop()

            # shift out
            when "\x0e"
              @setgLevel 1

            # shift in
            when "\x0f"
              @setgLevel 0

            # '\e'
            when "\x1b"
              @state = State.escaped

            else
              # Diacritical Marks
              if ("\u0300" <= ch <= "\u036F" or
                  "\u1AB0" <= ch <= "\u1AFF" or
                  "\u1DC0" <= ch <= "\u1DFF" or
                  "\u20D0" <= ch <= "\u20FF" or
                  "\uFE20" <= ch <= "\uFE2F")

                x = @x
                y = @y + @shift
                if @x > 0
                  x -= 1
                else if @y > 0
                  y -= 1
                  x = @cols - 1
                else
                  # ?!
                  break
                @screen[y].chars[x].ch += ch
                break

              if ch >= " "
                ch = @charset[ch] if @charset?[ch]
                if @x >= @cols
                  if @horizontalWrap
                    @screen[@y + @shift].extra += ch
                  else
                    if @autowrap
                      @screen[@y + @shift].wrap = true
                      @nextLine()
                    @x = 0
                @putChar ch
                @x++
                if @forceWidth and "\uff00" < ch < "\uffef"
                  if @cols < 2 or @x >= @cols
                    @putChar " "
                    break

                  @putChar " "
                  @x++

        when State.escaped
          switch ch
            # ESC [ Control Sequence Introducer ( CSI is 0x9b).
            when "["
              @params = []
              @currentParam = 0
              @state = State.csi

            # ESC ] Operating System Command ( OSC is 0x9d).
            when "]"
              @params = []
              @currentParam = 0
              @state = State.osc

            # ESC P Device Control String ( DCS is 0x90).
            when "P"
              @params = []
              @currentParam = 0
              @state = State.dcs

            # ESC _ Application Program Command ( APC is 0x9f).
            when "_"
              @state = State.ignore

            # ESC ^ Privacy Message ( PM is 0x9e).
            when "^"
              @state = State.ignore

            # ESC c Full Reset (RIS).
            when "c"
              @clearScrollback()
              @reset()

            # ESC E Next Line ( NEL is 0x85).
            when "E"
              @x = 0
              @index()

            # ESC D Index ( IND is 0x84).
            when "D"
              @index()

            # ESC M Reverse Index ( RI is 0x8d).
            when "M"
              @reverseIndex()

            # ESC % Select default/utf-8 character set.
            # @ = default, G = utf-8
            when "%"
              @setgLevel 0
              @setgCharset 0, Terminal::charsets.US
              @state = State.normal
              i++

            # ESC (,),*,+,-,. Designate G0-G2 Character Set.
            # <-- this seems to get all the attention
            when "(", ")" , "*" , "+" , "-" , "."
              switch ch
                when "("
                  @gcharset = 0
                when ")", "-"
                  @gcharset = 1
                when "*", "."
                  @gcharset = 2
                when "+"
                  @gcharset = 3
              @state = State.charset

            # Designate G3 Character Set (VT300).
            # A = ISO Latin-1 Supplemental.
            # Not implemented.
            when "/"
              @gcharset = 3
              @state = State.charset
              i--

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
              @state = State.normal

            # ESC 8 Restore Cursor (DECRC).
            when "8"
              @restoreCursor()
              @state = State.normal

            # ESC # 3 DEC line height/width
            when "#"
              @state = State.normal
              i++
              num = data.charAt(i)
              switch num
                when "3" # DECDHL
                  break
                when "4" # DECDHL
                  break
                when "5" # DECSWL
                  break
                when "6" # DECDWL
                  break
                when "8" # DECALN
                  for line in @screen
                    line.dirty = true
                    for c in [0..line.chars.length]
                      line.chars[c] = @cloneAttr @curAttr, "E"
                  @x = @y = 0

            # ESC H Tab Set (HTS is 0x88).
            when "H"
              @tabSet()

            # ESC = Application Keypad (DECPAM).
            when "="
              @applicationKeypad = true
              @state = State.normal

            # ESC > Normal Keypad (DECPNM).
            when ">"
              @applicationKeypad = false
              @state = State.normal
            else
              @state = State.normal
              console.log "Unknown ESC control:", ch

        when State.charset
          switch ch
            when "0" # DEC Special Character and Line Drawing Set.
              cs = Terminal::charsets.SCLD
            when "A" # UK
              cs = Terminal::charsets.UK
            when "B" # United States (USASCII).
              cs = Terminal::charsets.US
            when "4" # Dutch
              cs = Terminal::charsets.Dutch
            # Finnish
            when "C", "5"
              cs = Terminal::charsets.Finnish
            when "R" # French
              cs = Terminal::charsets.French
            when "Q" # FrenchCanadian
              cs = Terminal::charsets.FrenchCanadian
            when "K" # German
              cs = Terminal::charsets.German
            when "Y" # Italian
              cs = Terminal::charsets.Italian
            # NorwegianDanish
            when "E", "6"
              cs = Terminal::charsets.NorwegianDanish
            when "Z" # Spanish
              cs = Terminal::charsets.Spanish
            # Swedish
            when "H", "7"
              cs = Terminal::charsets.Swedish
            when "=" # Swiss
              cs = Terminal::charsets.Swiss
            when "/" # ISOLatin (actually /A)
              cs = Terminal::charsets.ISOLatin
              i++
            else # Default
              cs = Terminal::charsets.US
          @setgCharset @gcharset, cs
          @gcharset = null
          @state = State.normal

        when State.osc
          # OSC Ps ; Pt ST
          # OSC Ps ; Pt BEL
          #     Set Text Parameters.
          if ch is "\x1b" or ch is "\x07"
            i++ if ch is "\x1b"
            @params.push @currentParam
            switch @params[0]
              when 0, 1, 2
                if @params[1]
                  @title = @params[1] + " - ƸӜƷ butterfly"
                  @handleTitle @title

            # reset colors
            @params = []
            @currentParam = 0
            @state = State.normal
          else
            unless @params.length
              if ch >= "0" and ch <= "9"
                @currentParam = @currentParam * 10 + ch.charCodeAt(0) - 48
              else if ch is ";"
                @params.push @currentParam
                @currentParam = ""
            else
              @currentParam += ch

        when State.csi
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
            break

          # Ignore garbage characters
          if ch <= " " or ch >= "~"
            if ch is '\b'
              @currentParam = (@currentParam / 10) & 1
            if ch is '\r'
              @x = 0
            if ["\n", "\x0b", "\x0c"].indexOf(ch) >= 0
              @screen[@y + @shift].dirty = true
              @nextLine()
            break

          @params.push @currentParam
          @currentParam = 0

          # ';'
          break if ch is ";"
          @state = State.normal
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
              @charAttributes @params unless @prefix

            # CSI Ps n    Device Status Report (DSR).
            when "n"
              @deviceStatus @params

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
              if @prefix is '!'
                @softReset @params

            else
              console.error "Unknown CSI code: %s (%d).", ch, ch.charCodeAt(0)
          @prefix = ""

        when State.dcs
          if ch is "\x1b" or ch is "\x07"
            i++ if ch is "\x1b"
            switch @prefix
              # User-Defined Keys (DECUDK).
              when ""
                pt = @currentParam
                unless pt[0] is ';'
                  console.error "Unknown DECUDK: #{pt}"
                  break
                pt = pt.slice(1)

                [type, content] = pt.split('|', 2)

                if not content
                  console.error "No type for inline DECUDK: #{pt}"
                  break

                switch type
                  when "HTML"
                    safe = html_sanitize(content, (l) -> l)
                    attr = @cloneAttr @curAttr
                    attr.html = (
                      "<div class=\"inline-html\">#{safe}</div>")
                    @screen[@y + @shift].chars[@x] = attr
                    @resetLine @screen[@y + @shift]
                    @nextLine()

                  when "IMAGE"
                    # Prevent injection
                    content = encodeURI content

                    if content.indexOf(';')
                      mime = content.slice(0, content.indexOf(';'))
                      b64 = content.slice(content.indexOf(';') + 1)
                    else
                      mime = 'image'
                      b64 = content
                    attr = @cloneAttr @curAttr
                    attr.html = (
                      "<img class=\"inline-image\" src=\"data:#{mime};base64,#{
                        b64}\" />")
                    @screen[@y + @shift].chars[@x] = attr
                    @resetLine @screen[@y + @shift]

                  when "PROMPT"
                    @send content

                  when "TEXT"
                    l += content.length
                    data = data.slice(0, i + 1) + content + data.slice(i + 1)

                  else
                    console.error "Unknown type #{type} for DECUDK"

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
                    console.error "Unknown DCS Pt: %s.", pt
                    pt = ""

                @send "\x1bP" + +valid + "$r" + pt + "\x1b\\"

              when "+q"
                pt = @currentParam
                valid = false
                @send "\x1bP" + +valid + "+r" + pt + "\x1b\\"

              else
                console.error "Unknown DCS prefix: %s.", @prefix

            @currentParam = 0
            @prefix = ""
            @state = State.normal

          else unless @currentParam
            if not @prefix and ch isnt "$" and ch isnt "+"
              @currentParam = ch
            else if @prefix.length is 2
              @currentParam = ch
            else
              @prefix += ch
          else
            @currentParam += ch

        when State.ignore
          # For PM and APC.
          if ch is "\x1b" or ch is "\x07"
            i++ if ch is "\x1b"
            @state = State.normal
      i++

    @screen[@y + @shift].dirty = true
    @refresh()

  writeln: (data) ->
    @write "#{data}\r\n"

  keyUp: (ev) ->
    if ev.keyCode is 19  # Pause break
      return unless @stop?
      @body.classList.remove 'stopped'
      @stop = null
      @out '\x03\n'

  keyDown: (ev) ->
    # Key Resources:
    # https://developer.mozilla.org/en-US/docs/DOM/KeyboardEvent
    # Don't handle modifiers alone
    return true if ev.keyCode > 15 and ev.keyCode < 19

    if ev.keyCode is 19  # Pause break
      return if @stop?
      @body.classList.add 'stopped'
      @stop = 0
      @out '\x03'
      return false

    # Handle shift insert and ctrl insert
    # copy/paste usefull for typematrix keyboard
    return true if (ev.shiftKey or ev.ctrlKey) and ev.keyCode is 45

    # Let the ctrl+shift+c, ctrl+shift+v go through to handle native copy paste
    return true if (ev.shiftKey and ev.ctrlKey) and ev.keyCode in [67, 86]

    # Alt-z works as an escape to relay the following keys to the browser.
    # usefull to trigger browser shortcuts, i.e.: Alt+Z F5 to reload
    # May be redundant with keyPrefix
    if ev.altKey and ev.keyCode is 90 and not @skipNextKey
      @skipNextKey = true
      @body.classList.add('skip')
      return cancel(ev)

    if @skipNextKey
      @skipNextKey = false
      @body.classList.remove('skip')
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
        key = "\x1b[D"

      # right-arrow
      when 39
        if @applicationCursor
          key = "\x1bOC"
          break
        key = "\x1b[C"

      # up-arrow
      when 38
        if @applicationCursor
          key = "\x1bOA"
          break
        if ev.ctrlKey
          @scrollDisplay -1
          return cancel(ev)
        else
          key = "\x1b[A"

      # down-arrow
      when 40
        if @applicationCursor
          key = "\x1bOB"
          break
        if ev.ctrlKey
          @scrollDisplay 1
          return cancel(ev)
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
        key = "\x1b[H"

      # end
      when 35
        if @applicationKeypad
          key = "\x1bOF"
          break
        key = "\x1b[F"

      # page up
      when 33
        if ev.shiftKey
          break if ev.ctrlKey
          @scrollDisplay -(@rows - 1)
          return cancel(ev)
        else
          key = "\x1b[5~"

      # page down
      when 34
        if ev.shiftKey
          break if ev.ctrlKey
          @scrollDisplay @rows - 1
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

      # Scroll lock
      when 145
        @scrollLock = ! @scrollLock
        if @scrollLock
          @body.classList.add 'locked'
        else
          @body.classList.remove 'locked'
        return cancel(ev)

      else
        # a-z and space
        if ev.ctrlKey
          if ev.keyCode >= 65 and ev.keyCode <= 90
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
            if ev.keyCode is 221
              key = String.fromCharCode(29)

        else if (ev.altKey and 'Mac' not in navigator.platform) or
           (ev.metaKey and 'Mac' in navigator.platform)
          if ev.keyCode >= 65 and ev.keyCode <= 90
            key = "\x1b" + String.fromCharCode(ev.keyCode + 32)
          else if ev.keyCode is 192
            key = "\x1b`"
          else
            if ev.keyCode >= 48 and ev.keyCode <= 57
              key = "\x1b" + (ev.keyCode - 48)

    if ev.keyCode >= 37 and ev.keyCode <= 40
      if ev.ctrlKey
        key = key.slice(0, -1) + "1;5" + key.slice(-1)
      else if ev.altKey
        key = key.slice(0, -1) + "1;3" + key.slice(-1)
      else if ev.shiftKey
        key = key.slice(0, -1) + "1;4" + key.slice(-1)

    return true unless key

    @showCursor()
    @send(key)
    cancel ev


  setgLevel: (g) ->
    @glevel = g
    @charset = @charsets[g]

  setgCharset: (g, charset) ->
    @charsets[g] = charset
    @charset = charset if @glevel is g

  keyPress: (ev) ->
    if @skipNextKey is false
      @skipNextKey = null
      return true

    # Don't handle modifiers alone
    return true if ev.keyCode > 15 and ev.keyCode < 19

    # Handle shift insert and ctrl insert
    # copy/paste usefull for typematrix keyboard
    return true if (ev.shiftKey or ev.ctrlKey) and ev.keyCode is 45

    # Let the ctrl+shift+c, ctrl+shift+v go through to handle native copy paste
    return true if (ev.shiftKey and ev.ctrlKey) and ev.keyCode in [67, 86]

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
    @send key
    false

  bell: (cls="bell")->
    return unless @visualBell
    @body.classList.add cls
    @t_bell = setTimeout (=>
      @body.classList.remove cls
    ), @visualBell

  resize: (x=null, y=null, notif=false) ->
    oldCols = @cols
    oldRows = @rows
    @computeCharSize()
    w = @body.clientWidth
    h = @html.clientHeight - (@html.offsetHeight - @html.scrollHeight)
    @cols = x or Math.floor(w / @charSize.width)
    @rows = y or Math.floor(h / @charSize.height)
    px = h % @charSize.height
    @body.style['padding-bottom'] = "#{px}px"

    @cols = Math.max 1, @cols
    @rows = Math.max 1, @rows
    @nativeScrollTo()

    if (not x and not y) and oldCols == @cols and oldRows == @rows
      return

    @ctl 'Resize', @cols, @rows unless notif

    # resize cols
    if oldCols < @cols
      # does xterm use the default attr?
      i = @screen.length
      while i--
        @screen[i].chars.push @defAttr while @screen[i].chars.length < @cols
        @screen[i].wrap = false

    else if oldCols > @cols
      i = @screen.length
      while i--
        @screen[i].chars.pop() while @screen[i].chars.length > @cols

    @setupStops oldCols

    # resize rows
    j = oldRows
    if j < @rows
      el = @body
      while j++ < @rows
        @screen.push @blankLine() if @screen.length < @rows
        if @children.length < @rows
          line = @document.createElement("div")
          line.className = 'line'
          el.appendChild line
          @children.push line
    else if j > @rows
      while j-- > @rows
        @screen.pop() if @screen.length > @rows
        if @children.length > @rows
          el = @children.pop()
          el?.parentNode.removeChild el

    if @normal
      # resize cols
      if oldCols < @cols
        # does xterm use the default attr?
        i = @normal.screen.length
        while i--
          while @normal.screen[i].chars.length < @cols
            @normal.screen[i].chars.push @defAttr
          @normal.screen[i].wrap = false

      else if oldCols > @cols
        i = @normal.screen.length
        while i--
          while @normal.screen[i].chars.length > @cols
            @normal.screen[i].chars.pop()

      # resize rows
      j = oldRows
      if j < @rows
        while j++ < @rows
          @normal.screen.push @blankLine() if @normal.screen.length < @rows
      else if j > @rows
        while j-- > @rows
          @normal.screen.pop() if @normal.screen.length > @rows

    # make sure the cursor stays on screen
    @y = @rows - 1 if @y >= @rows
    @x = @cols - 1 if @x >= @cols

    @scrollTop = 0
    @scrollBottom = @rows - 1

    @refresh(true)
    @reset() if not notif and (x or y)

  resizeWindowPlease: (cols) ->
    # This is only when running butterfly in app mode when resizeTo is available
    margin = window.innerWidth - @body.clientWidth
    width = cols * @charSize.width + margin
    resizeTo width, window.innerHeight

  setupStops: (i) ->
    if i?
      i = @prevStop(i) unless @tabs[i]
    else
      @tabs = {}
      i = 0
    while i < @cols
      @tabs[i] = true
      i += 8

  prevStop: (x) ->
    x = @x unless x?
    while not @tabs[--x] and x > 0
      1

    if x >= @cols then @cols - 1 else (if x < 0 then 0 else x)

  nextStop: (x) ->
    x = @x unless x?
    while not @tabs[++x] and x < @cols
      1

    if x >= @cols then @cols - 1 else (if x < 0 then 0 else x)

  eraseRight: (x, y) ->
    line = @screen[y + @shift].chars
    # xterm

    while x < @cols
      line[x] = @eraseAttr()
      x++
    @resetLine @screen[y + @shift]

  eraseLeft: (x, y) ->
    x++
    @screen[y + @shift].chars[x] = @eraseAttr() while x--
    @resetLine @screen[y + @shift]

  eraseLine: (y) ->
    @eraseRight 0, y

  resetLine: (l) ->
    l.dirty = true
    l.wrap = false
    l.extra = ''

  blankLine: (cur=false, dirty=true) ->
    attr = (if cur then @eraseAttr() else @defAttr)
    line = []
    i = 0
    while i < @cols
      line[i] = attr
      i++

    chars: line
    dirty: dirty
    wrap: false
    extra: ''

  ch: (cur) ->
    if cur then @eraseAttr() else @defAttr

  isterm: (term) ->
    "#{@termName}".indexOf(term) is 0

  send: (data) ->
    @out data

  handleTitle: (title) ->
    document.title = title

  ## ESC ##

  # ESC D Index (IND is 0x84).
  index: ->
    @nextLine()
    @state = State.normal

  # ESC M Reverse Index (RI is 0x8d).
  reverseIndex: ->
    @prevLine()
    @state = State.normal

  # ESC c Full Reset (RIS).
  reset: ->
    @resetVars()
    @refresh(true)

  clearScrollback: ->
    # In case of real hard reset
    # Drop DOM history
    lines = document.querySelectorAll('.line')
    if lines.length > @rows
      for line in Array.prototype.slice.call(
        lines, 0, lines.length - @rows)
          line.remove()
      for group in document.querySelectorAll('.group:empty')
        group.remove()
      lines = document.querySelectorAll('.line')
    @children = Array.prototype.slice.call(
      lines, -@rows)


  # ESC H Tab Set (HTS is 0x88).
  tabSet: ->
    @tabs[@x] = true
    @state = State.normal


  ## CSI ##

  # CSI Ps A
  # Cursor Up Ps Times (default = 1) (CUU).
  cursorUp: (params) ->
    param = params[0]
    param = 1 if param < 1
    @y -= param
    @y = 0 if @y < 0

  # CSI Ps B
  # Cursor Down Ps Times (default = 1) (CUD).
  cursorDown: (params) ->
    param = params[0]
    param = 1 if param < 1
    @y += param
    @y = @rows - 1 if @y >= @rows

  # CSI Ps C
  # Cursor Forward Ps Times (default = 1) (CUF).
  cursorForward: (params) ->
    param = params[0]
    param = 1 if param < 1
    @x += param
    @x = @cols - 1 if @x >= @cols

  # CSI Ps D
  # Cursor Backward Ps Times (default = 1) (CUB).
  cursorBackward: (params) ->
    param = params[0]
    param = 1 if param < 1
    @x -= param
    @x = 0 if @x < 0

  # CSI Ps ; Ps H
  # Cursor Position [row;column] (default = [1,1]) (CUP).
  cursorPos: (params) ->
    row = params[0] - 1
    if params.length >= 2
      col = params[1] - 1
    else
      col = 0

    if row < 0
      row = 0
    else
      row = @rows - 1 if row >= @rows

    if col < 0
      col = 0
    else
      col = @cols - 1 if col >= @cols

    @x = col
    @y = row + if @originMode then @scrollTop else 0

  # CSI Ps J    Erase in Display (ED).
  #         Ps = 0    -> Erase Below (default).
  #         Ps = 1    -> Erase Above.
  #         Ps = 2    -> Erase All.
  #         Ps = 3    -> Erase Saved Lines (xterm).
  # CSI ? Ps J
  #     Erase in Display (DECSED).
  #         Ps = 0    -> Selective Erase Below (default).
  #         Ps = 1    -> Selective Erase Above.
  #         Ps = 2    -> Selective Erase All.
  eraseInDisplay: (params) ->
    switch params[0]
      when 0
        @eraseRight @x, @y
        j = @y + 1
        while j < @rows
          @eraseLine j
          j++
      when 1
        @eraseLeft @x, @y
        j = @y
        @eraseLine j while j--
      when 2
        j = @rows
        @eraseLine j while j--


  # CSI Ps K    Erase in Line (EL).
  #         Ps = 0    -> Erase to Right (default).
  #         Ps = 1    -> Erase to Left.
  #         Ps = 2    -> Erase All.
  # CSI ? Ps K
  #     Erase in Line (DECSEL).
  #         Ps = 0    -> Selective Erase to Right (default).
  #         Ps = 1    -> Selective Erase to Left.
  #         Ps = 2    -> Selective Erase All.
  eraseInLine: (params) ->
    switch params[0]
      when 0
        @eraseRight @x, @y
      when 1
        @eraseLeft @x, @y
      when 2
        @eraseLine @y


  # CSI Pm m    Character Attributes (SGR).
  #         Ps = 0      -> Normal (default).
  #         Ps = 1      -> Bold.
  #         Ps = 2      -> Faint
  #         Ps = 3      -> Italic
  #         Ps = 4      -> Underlined.
  #         Ps = 5      -> Blink.
  #         Ps = 6      -> Blink rapid
  #         Ps = 7      -> Inverse.
  #         Ps = 8      -> Invisible, i.e., hidden (VT300).
  #         Ps = 9      -> Crossed out
  #         Ps = 1 0    -> Primary font

  #         Ps = 2 1    -> Bold off
  #         Ps = 2 2    -> Normal (neither bold nor faint).
  #         Ps = 2 3    -> Non italic
  #         Ps = 2 4    -> Not underline.
  #         Ps = 2 5    -> Steady (not blinking).
  #         Ps = 2 7    -> Positive (not inverse).
  #         Ps = 2 8    -> Visible, i.e., not hidden (VT300).
  #         Ps = 2 9    -> Not crossed out
  #         Ps = 3 0    -> Set foreground color to Black.
  #         Ps = 3 1    -> Set foreground color to Red.
  #         Ps = 3 2    -> Set foreground color to Green.
  #         Ps = 3 3    -> Set foreground color to Yellow.
  #         Ps = 3 4    -> Set foreground color to Blue.
  #         Ps = 3 5    -> Set foreground color to Magenta.
  #         Ps = 3 6    -> Set foreground color to Cyan.
  #         Ps = 3 7    -> Set foreground color to White.
  #         Ps = 3 9    -> Set foreground color to default (original).
  #         Ps = 4 0    -> Set background color to Black.
  #         Ps = 4 1    -> Set background color to Red.
  #         Ps = 4 2    -> Set background color to Green.
  #         Ps = 4 3    -> Set background color to Yellow.
  #         Ps = 4 4    -> Set background color to Blue.
  #         Ps = 4 5    -> Set background color to Magenta.
  #         Ps = 4 6    -> Set background color to Cyan.
  #         Ps = 4 7    -> Set background color to White.
  #         Ps = 4 9    -> Set background color to default (original).

  #     If 16-color support is compiled, the following apply.    Assume
  #     that xterm's resources are set so that the ISO color codes are
  #     the first 8 of a set of 16.    Then the aixterm colors are the
  #     bright versions of the ISO colors:
  #         Ps = 9 0    -> Set foreground color to Black.
  #         Ps = 9 1    -> Set foreground color to Red.
  #         Ps = 9 2    -> Set foreground color to Green.
  #         Ps = 9 3    -> Set foreground color to Yellow.
  #         Ps = 9 4    -> Set foreground color to Blue.
  #         Ps = 9 5    -> Set foreground color to Magenta.
  #         Ps = 9 6    -> Set foreground color to Cyan.
  #         Ps = 9 7    -> Set foreground color to White.
  #         Ps = 1 0 0    -> Set background color to Black.
  #         Ps = 1 0 1    -> Set background color to Red.
  #         Ps = 1 0 2    -> Set background color to Green.
  #         Ps = 1 0 3    -> Set background color to Yellow.
  #         Ps = 1 0 4    -> Set background color to Blue.
  #         Ps = 1 0 5    -> Set background color to Magenta.
  #         Ps = 1 0 6    -> Set background color to Cyan.
  #         Ps = 1 0 7    -> Set background color to White.

  #     If xterm is compiled with the 16-color support disabled, it
  #     supports the following, from rxvt:
  #         Ps = 1 0 0    -> Set foreground and background color to
  #         default.

  #     If 88- or 256-color support is compiled, the following apply.
  #         Ps = 3 8    ; 5    ; Ps -> Set foreground color to the second
  #         Ps.
  #         Ps = 4 8    ; 5    ; Ps -> Set background color to the second
  #         Ps.
  charAttributes: (params) ->
    # Optimize a single SGR0.
    if params.length is 1 and params[0] is 0
      @curAttr = @cloneAttr @defAttr
      return
    l = params.length
    i = 0
    while i < l
      p = params[i]
      if p >= 30 and p <= 37
        # fg color 8
        @curAttr.fg = p - 30
      else if p >= 40 and p <= 47
        # bg color 8
        @curAttr.bg = p - 40
      else if p >= 90 and p <= 97
        # fg color 16
        p += 8
        @curAttr.fg = p - 90
      else if p >= 100 and p <= 107
        # bg color 16
        p += 8
        @curAttr.bg = p - 100
      else if p is 0
        # default
        @curAttr = @cloneAttr @defAttr
      else if p is 1
        # bold text
        @curAttr.bold = true
      else if p is 2
        # bold text
        @curAttr.faint = true
      else if p is 3
        # italic text
        @curAttr.italic = true
      else if p is 4
        # underline text
        @curAttr.underline = true
      else if p is 5
        # blink
        @curAttr.blink = 1
      else if p is 6
        # blink fast
        @curAttr.blink = 2
      else if p is 7
        # inverse and positive
        # test with: echo -e '\e[31m\e[42mhello\e[7mworld\e[27mhi\e[m'
        @curAttr.inverse = true
      else if p is 8
        # invisible
        @curAttr.invisible = true
      else if p is 9
        # crossed out
        @curAttr.crossed = true
      else if p is 10
        # Primary Font
        # ignoring
        undefined
      else if p is 21
        # bold off
        @curAttr.bold = false
      else if p is 22
        # not bold
        @curAttr.bold = false
        @curAttr.faint = false
      else if p is 23
        # not italic
        @curAttr.italic = false
      else if p is 24
        # not underline
        @curAttr.underline = false
      else if p is 25
        # not blink
        @curAttr.blink = false
      else if p is 27
        # not inverse
        @curAttr.inverse = false
      else if p is 28
        # not invisible
        @curAttr.invisible = false
      else if p is 29
        # not crossed out
        @curAttr.crossed = false
      else if p is 39
        # reset fg
        @curAttr.fg = 257
      else if p is 49
        # reset bg
        @curAttr.bg = 256
      else if p is 38
        if params[i + 1] is 2
          # fg color 2^24
          i += 2
          @curAttr.fg = "rgb(#{params[i]}, #{params[i+1]}, #{params[i+2]})"
          i += 2
        else if params[i + 1] is 5
          # fg color 256
          i += 2
          @curAttr.fg = params[i] & 0xff
      else if p is 48
        if params[i + 1] is 2
          # bg color 2^24
          i += 2
          @curAttr.bg = "rgb(#{params[i]}, #{params[i+1]}, #{params[i+2]})"
          i += 2
        else if params[i + 1] is 5
          # bg color 256
          i += 2
          @curAttr.bg = params[i] & 0xff
      else if p is 100
        # reset fg/bg
        @curAttr.fg = 257
        @curAttr.bg = 256
      else
        console.error "Unknown SGR attribute: %d.", p
      i++

  # CSI Ps n    Device Status Report (DSR).
  #         Ps = 5    -> Status Report.    Result (``OK'') is
  #     CSI 0 n
  #         Ps = 6    -> Report Cursor Position (CPR) [row;column].
  #     Result is
  #     CSI r ; c R
  # CSI ? Ps n
  #     Device Status Report (DSR, DEC-specific).
  #         Ps = 6    -> Report Cursor Position (CPR) [row;column] as CSI
  #         ? r ; c R (assumes page is zero).
  #         Ps = 1 5    -> Report Printer status as CSI ? 1 0    n    (ready).
  #         or CSI ? 1 1    n    (not ready).
  #         Ps = 2 5    -> Report UDK status as CSI ? 2 0    n    (unlocked)
  #         or CSI ? 2 1    n    (locked).
  #         Ps = 2 6    -> Report Keyboard status as
  #     CSI ? 2 7    ;    1    ;    0    ;    0    n    (North American).
  #     The last two parameters apply to VT400 & up, and denote key-
  #     board ready and LK01 respectively.
  #         Ps = 5 3    -> Report Locator status as
  #     CSI ? 5 3    n    Locator available, if compiled-in, or
  #     CSI ? 5 0    n    No Locator, if not.
  deviceStatus: (params) ->
    unless @prefix
      switch params[0]
        when 5
          # status report
          @send "\x1b[0n"
        when 6
          # cursor position
          @send "\x1b[" + (@y + 1) + ";" + (@x + 1) + "R"
    else if @prefix is "?"
      # modern xterm doesnt seem to
      # respond to any of these except ?6, 6, and 5
      if params[0] is 6
        # cursor position
        @send "\x1b[?" + (@y + 1) + ";" + (@x + 1) + "R"

      # Custom DSR
      if params[0] is 99
        # Geo position
        unless navigator.geolocation?.getCurrentPosition?
          @send '\x1b[?R'
          return
        navigator.geolocation?.getCurrentPosition (position) =>
          @send (
            "\x1b[?" + position.coords.latitude + ";" +
             position.coords.longitude + "R")
        , (error) =>
          @send '\x1b[?R'


  ## Additions ##

  # CSI Ps @
  # Insert Ps (Blank) Character(s) (default = 1) (ICH).
  insertChars: (params) ->
    param = params[0]
    param = 1 if param < 1
    row = @y
    j = @x
    # xterm
    while param-- and j < @cols
      @screen[row + @shift].chars.splice j++, 0, [@eraseAttr(), true]
      @screen[row + @shift].chars.pop()
    @screen[row + @shift].dirty = true


  # CSI Ps E
  # Cursor Next Line Ps Times (default = 1) (CNL).
  # same as CSI Ps B ?
  cursorNextLine: (params) ->
    param = params[0]
    param = 1 if param < 1
    @y += param
    @y = @rows - 1 if @y >= @rows
    @x = 0


  # CSI Ps F
  # Cursor Preceding Line Ps Times (default = 1) (CNL).
  # reuse CSI Ps A ?
  cursorPrecedingLine: (params) ->
    param = params[0]
    param = 1    if param < 1
    @y -= param
    @y = 0    if @y < 0
    @x = 0


  # CSI Ps G
  # Cursor Character Absolute    [column] (default = [row,1]) (CHA).
  cursorCharAbsolute: (params) ->
    param = params[0]
    param = 1 if param < 1
    @x = param - 1

  # CSI Ps L
  # Insert Ps Line(s) (default = 1) (IL).
  # test: echo -e '\e[44m\e[1L\e[0m'
  insertLines: (params) ->
    param = params[0]
    param = 1 if param < 1

    while param--
      @screen.splice @y + @shift, 0, @blankLine(true)
      # blankLine(true) - xterm/linux behavior
      @screen.splice @scrollBottom + 1 + @shift, 1

    for i in [@y + @shift..@screen.length - 1]
      @screen[i].dirty = true

  # CSI Ps M
  # Delete Ps Line(s) (default = 1) (DL).
  deleteLines: (params) ->
    param = params[0]
    param = 1 if param < 1

    while param--
      # test: echo -e '\e[44m\e[1M\e[0m'
      # blankLine(true) - xterm/linux behavior
      @screen.splice @scrollBottom + @shift, 0, @blankLine(true)
      @screen.splice @y + @shift, 1
      unless @normal or @scrollTop isnt 0 or @scrollBottom isnt @rows - 1
        @children[@y + @shift].remove()
        @children.splice @y + @shift, 1

    if @normal or @scrollTop isnt 0 or @scrollBottom isnt @rows - 1
      for i in [@y + @shift..@screen.length - 1]
        @screen[i].dirty = true

  # CSI Ps P
  # Delete Ps Character(s) (default = 1) (DCH).
  deleteChars: (params) ->
    param = params[0]
    param = 1 if param < 1

    while param--
      @screen[@y + @shift].chars.splice @x, 1
      @screen[@y + @shift].chars.push @eraseAttr()
    @resetLine @screen[@y + @shift]

  # CSI Ps X
  # Erase Ps Character(s) (default = 1) (ECH).
  eraseChars: (params) ->
    param = params[0]
    param = 1 if param < 1
    j = @x
    # xterm
    @screen[@y + @shift].chars[j++] = @eraseAttr() while param-- and j < @cols
    @resetLine @screen[@y + @shift]

  # CSI Pm `    Character Position Absolute
  #     [column] (default = [row,1]) (HPA).
  charPosAbsolute: (params) ->
    param = params[0]
    param = 1 if param < 1
    @x = param - 1
    @x = @cols - 1 if @x >= @cols


  # 141 61 a * HPR -
  # Horizontal Position Relative
  # reuse CSI Ps C ?
  HPositionRelative: (params) ->
    param = params[0]
    param = 1 if param < 1
    @x += param
    @x = @cols - 1 if @x >= @cols


  # CSI Ps c    Send Device Attributes (Primary DA).
  #         Ps = 0    or omitted -> request attributes from terminal.    The
  #         response depends on the decTerminalID resource setting.
  #         -> CSI ? 1 ; 2 c    (``VT100 with Advanced Video Option'')
  #         -> CSI ? 1 ; 0 c    (``VT101 with No Options'')
  #         -> CSI ? 6 c    (``VT102'')
  #         -> CSI ? 6 0 ; 1 ; 2 ; 6 ; 8 ; 9 ; 1 5 ; c    (``VT220'')
  #     The VT100-style response parameters do not mean anything by
  #     themselves.    VT220 parameters do, telling the host what fea-
  #     tures the terminal supports:
  #         Ps = 1    -> 132-columns.
  #         Ps = 2    -> Printer.
  #         Ps = 6    -> Selective erase.
  #         Ps = 8    -> User-defined keys.
  #         Ps = 9    -> National replacement character sets.
  #         Ps = 1 5    -> Technical characters.
  #         Ps = 2 2    -> ANSI color, e.g., VT525.
  #         Ps = 2 9    -> ANSI text locator (i.e., DEC Locator mode).
  # CSI > Ps c
  #     Send Device Attributes (Secondary DA).
  #         Ps = 0    or omitted -> request the terminal's identification
  #         code.    The response depends on the decTerminalID resource set-
  #         ting.    It should apply only to VT220 and up, but xterm extends
  #         this to VT100.
  #         -> CSI    > Pp ; Pv ; Pc c
  #     where Pp denotes the terminal type
  #         Pp = 0    -> ``VT100''.
  #         Pp = 1    -> ``VT220''.
  #     and Pv is the firmware version (for xterm, this was originally
  #     the XFree86 patch number, starting with 95).    In a DEC termi-
  #     nal, Pc indicates the ROM cartridge registration number and is
  #     always zero.
  # More information:
  #     xterm/charproc.c - line 2012, for more information.
  #     vim responds with ^[[?0c or ^[[?1c after the terminal's response (?)
  sendDeviceAttributes: (params) ->
    return if params[0] > 0
    unless @prefix
      if @isterm("xterm") or @isterm("rxvt-unicode") or @isterm("screen")
        @send "\x1b[?1;2c"
      else @send "\x1b[?6c"    if @isterm("linux")

    else if @prefix is ">"
      # xterm and urxvt
      # seem to spit this
      # out around ~370 times (?).
      if @isterm("xterm")
        @send "\x1b[>0;276;0c"
      else if @isterm("rxvt-unicode")
        @send "\x1b[>85;95;0c"
      else if @isterm("linux")
        # not supported by linux console.
        # linux console echoes parameters.
        @send params[0] + "c"
      else @send "\x1b[>83;40003;0c"    if @isterm("screen")


  # CSI Pm d
  # Line Position Absolute    [row] (default = [1,column]) (VPA).
  linePosAbsolute: (params) ->
    param = params[0]
    param = 1 if param < 1
    @y = param - 1
    @y = @rows - 1 if @y >= @rows


  # 145 65 e * VPR - Vertical Position Relative
  # reuse CSI Ps B ?
  VPositionRelative: (params) ->
    param = params[0]
    param = 1 if param < 1
    @y += param
    @y = @rows - 1 if @y >= @rows


  # CSI Ps ; Ps f
  #     Horizontal and Vertical Position [row;column] (default =
  #     [1,1]) (HVP).
  HVPosition: (params) ->
    params[0] = 1 if params[0] < 1
    params[1] = 1 if params[1] < 1
    @y = params[0] - 1
    @y = @rows - 1 if @y >= @rows
    @x = params[1] - 1
    @x = @cols - 1 if @x >= @cols


  # CSI Pm h    Set Mode (SM).
  #         Ps = 2    -> Keyboard Action Mode (AM).
  #         Ps = 4    -> Insert Mode (IRM).
  #         Ps = 1 2    -> Send/receive (SRM).
  #         Ps = 2 0    -> Automatic Newline (LNM).
  # CSI ? Pm h
  #     DEC Private Mode Set (DECSET).
  #         Ps = 1    -> Application Cursor Keys (DECCKM).
  #         Ps = 2    -> Designate USASCII for character sets G0-G3
  #         (DECANM), and set VT100 mode.
  #         Ps = 3    -> 132 Column Mode (DECCOLM).
  #         Ps = 4    -> Smooth (Slow) Scroll (DECSCLM).
  #         Ps = 5    -> Reverse Video (DECSCNM).
  #         Ps = 6    -> Origin Mode (DECOM).
  #         Ps = 7    -> Wraparound Mode (DECAWM).
  #         Ps = 8    -> Auto-repeat Keys (DECARM).
  #         Ps = 9    -> Send Mouse X & Y on button press.    See the sec-
  #         tion Mouse Tracking.
  #         Ps = 1 0    -> Show toolbar (rxvt).
  #         Ps = 1 2    -> Start Blinking Cursor (att610).
  #         Ps = 1 8    -> Print form feed (DECPFF).
  #         Ps = 1 9    -> Set print extent to full screen (DECPEX).
  #         Ps = 2 5    -> Show Cursor (DECTCEM).
  #         Ps = 3 0    -> Show scrollbar (rxvt).
  #         Ps = 3 5    -> Enable font-shifting functions (rxvt).
  #         Ps = 3 8    -> Enter Tektronix Mode (DECTEK).
  #         Ps = 4 0    -> Allow 80 -> 132 Mode.
  #         Ps = 4 1    -> more(1) fix (see curses resource).
  #         Ps = 4 2    -> Enable Nation Replacement Character sets (DECN-
  #         RCM).
  #         Ps = 4 4    -> Turn On Margin Bell.
  #         Ps = 4 5    -> Reverse-wraparound Mode.
  #         Ps = 4 6    -> Start Logging.    This is normally disabled by a
  #         compile-time option.
  #         Ps = 4 7    -> Use Alternate Screen Buffer.    (This may be dis-
  #         abled by the titeInhibit resource).
  #         Ps = 6 6    -> Application keypad (DECNKM).
  #         Ps = 6 7    -> Backarrow key sends backspace (DECBKM).
  #         Ps = 1 0 0 0    -> Send Mouse X & Y on button press and
  #         release.    See the section Mouse Tracking.
  #         Ps = 1 0 0 1    -> Use Hilite Mouse Tracking.
  #         Ps = 1 0 0 2    -> Use Cell Motion Mouse Tracking.
  #         Ps = 1 0 0 3    -> Use All Motion Mouse Tracking.
  #         Ps = 1 0 0 4    -> Send FocusIn/FocusOut events.
  #         Ps = 1 0 0 5    -> Enable Extended Mouse Mode.
  #         Ps = 1 0 1 0    -> Scroll to bottom on tty output (rxvt).
  #         Ps = 1 0 1 1    -> Scroll to bottom on key press (rxvt).
  #         Ps = 1 0 3 4    -> Interpret "meta" key, sets eighth bit.
  #         (enables the eightBitInput resource).
  #         Ps = 1 0 3 5    -> Enable special modifiers for Alt and Num-
  #         Lock keys.    (This enables the numLock resource).
  #         Ps = 1 0 3 6    -> Send ESC     when Meta modifies a key.    (This
  #         enables the metaSendsEscape resource).
  #         Ps = 1 0 3 7    -> Send DEL from the editing-keypad Delete
  #         key.
  #         Ps = 1 0 3 9    -> Send ESC    when Alt modifies a key.    (This
  #         enables the altSendsEscape resource).
  #         Ps = 1 0 4 0    -> Keep selection even if not highlighted.
  #         (This enables the keepSelection resource).
  #         Ps = 1 0 4 1    -> Use the CLIPBOARD selection.    (This enables
  #         the selectToClipboard resource).
  #         Ps = 1 0 4 2    -> Enable Urgency window manager hint when
  #         Control-G is received.    (This enables the bellIsUrgent
  #         resource).
  #         Ps = 1 0 4 3    -> Enable raising of the window when Control-G
  #         is received.    (enables the popOnBell resource).
  #         Ps = 1 0 4 7    -> Use Alternate Screen Buffer.    (This may be
  #         disabled by the titeInhibit resource).
  #         Ps = 1 0 4 8    -> Save cursor as in DECSC.    (This may be dis-
  #         abled by the titeInhibit resource).
  #         Ps = 1 0 4 9    -> Save cursor as in DECSC and use Alternate
  #         Screen Buffer, clearing it first.    (This may be disabled by
  #         the titeInhibit resource).    This combines the effects of the 1
  #         0 4 7    and 1 0 4 8    modes.    Use this with terminfo-based
  #         applications rather than the 4 7    mode.
  #         Ps = 1 0 5 0    -> Set terminfo/termcap function-key mode.
  #         Ps = 1 0 5 1    -> Set Sun function-key mode.
  #         Ps = 1 0 5 2    -> Set HP function-key mode.
  #         Ps = 1 0 5 3    -> Set SCO function-key mode.
  #         Ps = 1 0 6 0    -> Set legacy keyboard emulation (X11R6).
  #         Ps = 1 0 6 1    -> Set VT220 keyboard emulation.
  #         Ps = 2 0 0 4    -> Set bracketed paste mode.
  # Modes:
  #     http://vt100.net/docs/vt220-rm/chapter4.html
  setMode: (params) ->
    if typeof params is "object"
      l = params.length
      i = 0
      while i < l
        @setMode params[i]
        i++
      return
    if not @prefix
      switch params
        when 4
          @insertMode = true
        when 20
          @convertEol = true
      return
    if @prefix is "?"
      switch params
        when 1
          @applicationCursor = true
        when 2
          @setgCharset 0, Terminal::charsets.US
          @setgCharset 1, Terminal::charsets.US
          @setgCharset 2, Terminal::charsets.US
          @setgCharset 3, Terminal::charsets.US
        # set VT100 mode here
        when 3 # 132 col mode
          @savedCols = @cols
          @resize 132, @rows
          @resizeWindowPlease 132
          @reset()
          # For app mode
        when 6
          @originMode = true
        when 7
          @autowrap = true
        when 66
          @applicationKeypad = true
        when 77
          @horizontalWrap = true
        # X10 Mouse
        # no release, no motion, no wheel, no modifiers.
        when 9, 1000, 1002, 1003 # any event mouse
          # any event - sends motion events,
          # even if there is no button held down.
          @x10Mouse = params is 9
          @vt200Mouse = params is 1000
          @normalMouse = params > 1000
          @mouseEvents = true
          @body.style.cursor = 'pointer'
        when 1004 # send focusin/focusout events
          # focusin: ^[[I
          # focusout: ^[[O
          @sendFocus = true
        when 1005 # utf8 ext mode mouse
          @utfMouse = true
        # for wide terminals
        # simply encodes large values as utf8 characters
        when 1006 # sgr ext mode mouse
          @sgrMouse = true
        # for wide terminals
        # does not add 32 to fields
        # press: ^[[<b;x;yM
        # release: ^[[<b;x;ym
        when 1015 # urxvt ext mode mouse
          @urxvtMouse = true
        # for wide terminals
        # numbers for fields
        # press: ^[[b;x;yM
        # motion: ^[[b;x;yT
        when 25 # show cursor
          @cursorHidden = false

        when 1049, 47, 1047 # alt screen buffer
          unless @normal
            normal =
              screen: @screen
              x: @x
              y: @y
              shift: @shift
              scrollTop: @scrollTop
              scrollBottom: @scrollBottom
              tabs: @tabs
              curAttr: @curAttr
            @reset()
            @normal = normal
            @showCursor()


  # CSI Pm l    Reset Mode (RM).
  #         Ps = 2    -> Keyboard Action Mode (AM).
  #         Ps = 4    -> Replace Mode (IRM).
  #         Ps = 1 2    -> Send/receive (SRM).
  #         Ps = 2 0    -> Normal Linefeed (LNM).
  # CSI ? Pm l
  #     DEC Private Mode Reset (DECRST).
  #         Ps = 1    -> Normal Cursor Keys (DECCKM).
  #         Ps = 2    -> Designate VT52 mode (DECANM).
  #         Ps = 3    -> 80 Column Mode (DECCOLM).
  #         Ps = 4    -> Jump (Fast) Scroll (DECSCLM).
  #         Ps = 5    -> Normal Video (DECSCNM).
  #         Ps = 6    -> Normal Cursor Mode (DECOM).
  #         Ps = 7    -> No Wraparound Mode (DECAWM).
  #         Ps = 8    -> No Auto-repeat Keys (DECARM).
  #         Ps = 9    -> Don't send Mouse X & Y on button press.
  #         Ps = 1 0    -> Hide toolbar (rxvt).
  #         Ps = 1 2    -> Stop Blinking Cursor (att610).
  #         Ps = 1 8    -> Don't print form feed (DECPFF).
  #         Ps = 1 9    -> Limit print to scrolling region (DECPEX).
  #         Ps = 2 5    -> Hide Cursor (DECTCEM).
  #         Ps = 3 0    -> Don't show scrollbar (rxvt).
  #         Ps = 3 5    -> Disable font-shifting functions (rxvt).
  #         Ps = 4 0    -> Disallow 80 -> 132 Mode.
  #         Ps = 4 1    -> No more(1) fix (see curses resource).
  #         Ps = 4 2    -> Disable Nation Replacement Character sets (DEC-
  #         NRCM).
  #         Ps = 4 4    -> Turn Off Margin Bell.
  #         Ps = 4 5    -> No Reverse-wraparound Mode.
  #         Ps = 4 6    -> Stop Logging.    (This is normally disabled by a
  #         compile-time option).
  #         Ps = 4 7    -> Use Normal Screen Buffer.
  #         Ps = 6 6    -> Numeric keypad (DECNKM).
  #         Ps = 6 7    -> Backarrow key sends delete (DECBKM).
  #         Ps = 1 0 0 0    -> Don't send Mouse X & Y on button press and
  #         release.    See the section Mouse Tracking.
  #         Ps = 1 0 0 1    -> Don't use Hilite Mouse Tracking.
  #         Ps = 1 0 0 2    -> Don't use Cell Motion Mouse Tracking.
  #         Ps = 1 0 0 3    -> Don't use All Motion Mouse Tracking.
  #         Ps = 1 0 0 4    -> Don't send FocusIn/FocusOut events.
  #         Ps = 1 0 0 5    -> Disable Extended Mouse Mode.
  #         Ps = 1 0 1 0    -> Don't scroll to bottom on tty output
  #         (rxvt).
  #         Ps = 1 0 1 1    -> Don't scroll to bottom on key press (rxvt).
  #         Ps = 1 0 3 4    -> Don't interpret "meta" key.    (This disables
  #         the eightBitInput resource).
  #         Ps = 1 0 3 5    -> Disable special modifiers for Alt and Num-
  #         Lock keys.    (This disables the numLock resource).
  #         Ps = 1 0 3 6    -> Don't send ESC    when Meta modifies a key.
  #         (This disables the metaSendsEscape resource).
  #         Ps = 1 0 3 7    -> Send VT220 Remove from the editing-keypad
  #         Delete key.
  #         Ps = 1 0 3 9    -> Don't send ESC    when Alt modifies a key.
  #         (This disables the altSendsEscape resource).
  #         Ps = 1 0 4 0    -> Do not keep selection when not highlighted.
  #         (This disables the keepSelection resource).
  #         Ps = 1 0 4 1    -> Use the PRIMARY selection.    (This disables
  #         the selectToClipboard resource).
  #         Ps = 1 0 4 2    -> Disable Urgency window manager hint when
  #         Control-G is received.    (This disables the bellIsUrgent
  #         resource).
  #         Ps = 1 0 4 3    -> Disable raising of the window when Control-
  #         G is received.    (This disables the popOnBell resource).
  #         Ps = 1 0 4 7    -> Use Normal Screen Buffer, clearing screen
  #         first if in the Alternate Screen.    (This may be disabled by
  #         the titeInhibit resource).
  #         Ps = 1 0 4 8    -> Restore cursor as in DECRC.    (This may be
  #         disabled by the titeInhibit resource).
  #         Ps = 1 0 4 9    -> Use Normal Screen Buffer and restore cursor
  #         as in DECRC.    (This may be disabled by the titeInhibit
  #         resource).    This combines the effects of the 1 0 4 7    and 1 0
  #         4 8    modes.    Use this with terminfo-based applications rather
  #         than the 4 7    mode.
  #         Ps = 1 0 5 0    -> Reset terminfo/termcap function-key mode.
  #         Ps = 1 0 5 1    -> Reset Sun function-key mode.
  #         Ps = 1 0 5 2    -> Reset HP function-key mode.
  #         Ps = 1 0 5 3    -> Reset SCO function-key mode.
  #         Ps = 1 0 6 0    -> Reset legacy keyboard emulation (X11R6).
  #         Ps = 1 0 6 1    -> Reset keyboard emulation to Sun/PC style.
  #         Ps = 2 0 0 4    -> Reset bracketed paste mode.
  resetMode: (params) ->
    if typeof params is "object"
      l = params.length
      i = 0
      while i < l
        @resetMode params[i]
        i++
      return
    if not @prefix
      switch params
        when 4
          @insertMode = false
        when 20
          @convertEol = false
      return

    if @prefix is "?"
      switch params
        when 1
          @applicationCursor = false
        when 3
          @resize @savedCols, @rows if @cols is 132 and @savedCols
          @resizeWindowPlease 80
          @reset()
          # App mode
          delete @savedCols
        when 6
          @originMode = false
        when 7
          @autowrap = false
        when 66
          @applicationKeypad = false
        when 77
          @horizontalWrap = false
        when 9, 1000, 1002 , 1003 # any event mouse
          @x10Mouse = false
          @vt200Mouse = false
          @normalMouse = false
          @mouseEvents = false
          @body.style.cursor = ""
        when 1004 # send focusin/focusout events
          @sendFocus = false
        when 1005 # utf8 ext mode mouse
          @utfMouse = false
        when 1006 # sgr ext mode mouse
          @sgrMouse = false
        when 1015 # urxvt ext mode mouse
          @urxvtMouse = false
        when 25 # hide cursor
          @cursorHidden = true
        when 1049, 47, 1047 # normal screen buffer - clearing it first
          if @normal
            @screen = @normal.screen
            @x = @normal.x
            @y = @normal.y
            @shift = @normal.shift
            @scrollTop = @normal.scrollTop
            @scrollBottom = @normal.scrollBottom
            @tabs = @normal.tabs
            @curAttr = @normal.curAttr
            @normal = null
            @refresh(true)
            @showCursor()

  # CSI Ps ; Ps r
  #     Set Scrolling Region [top;bottom] (default = full size of win-
  #     dow) (DECSTBM).
  # CSI ? Pm r
  setScrollRegion: (params) ->
    return if @prefix
    @scrollTop = (params[0] or 1) - 1
    @scrollBottom = (params[1] or @rows) - 1
    @x = 0
    @y = 0


  # CSI s
  #     Save cursor (ANSI.SYS).
  saveCursor: (params) ->
    @savedX = @x
    @savedY = @y


  # CSI u
  #     Restore cursor (ANSI.SYS).
  restoreCursor: (params) ->
    @x = @savedX or 0
    @y = @savedY or 0

  ## Lesser Used ##

  # CSI Ps I
  #     Cursor Forward Tabulation Ps tab stops (default = 1) (CHT).
  cursorForwardTab: (params) ->
    param = params[0] or 1
    @x = @nextStop() while param--


  # CSI Ps S    Scroll up Ps lines (default = 1) (SU).
  scrollUp: (params) ->
    param = params[0] or 1
    while param--
      @screen.splice @scrollTop, 1
      @screen.splice @scrollBottom, 0, @blankLine()

    for i in [@scrollTop..@scrollBottom]
      @screen[i + @shift].dirty = true


  # CSI Ps T    Scroll down Ps lines (default = 1) (SD).
  scrollDown: (params) ->
    param = params[0] or 1
    while param--
      @screen.splice @scrollBottom, 1
      @screen.splice @scrollTop, 0, @blankLine()

    for i in [@scrollTop..@scrollBottom]
      @screen[i + @shift].dirty = true


  # CSI Ps ; Ps ; Ps ; Ps ; Ps T
  #     Initiate highlight mouse tracking.    Parameters are
  #     [func;startx;starty;firstrow;lastrow].    See the section Mouse
  #     Tracking.
  initMouseTracking: (params) ->

  # Relevant: DECSET 1001

  # CSI > Ps; Ps T
  #     Reset one or more features of the title modes to the default
  #     value.    Normally, "reset" disables the feature.    It is possi-
  #     ble to disable the ability to reset features by compiling a
  #     different default for the title modes into xterm.
  #         Ps = 0    -> Do not set window/icon labels using hexadecimal.
  #         Ps = 1    -> Do not query window/icon labels using hexadeci-
  #         mal.
  #         Ps = 2    -> Do not set window/icon labels using UTF-8.
  #         Ps = 3    -> Do not query window/icon labels using UTF-8.
  #     (See discussion of "Title Modes").
  resetTitleModes: (params) ->


  # CSI Ps Z    Cursor Backward Tabulation Ps tab stops (default = 1) (CBT).
  cursorBackwardTab: (params) ->
    param = params[0] or 1
    @x = @prevStop() while param--


  # CSI Ps b    Repeat the preceding graphic character Ps times (REP).
  repeatPrecedingCharacter: (params) ->
    param = params[0] or 1
    line = @screen[@y + @shift].chars
    ch = line[@x - 1] or @defAttr
    line[@x++] = ch while param--
    @screen[@y + @shift].dirty = true

  # CSI Ps g    Tab Clear (TBC).
  #         Ps = 0    -> Clear Current Column (default).
  #         Ps = 3    -> Clear All.
  # Potentially:
  #     Ps = 2    -> Clear Stops on Line.
  #     http://vt100.net/annarbor/aaa-ug/section6.html
  tabClear: (params) ->
    param = params[0]
    if param <= 0
      delete @tabs[@x]
    else
      @tabs = {} if param is 3

  # CSI Pm i    Media Copy (MC).
  #         Ps = 0    -> Print screen (default).
  #         Ps = 4    -> Turn off printer controller mode.
  #         Ps = 5    -> Turn on printer controller mode.
  # CSI ? Pm i
  #     Media Copy (MC, DEC-specific).
  #         Ps = 1    -> Print line containing cursor.
  #         Ps = 4    -> Turn off autoprint mode.
  #         Ps = 5    -> Turn on autoprint mode.
  #         Ps = 1    0    -> Print composed display, ignores DECPEX.
  #         Ps = 1    1    -> Print all pages.
  mediaCopy: (params) ->


  # CSI > Ps; Ps m
  #     Set or reset resource-values used by xterm to decide whether
  #     to construct escape sequences holding information about the
  #     modifiers pressed with a given key.    The first parameter iden-
  #     tifies the resource to set/reset.    The second parameter is the
  #     value to assign to the resource.    If the second parameter is
  #     omitted, the resource is reset to its initial value.
  #         Ps = 1    -> modifyCursorKeys.
  #         Ps = 2    -> modifyFunctionKeys.
  #         Ps = 4    -> modifyOtherKeys.
  #     If no parameters are given, all resources are reset to their
  #     initial values.
  setResources: (params) ->


  # CSI > Ps n
  #     Disable modifiers which may be enabled via the CSI > Ps; Ps m
  #     sequence.    This corresponds to a resource value of "-1", which
  #     cannot be set with the other sequence.    The parameter identi-
  #     fies the resource to be disabled:
  #         Ps = 1    -> modifyCursorKeys.
  #         Ps = 2    -> modifyFunctionKeys.
  #         Ps = 4    -> modifyOtherKeys.
  #     If the parameter is omitted, modifyFunctionKeys is disabled.
  #     When modifyFunctionKeys is disabled, xterm uses the modifier
  #     keys to make an extended sequence of functions rather than
  #     adding a parameter to each function key to denote the modi-
  #     fiers.
  disableModifiers: (params) ->


  # CSI > Ps p
  #     Set resource value pointerMode.    This is used by xterm to
  #     decide whether to hide the pointer cursor as the user types.
  #     Valid values for the parameter:
  #         Ps = 0    -> never hide the pointer.
  #         Ps = 1    -> hide if the mouse tracking mode is not enabled.
  #         Ps = 2    -> always hide the pointer.    If no parameter is
  #         given, xterm uses the default, which is 1 .
  setPointerMode: (params) ->


  # CSI ! p     Soft terminal reset (DECSTR).
  # http://vt100.net/docs/vt220-rm/table4-10.html
  softReset: (params) ->
    @cursorHidden = false
    @insertMode = false
    @originMode = false
    @autowrap = true
    @applicationKeypad = false # ?
    @applicationCursor = false
    @scrollTop = 0
    @scrollBottom = @rows - 1
    @curAttr = @defAttr
    @x = @y = 0 # ?
    @charset = null
    @glevel = 0 # ??
    @charsets = [null] # ??


  # CSI Ps$ p
  #     Request ANSI mode (DECRQM).    For VT300 and up, reply is
  #         CSI Ps; Pm$ y
  #     where Ps is the mode number as in RM, and Pm is the mode
  #     value:
  #         0 - not recognized
  #         1 - set
  #         2 - reset
  #         3 - permanently set
  #         4 - permanently reset
  requestAnsiMode: (params) ->


  # CSI ? Ps$ p
  #     Request DEC private mode (DECRQM).    For VT300 and up, reply is
  #         CSI ? Ps; Pm$ p
  #     where Ps is the mode number as in DECSET, Pm is the mode value
  #     as in the ANSI DECRQM.
  requestPrivateMode: (params) ->


  # CSI Ps ; Ps " p
  #     Set conformance level (DECSCL).    Valid values for the first
  #     parameter:
  #         Ps = 6 1    -> VT100.
  #         Ps = 6 2    -> VT200.
  #         Ps = 6 3    -> VT300.
  #     Valid values for the second parameter:
  #         Ps = 0    -> 8-bit controls.
  #         Ps = 1    -> 7-bit controls (always set for VT100).
  #         Ps = 2    -> 8-bit controls.
  setConformanceLevel: (params) ->


  # CSI Ps q    Load LEDs (DECLL).
  #         Ps = 0    -> Clear all LEDS (default).
  #         Ps = 1    -> Light Num Lock.
  #         Ps = 2    -> Light Caps Lock.
  #         Ps = 3    -> Light Scroll Lock.
  #         Ps = 2    1    -> Extinguish Num Lock.
  #         Ps = 2    2    -> Extinguish Caps Lock.
  #         Ps = 2    3    -> Extinguish Scroll Lock.
  loadLEDs: (params) ->


  # CSI Ps SP q
  #     Set cursor style (DECSCUSR, VT520).
  #         Ps = 0    -> blinking block.
  #         Ps = 1    -> blinking block (default).
  #         Ps = 2    -> steady block.
  #         Ps = 3    -> blinking underline.
  #         Ps = 4    -> steady underline.
  setCursorStyle: (params) ->


  # CSI Ps " q
  #     Select character protection attribute (DECSCA).    Valid values
  #     for the parameter:
  #         Ps = 0    -> DECSED and DECSEL can erase (default).
  #         Ps = 1    -> DECSED and DECSEL cannot erase.
  #         Ps = 2    -> DECSED and DECSEL can erase.
  setCharProtectionAttr: (params) ->


  # CSI ? Pm r
  #     Restore DEC Private Mode Values.    The value of Ps previously
  #     saved is restored.    Ps values are the same as for DECSET.
  restorePrivateValues: (params) ->


  # CSI Pt; Pl; Pb; Pr; Ps$ r
  #     Change Attributes in Rectangular Area (DECCARA), VT400 and up.
  #         Pt; Pl; Pb; Pr denotes the rectangle.
  #         Ps denotes the SGR attributes to change: 0, 1, 4, 5, 7.
  # NOTE: xterm doesn't enable this code by default.
  setAttrInRectangle: (params) ->
    t = params[0]
    l = params[1]
    b = params[2]
    r = params[3]
    attr = params[4]
    while t < b + 1
      line = @screen[t + @shift].chars
      @screen[t + @shift].dirty = true
      i = l
      while i < r
        line[i] = @cloneAttr attr, line[i].ch
        i++
      t++


  # CSI ? Pm s
  #     Save DEC Private Mode Values.    Ps values are the same as for
  #     DECSET.
  savePrivateValues: (params) ->


  # CSI Ps ; Ps ; Ps t
  #     Window manipulation (from dtterm, as well as extensions).
  #     These controls may be disabled using the allowWindowOps
  #     resource.    Valid values for the first (and any additional
  #     parameters) are:
  #         Ps = 1    -> De-iconify window.
  #         Ps = 2    -> Iconify window.
  #         Ps = 3    ;    x ;    y -> Move window to [x, y].
  #         Ps = 4    ;    height ;    width -> Resize the xterm window to
  #         height and width in pixels.
  #         Ps = 5    -> Raise the xterm window to the front of the stack-
  #         ing order.
  #         Ps = 6    -> Lower the xterm window to the bottom of the
  #         stacking order.
  #         Ps = 7    -> Refresh the xterm window.
  #         Ps = 8    ;    height ;    width -> Resize the text area to
  #         [height;width] in characters.
  #         Ps = 9    ;    0    -> Restore maximized window.
  #         Ps = 9    ;    1    -> Maximize window (i.e., resize to screen
  #         size).
  #         Ps = 1 0    ;    0    -> Undo full-screen mode.
  #         Ps = 1 0    ;    1    -> Change to full-screen.
  #         Ps = 1 1    -> Report xterm window state.    If the xterm window
  #         is open (non-iconified), it returns CSI 1 t .    If the xterm
  #         window is iconified, it returns CSI 2 t .
  #         Ps = 1 3    -> Report xterm window position.    Result is CSI 3
  #         ; x ; y t
  #         Ps = 1 4    -> Report xterm window in pixels.    Result is CSI
  #         4    ;    height ;    width t
  #         Ps = 1 8    -> Report the size of the text area in characters.
  #         Result is CSI    8    ;    height ;    width t
  #         Ps = 1 9    -> Report the size of the screen in characters.
  #         Result is CSI    9    ;    height ;    width t
  #         Ps = 2 0    -> Report xterm window's icon label.    Result is
  #         OSC    L    label ST
  #         Ps = 2 1    -> Report xterm window's title.    Result is OSC    l
  #         label ST
  #         Ps = 2 2    ;    0    -> Save xterm icon and window title on
  #         stack.
  #         Ps = 2 2    ;    1    -> Save xterm icon title on stack.
  #         Ps = 2 2    ;    2    -> Save xterm window title on stack.
  #         Ps = 2 3    ;    0    -> Restore xterm icon and window title from
  #         stack.
  #         Ps = 2 3    ;    1    -> Restore xterm icon title from stack.
  #         Ps = 2 3    ;    2    -> Restore xterm window title from stack.
  #         Ps >= 2 4    -> Resize to Ps lines (DECSLPP).
  manipulateWindow: (params) ->


  # CSI Pt; Pl; Pb; Pr; Ps$ t
  #     Reverse Attributes in Rectangular Area (DECRARA), VT400 and
  #     up.
  #         Pt; Pl; Pb; Pr denotes the rectangle.
  #         Ps denotes the attributes to reverse, i.e.,    1, 4, 5, 7.
  # NOTE: xterm doesn't enable this code by default.
  reverseAttrInRectangle: (params) ->


  # CSI > Ps; Ps t
  #     Set one or more features of the title modes.    Each parameter
  #     enables a single feature.
  #         Ps = 0    -> Set window/icon labels using hexadecimal.
  #         Ps = 1    -> Query window/icon labels using hexadecimal.
  #         Ps = 2    -> Set window/icon labels using UTF-8.
  #         Ps = 3    -> Query window/icon labels using UTF-8.    (See dis-
  #         cussion of "Title Modes")
  setTitleModeFeature: (params) ->


  # CSI Ps SP t
  #     Set warning-bell volume (DECSWBV, VT520).
  #         Ps = 0    or 1    -> off.
  #         Ps = 2 , 3    or 4    -> low.
  #         Ps = 5 , 6 , 7 , or 8    -> high.
  setWarningBellVolume: (params) ->


  # CSI Ps SP u
  #     Set margin-bell volume (DECSMBV, VT520).
  #         Ps = 1    -> off.
  #         Ps = 2 , 3    or 4    -> low.
  #         Ps = 0 , 5 , 6 , 7 , or 8    -> high.
  setMarginBellVolume: (params) ->


  # CSI Pt; Pl; Pb; Pr; Pp; Pt; Pl; Pp$ v
  #     Copy Rectangular Area (DECCRA, VT400 and up).
  #         Pt; Pl; Pb; Pr denotes the rectangle.
  #         Pp denotes the source page.
  #         Pt; Pl denotes the target location.
  #         Pp denotes the target page.
  # NOTE: xterm doesn't enable this code by default.
  copyRectangle: (params) ->


  # CSI Pt ; Pl ; Pb ; Pr ' w
  #     Enable Filter Rectangle (DECEFR), VT420 and up.
  #     Parameters are [top;left;bottom;right].
  #     Defines the coordinates of a filter rectangle and activates
  #     it.    Anytime the locator is detected outside of the filter
  #     rectangle, an outside rectangle event is generated and the
  #     rectangle is disabled.    Filter rectangles are always treated
  #     as "one-shot" events.    Any parameters that are omitted default
  #     to the current locator position.    If all parameters are omit-
  #     ted, any locator motion will be reported.    DECELR always can-
  #     cels any prevous rectangle definition.
  enableFilterRectangle: (params) ->


  # CSI Ps x    Request Terminal Parameters (DECREQTPARM).
  #     if Ps is a "0" (default) or "1", and xterm is emulating VT100,
  #     the control sequence elicits a response of the same form whose
  #     parameters describe the terminal:
  #         Ps -> the given Ps incremented by 2.
  #         Pn = 1    <- no parity.
  #         Pn = 1    <- eight bits.
  #         Pn = 1    <- 2    8    transmit 38.4k baud.
  #         Pn = 1    <- 2    8    receive 38.4k baud.
  #         Pn = 1    <- clock multiplier.
  #         Pn = 0    <- STP flags.
  requestParameters: (params) ->


  # CSI Ps x    Select Attribute Change Extent (DECSACE).
  #         Ps = 0    -> from start to end position, wrapped.
  #         Ps = 1    -> from start to end position, wrapped.
  #         Ps = 2    -> rectangle (exact).
  selectChangeExtent: (params) ->


  # CSI Pc; Pt; Pl; Pb; Pr$ x
  #     Fill Rectangular Area (DECFRA), VT420 and up.
  #         Pc is the character to use.
  #         Pt; Pl; Pb; Pr denotes the rectangle.
  # NOTE: xterm doesn't enable this code by default.
  fillRectangle: (params) ->
    ch = params[0]
    t = params[1]
    l = params[2]
    b = params[3]
    r = params[4]
    while t < b + 1
      line = @screen[t + @shift].chars
      @screen[t + @shift].dirty = true
      i = l
      while i < r
        line[i] = @cloneAttr line[i][0], String.fromCharCode(ch)
        i++
      t++


  # CSI Ps ; Pu ' z
  #     Enable Locator Reporting (DECELR).
  #     Valid values for the first parameter:
  #         Ps = 0    -> Locator disabled (default).
  #         Ps = 1    -> Locator enabled.
  #         Ps = 2    -> Locator enabled for one report, then disabled.
  #     The second parameter specifies the coordinate unit for locator
  #     reports.
  #     Valid values for the second parameter:
  #         Pu = 0    <- or omitted -> default to character cells.
  #         Pu = 1    <- device physical pixels.
  #         Pu = 2    <- character cells.
  enableLocatorReporting: (params) ->
    val = params[0] > 0


  # CSI Pt; Pl; Pb; Pr$ z
  #     Erase Rectangular Area (DECERA), VT400 and up.
  #         Pt; Pl; Pb; Pr denotes the rectangle.
  # NOTE: xterm doesn't enable this code by default.
  eraseRectangle: (params) ->
    t = params[0]
    l = params[1]
    b = params[2]
    r = params[3]
    while t < b + 1
      line = @screen[t + @shift].chars
      @screen[t + @shift].dirty = true
      i = l
      while i < r
        line[i] = @eraseAttr()
        i++
      t++

  # CSI Pm ' {
  #     Select Locator Events (DECSLE).
  #     Valid values for the first (and any additional parameters)
  #     are:
  #         Ps = 0    -> only respond to explicit host requests (DECRQLP).
  #                        (This is default).    It also cancels any filter
  #     rectangle.
  #         Ps = 1    -> report button down transitions.
  #         Ps = 2    -> do not report button down transitions.
  #         Ps = 3    -> report button up transitions.
  #         Ps = 4    -> do not report button up transitions.
  setLocatorEvents: (params) ->


  # CSI Pt; Pl; Pb; Pr$ {
  #     Selective Erase Rectangular Area (DECSERA), VT400 and up.
  #         Pt; Pl; Pb; Pr denotes the rectangle.
  selectiveEraseRectangle: (params) ->


  # CSI Ps ' |
  #     Request Locator Position (DECRQLP).
  #     Valid values for the parameter are:
  #         Ps = 0 , 1 or omitted -> transmit a single DECLRP locator
  #         report.

  #     If Locator Reporting has been enabled by a DECELR, xterm will
  #     respond with a DECLRP Locator Report.    This report is also
  #     generated on button up and down events if they have been
  #     enabled with a DECSLE, or when the locator is detected outside
  #     of a filter rectangle, if filter rectangles have been enabled
  #     with a DECEFR.

  #         -> CSI Pe ; Pb ; Pr ; Pc ; Pp &    w

  #     Parameters are [event;button;row;column;page].
  #     Valid values for the event:
  #         Pe = 0    -> locator unavailable - no other parameters sent.
  #         Pe = 1    -> request - xterm received a DECRQLP.
  #         Pe = 2    -> left button down.
  #         Pe = 3    -> left button up.
  #         Pe = 4    -> middle button down.
  #         Pe = 5    -> middle button up.
  #         Pe = 6    -> right button down.
  #         Pe = 7    -> right button up.
  #         Pe = 8    -> M4 button down.
  #         Pe = 9    -> M4 button up.
  #         Pe = 1 0    -> locator outside filter rectangle.
  #     ``button'' parameter is a bitmask indicating which buttons are
  #         pressed:
  #         Pb = 0    <- no buttons down.
  #         Pb & 1    <- right button down.
  #         Pb & 2    <- middle button down.
  #         Pb & 4    <- left button down.
  #         Pb & 8    <- M4 button down.
  #     ``row'' and ``column'' parameters are the coordinates of the
  #         locator position in the xterm window, encoded as ASCII deci-
  #         mal.
  #     The ``page'' parameter is not used by xterm, and will be omit-
  #     ted.
  requestLocatorPosition: (params) ->


  # CSI P m SP }
  # Insert P s Column(s) (default = 1) (DECIC), VT420 and up.
  # NOTE: xterm doesn't enable this code by default.
  insertColumns: ->
    param = params[0]
    l = @rows + @shift
    while param--
      i = @shift
      while i < l
        @screen[i].chars.splice @x + 1, 0, @eraseAttr()
        @screen[i].chars.pop()
        @screen[i].dirty = true
        i++


  # CSI P m SP ~
  # Delete P s Column(s) (default = 1) (DECDC), VT420 and up
  # NOTE: xterm doesn't enable this code by default.
  deleteColumns: ->
    param = params[0]
    l = @rows + @shift
    while param--
      i = @shift
      while i < l
        @screen[i].chars.splice @x, 1
        @screen[i].chars.push @eraseAttr()
        @resetLine @screen[i].dirty
        i++

  # DEC Special Character and Line Drawing Set.
  # http://vt100.net/docs/vt102-ug/table5-13.html
  # A lot of curses apps use this if they see TERM=xterm.
  # testing: echo -e '\e(0a\e(B'
  # The xterm output sometimes seems to conflict with the
  # reference above. xterm seems in line with the reference
  # when running vttest however.
  # The table below now uses xterm's output from vttest.
  charsets:
    SCLD:# (0
      "`": "◆" # '◆'
      a: "▒" # '▒'
      b: "\t" # '\t'
      c: "\f" # '\f'
      d: "\r" # '\r'
      e: "\n" # '\n'
      f: "°" # '°'
      g: "±" # '±'
      h: "␤" # '\u2424' (NL)
      i: "\x0b" # '\v'
      j: "┘" # '┘'
      k: "┐" # '┐'
      l: "┌" # '┌'
      m: "└" # '└'
      n: "┼" # '┼'
      o: "⎺" # '⎺'
      p: "⎻" # '⎻'
      q: "─" # '─'
      r: "⎼" # '⎼'
      s: "⎽" # '⎽'
      t: "├" # '├'
      u: "┤" # '┤'
      v: "┴" # '┴'
      w: "┬" # '┬'
      x: "│" # '│'
      y: "≤" # '≤'
      z: "≥" # '≥'
      "{": "π" # 'π'
      "|": "≠" # '≠'
      "}": "£" # '£'
      "~": "·" # '·'
    UK: null # (A
    US: null # (B (USASCII)
    Dutch: null # (4
    Finnish: null # (C or (5
    French: null # (R
    FrenchCanadian: null # (Q
    German: null # (K
    Italian: null # (Y
    NorwegianDanish: null # (E or (6
    Spanish: null # (Z
    Swedish: null # (H or (7
    Swiss: null # (=
    ISOLatin: null # /A

window.Terminal = Terminal
