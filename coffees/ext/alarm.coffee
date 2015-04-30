setAlarm = (notification) ->
  alarm = (data) ->
    butterfly.body.classList.remove 'alarm'
    note = "New activity on butterfly terminal [#{ butterfly.title }]"

    if notification
      new Notification(
        note,
        body: data.data,
        icon: '/static/images/favicon.png')
    else
      alert(note + '\n' + data.data)

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

  if Notification and Notification.permission is 'default'
    Notification.requestPermission ->
      setAlarm(Notification.permission is 'granted')
  else
    setAlarm(Notification.permission is 'granted')

  cancel(e)
