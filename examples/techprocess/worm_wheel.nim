import sandbox, geom2d, techDraw

type
  Stroke = object
    repeated: bool   # 1..n

  Transition = object
    strokes: seq[Stroke]

  Installation = object
    transitions: seq[Transition]

  Operation = object
    id: string
    name: string
    installations: seq[Installation]
  
  ProcessingRoute = object
    operations: seq[Operation]


proc oneInst(repeated = false): seq[Installation] =
  @[Installation(transitions: @[Transition(strokes: @[Stroke(repeated: repeated)])])]


let colored_metal_path = ProcessingRoute(
  operations: @[
    Operation(
      name: "Литьё заготовки",
      id: "05",
      installations: oneInst(),
    ),
    Operation(
      name: "Термическая обработка",
      id: "10",
      installations: oneInst(),
    ),
    Operation(
      name: "Растачивание (черновое)",
      id: "15",
      installations: oneInst(),
    ),
    Operation(
      name: "Растачивание (чистовое)",
      id: "20",
      installations: oneInst(),
    ),
    Operation(
      name: "Тонкое растачивание",
      id: "25",
      installations: oneInst(),
    ),
  ]
)

proc display(route: ProcessingRoute) =
  var x = 0.0
  for i, op in route.operations:
    var w = 10.0
    var h = 2.0
    var y = 0.0
    
    template lineToNext = doc.add line(p2(x + w/2, y + h), p2(x + w/2, y + h + 2))
    
    doc.add rectPath(x, y, w, h)
    doc.add Text "Оп. " & op.id, Position2 p2(x + w/2, y + h/2), PositionAtCenter
    lineToNext
    if i != 0:
      doc.add line(p2(x - 5, y + h/2), p2(x, y + h/2))
    
    y += h + 2
    h = 4
    doc.add polygon(p2(x, y), p2(x + w, y), p2(x + w/2, y + h))
    doc.add Text "У1", Position2 p2(x + w/2, y + h/2), PositionAtBottom
    lineToNext
    
    y += h + 2
    doc.add circle(p2(x + w/2, y + h/2), h/2)
    doc.add Text "ТП1", Position2 p2(x + w/2, y + h/2), PositionAtCenter
    lineToNext
    
    y += h + 2
    h = 2
    doc.add rectPath(x, y, w, h)
    doc.add Text "рх1" & (if op.installations[0].transitions[0].strokes[0].repeated: "..n" else: ""), Position2 p2(x + w/2, y + h/2), PositionAtCenter
    
    x += w + 5


display colored_metal_path

