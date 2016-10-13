tid = null
packSize = 1000
histSize = 100

maybePack = ->
  return unless butterfly.term.childElementCount > packSize + butterfly.rows
  hist = document.getElementById 'packed'
  packfrag = document.createDocumentFragment 'fragment'
  for i in [0..packSize]
    packfrag.appendChild butterfly.term.firstChild
  pack = document.createElement 'div'
  pack.classList.add 'pack'
  pack.appendChild packfrag
  hist.appendChild pack

  hist.firstChild.remove() if hist.childElementCount > histSize

  tid = setTimeout maybePack


Terminal.on 'refresh', ->
  clearTimeout tid if tid
  maybePack()

Terminal.on 'clear', ->
  newHist = document.createElement 'div'
  newHist.id = 'packed'
  hist = document.getElementById 'packed'
  butterfly.body.replaceChild newHist, hist
