document.addEventListener 'keydown', (e) ->
  return true unless e.altKey and e.keyCode is 79
  open(location.href)
  cancel e
