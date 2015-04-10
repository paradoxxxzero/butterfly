
document.addEventListener 'DOMContentLoaded', ->
  return

  req = null

  butterfly.native_scroll_to = (scroll=-1) ->
    e = butterfly.parent
    cancelAnimationFrame req if req
    if scroll is -1 or (
      scroll > e.scrollHeight - e.getBoundingClientRect().height)
      scroll = e.scrollHeight - e.getBoundingClientRect().height

    diff = scroll - e.scrollTop
    return if diff is 0
    step = diff / 25
    scroll_step = ->
      if Math.abs(e.scrollTop - scroll) < Math.abs(step)
        e.scrollTop = scroll
      else
        e.scrollTop += step
        req = requestAnimationFrame scroll_step

    req = requestAnimationFrame scroll_step
