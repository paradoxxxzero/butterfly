try
    document.createEvent("TouchEvent")
    virtual_input = true
catch e
    virtual_input = false

term = ws = null
cols = rows = null
quit = false

if virtual_input
    ctrl = false
    alt = false
    first = true
    virtual_input = document.createElement 'input'
    virtual_input.type = 'password'
    virtual_input.style.position = 'fixed'
    virtual_input.style.top = 0
    virtual_input.style.left = 0
    virtual_input.style.border = 'none'
    virtual_input.style.outline = 'none'
    virtual_input.style.opacity = 0
    virtual_input.value = '0'
    document.body.appendChild virtual_input

    virtual_input.addEventListener 'blur', ->
        setTimeout((=> @focus()), 10)

    addEventListener 'click', ->
        virtual_input.focus()

    addEventListener 'touchstart', (e) ->
        if e.touches.length == 1
            ctrl = true
        else if e.touches.length == 2
            ctrl = false
            alt = true
        else if e.touches.length == 3
            ctrl = true
            alt = true

    virtual_input.addEventListener 'keydown', (e) ->
         term.keyDown(e)
         return true

    virtual_input.addEventListener 'input', (e) ->
        len = @value.length

        if len == 0
            e.keyCode = 8
            term.keyDown e
            @value = '0'
            return true

        e.keyCode = @value.charAt(1).charCodeAt(0)

        if (ctrl or alt) and not first
            e.keyCode = @value.charAt(1).charCodeAt(0)
            e.ctrlKey = ctrl
            e.altKey = alt
            if e.keyCode >= 97 && e.keyCode <= 122
                e.keyCode -= 32
            term.keyDown e
            @value = '0'
            ctrl = alt = false
            return true

        term.keyPress e
        first = false
        @value = '0'
        true

$ = document.querySelectorAll.bind(document)

ws_url = 'ws://' + document.location.host + '/ws' + location.pathname
ws = new WebSocket ws_url
ws.onopen = ->
    console.log "WebSocket open", arguments

    term = new Terminal(
        visualBell: 100
        screenKeys: true
        scrollback: -1
    )
    term.on "data", (data) ->
        ws.send 'SH|' + data

    term.on "title", (title) ->
      document.title = title

    term.open $('main')[0]
    $('.terminal')[0].style = ''
    resize()


ws.onclose = ->
    if term
        term.destroy()
    console.log "WebSocket closed", arguments
    quit = true
    open('','_self').close()

ws.onerror = -> console.log "WebSocket error", arguments
ws.onmessage = (e) ->
    term.write event.data

addEventListener 'beforeunload', ->
    if not quit
        'This will exit the terminal session'

addEventListener 'resize', resize =  ->
    main = $('main')[0]
    fake_term = document.createElement('div')
    fake_term.className = 'terminal test'
    fake_term_div = document.createElement('div')
    fake_term_line = document.createElement('span')
    fake_term_line.textContent = '0123456789'
    fake_term_div.appendChild(fake_term_line)
    fake_term.appendChild(fake_term_div)
    main.appendChild(fake_term)

    ew = fake_term_line.getBoundingClientRect().width
    eh = fake_term_div.getBoundingClientRect().height
    main.removeChild(fake_term)

    main_bb = main.getBoundingClientRect()
    cols = Math.floor(10 * main_bb.width / ew) - 1
    rows = Math.floor(main_bb.height / eh)

    console.log "Computed #{cols} cols and #{rows} rows from ", main_bb, ew, eh
    term.resize cols, rows
    ws.send "RS|#{cols},#{rows}"
