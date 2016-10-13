Terminal.on 'change', (line) ->
  if 'extended' in line.classList
    line.addEventListener 'click', do (line) -> ->
      if 'expanded' in line.classList
        line.classList.remove 'expanded'
      else
        before = line.getBoundingClientRect().height
        line.classList.add 'expanded'
        after = line.getBoundingClientRect().height
        document.body.scrollTop += after - before
