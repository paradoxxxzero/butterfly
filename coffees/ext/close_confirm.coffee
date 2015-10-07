addEventListener 'beforeunload', (e) ->
  unless (butterfly.body.classList.contains('dead') or
    location.href.indexOf('session') > -1)
      e.returnValue = 'This terminal is active and not in session.
      Are you sure you want to kill it?'
