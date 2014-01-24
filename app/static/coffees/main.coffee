term = ws = null
cols = rows = null

$ ->
    ws_url = 'ws://' + document.location.host + '/ws'
    if location.pathname.indexOf('/wd') == 0
        ws_url += location.pathname.slice 3
    ws = new WebSocket ws_url
    ws.onopen = ->
        console.log "WebSocket open", arguments
        term = new Terminal(
            visualBell: true
            screenKeys: true
            scrollback: -1
        )
        term.on "data", (data) ->
            ws.send 'SH|' + data

        term.on "title", (title) ->
          document.title = title

        term.open $('main').get(0)
        $('.terminal').attr('style', '')
        $(window).trigger 'resize'


    ws.onclose = ->
        if term
            term.destroy()
        console.log "WebSocket closed", arguments
        open('','_self').close()

    ws.onerror = -> console.log "WebSocket error", arguments
    ws.onmessage = (event) ->
        # setTimeout (term.write event.data), 1
        term.write event.data

    $(window).resize ->
        $main = $('main')
        $termtest = $('<div>').addClass('terminal')
        $test = $('<div>').text('0123456789')
        $termtest.append($test)

        $main.append($termtest)
        eh = $test.outerHeight()
        $test.css(display: 'inline-block')
        ew = $test.outerWidth() / 10
        $termtest.remove()
        w = $main.outerWidth()
        h = $main.outerHeight()
        cols = Math.floor(w / ew) - 1
        rows = Math.floor(h / eh)
        console.log "Computed #{cols} cols and #{rows} rows from main size #{w}, #{h} and div #{ew}, #{eh}"
        term.resize cols, rows
        ws.send "RS|#{cols},#{rows}"
