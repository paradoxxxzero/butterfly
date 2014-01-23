term = ws = null
cols = rows = null

$ ->

    ws = new WebSocket 'ws://' + document.location.host + '/ws'
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
        $test = $('<div>').css(display: 'inline').text('0123456789')
        $termtest.append($test)

        $main.append($termtest)
        ew = $test.outerWidth() / 10
        eh = $test.outerHeight()
        $termtest.remove()
        w = $main.outerWidth()
        h = $main.outerHeight()
        cols = Math.floor(w / ew) - 1
        rows = Math.floor(h / eh) - 1
        term.resize cols, rows
        ws.send "RS|#{cols},#{rows}"
