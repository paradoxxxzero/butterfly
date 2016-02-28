
class Popup
  constructor: ->
    @el = document.getElementById('popup')
    @bound_click_maybe_close = @click_maybe_close.bind(@)
    @bound_key_maybe_close = @key_maybe_close.bind(@)

  open: (html) ->
    @el.innerHTML = html
    @el.classList.remove 'hidden'

    # ff glorious hack
    if typeof InstallTrigger isnt "undefined"
      document.body.contentEditable = 'false'

    addEventListener 'click', @bound_click_maybe_close
    addEventListener 'keydown', @bound_key_maybe_close

  close: ->
    removeEventListener 'click', @bound_click_maybe_close
    removeEventListener 'keydown', @bound_key_maybe_close

    # ff glorious hack
    if typeof InstallTrigger isnt "undefined"
      document.body.contentEditable = 'true'

    @el.classList.add 'hidden'
    @el.innerHTML = ''

  click_maybe_close: (e) ->
    t = e.target
    while t.parentElement
      return true if Array.prototype.slice.call(@el.children).indexOf(t) > -1
      t = t.parentElement
    @close()
    cancel e

  key_maybe_close: (e) ->
    return true unless e.keyCode is 27
    @close()
    cancel e

popup = new Popup()

