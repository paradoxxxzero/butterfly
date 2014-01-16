ws = null

$ ->
    ws = new WebSocket 'ws://' + document.location.host + '/ws'
    ws.onopen = -> console.log "WebSocket open", arguments
    ws.onclose = -> console.log "WebSocket closed", arguments
    ws.onerror = -> console.log "WebSocket error", arguments
    ws.onmessage = (event) ->
        $('.term code').html($('.term code').html() + event.data)

    $('html,body').on('keypress', (event) ->
        code = event.keyCode
        ws.send(String.fromCharCode(code))
        event.preventDefault()
        event.stopPropagation()
        return false
    ).on('keydown', (event) ->
        code = event.keyCode
        return if code == 17
        if event.ctrlKey
            code -= 64
            ws.send(String.fromCharCode(code))

            event.preventDefault()
            event.stopPropagation()
            return false
    )
