_set_theme_href = (href) ->
  document.getElementById('style').setAttribute('href', href)
  img = document.createElement('img')
  img.onerror = ->
    setTimeout (-> butterfly?.resize()), 50
  img.src = href;

_theme = localStorage?.getItem('theme')
_set_theme_href(_theme) if _theme

@set_theme = (theme) ->
  _theme = theme
  localStorage?.setItem('theme', theme)
  _set_theme_href(theme) if theme

document.addEventListener 'keydown', (e) ->

document.addEventListener 'keydown', (e) ->
  return true unless e.altKey and e.keyCode is 83
  if e.shiftKey
    style = document.getElementById('style').getAttribute('href')
    style = style.split('?')[0]
    _set_theme_href style + '?' + (new Date().getTime())
    return cancel(e)


  oReq = new XMLHttpRequest()
  oReq.addEventListener 'load', ->
    response = JSON.parse(@responseText)
    themes = response.themes

    if themes.length is 0
      alert("No themes found in #{response.dir}.\n
      Please install themes with butterfly.server.py --install-themes")
      return

    inner = """
        <form>
          <h2>Pick a theme:</h2>
          <select id="theme_list">
    """
    for theme in ['default'].concat(themes)
      if theme is 'default'
        url = "/static/main.css"
      else
        url = "/theme/#{theme}/style.css"
      inner += '<option '

      if _theme is url
        inner += 'selected '

      inner += "value=\"#{url}\">"
      inner += theme
      inner += '</option>'
    inner += """
        </select>
        <label>You can create yours in #{response.dir}.</label>
      </form>
    """
    popup.open inner

    theme_list = document.getElementById('theme_list')

    theme_list.addEventListener 'change', -> set_theme theme_list.value

  oReq.open("GET", "/themes/list.json")
  oReq.send()

  cancel e
