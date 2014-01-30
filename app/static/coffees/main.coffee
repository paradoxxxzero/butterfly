term = ws = null
cols = rows = null
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
    open('','_self').close()

ws.onerror = -> console.log "WebSocket error", arguments
ws.onmessage = (event) ->
    term.write event.data

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
