Terminal.on 'change', (lines) ->
  for line in lines
    if 'extended' in line.classList
      line.addEventListener 'click', do (line) -> ->
        if 'expanded' in line.classList
          line.classList.remove 'expanded'
        else
          line.classList.add 'expanded'
          butterfly.nativeScrollTo()
