state =
    x: null
    y: null

document.addEventListener 'keydown', (e) ->
    if e.shiftKey and (37 <= e.keyCode <= 40)
        if state.y == null
            state.y = term.ybase + term.y
        if e.keyCode == 38
            state.y--
            if state.y < term.ybase
                state.y = term.ybase
        else if e.keyCode == 40
            state.y++
            if state.y > term.ybase + term.y
                state.y = term.ybase + term.y

        term.emit('data', ' \x0b\x15')
        if state.y != term.ybase + term.y
            term.emit('data', term.grabText(0, term.cols - 1, state.y, state.y).replace('\n', ''))
        e.stopPropagation()
        return false
    else
        state.x = state.y = null
