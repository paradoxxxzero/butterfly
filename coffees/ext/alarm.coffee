clean_ansi = (data) ->
  # Fast ansi clean (not complete)

  if data.indexOf('\x1b') < 0
    return data
  i = -1
  out = ''
  state = 'normal'
  while i < data.length - 1
    c = data.charAt ++i
    switch state
      when 'normal'
        if c is '\x1b'
          state = 'escaped'
          break
        out += c

      when 'escaped'
        if c is '['
          state = 'csi'
          break

        if c is ']'
          state = 'osc'
          break

        if '#()%*+-./'.indexOf(c) >= 0
          i++
        state = 'normal'

      when 'csi'
        if "?>!$\" '".indexOf(c) >= 0
          break
        if '0' <= c <= '9'
          break
        break if c is ';'
        state = 'normal'
      when 'osc'
        if c is "\x1b" or c is "\x07"
          i++ if c is "\x1b"
          state = 'normal'

  return out


setAlarm = (notification, cond) ->
  alarm = (data) ->
    message = clean_ansi data.data.slice(1)
    return if cond isnt null and not cond.test(message)

    butterfly.body.classList.remove 'alarm'
    note = "Butterfly [#{ butterfly.title }]"

    if notification
      notif = new Notification(
        note,
        body: message,
        icon: '/static/images/favicon.png')
      notif.onclick = ->
        window.focus()
        notif.close()
    else
      alert(note + '\n' + message)

    butterfly.ws.removeEventListener 'message', alarm

  butterfly.ws.addEventListener 'message', alarm
  butterfly.body.classList.add 'alarm'


cancel = (ev) ->
  ev.preventDefault() if ev.preventDefault
  ev.stopPropagation() if ev.stopPropagation
  ev.cancelBubble = true
  false


document.addEventListener 'keydown', (e) ->
  return true unless e.altKey and e.keyCode is 65

  cond = null
  if e.shiftKey
    cond = prompt('Ring alarm when encountering the following text:
     (can be a regexp)')
    return unless cond
    cond = new RegExp(cond)

  if Notification and Notification.permission is 'default'
    Notification.requestPermission ->
      setAlarm(Notification.permission is 'granted', cond)
  else
    setAlarm(Notification.permission is 'granted', cond)

  cancel(e)
