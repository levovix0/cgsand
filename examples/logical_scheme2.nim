import std/[sequtils, tables, hashes, sets]
import sandbox, geom2d, c3d
import pkg/bumpy

type
  NodeKind = enum
    SymN
    BoxN

  Node = ref object
    kind: NodeKind
    inputs: seq[tuple[n: Node, port: int]]
    outputs: seq[bool]  # true - regular out, false - inversed out
    name: string
  
  Line = object
    nodes: seq[Node]
    gap: float32
    align: bool  # if true, align all nodes to their inputs, so connection does not need to bend (and ignore gap)
    origin: Point2
  
  Bus = object
    input: Node
    outputs: seq[Node]
    origin: Point2
    color: Color = color(0, 0, 0)

  Connection = seq[Point2]
  Branch = Point2


doc.add CanvasSettings(autoSize: true, margin: vec2(1)):
  AxisYDown
  FontSize 1
  Background color(1, 1, 1)
  Foreground color(0, 0, 0)


converter toNode*(name: string): Node = Node(kind: SymN, name: name)

proc orN*(inputs: varargs[Node]): Node =
  Node(kind: BoxN, name: "1", inputs: inputs.mapIt((it, 0)), outputs: @[true])
proc andN*(inputs: varargs[Node]): Node =
  Node(kind: BoxN, name: "&", inputs: inputs.mapIt((it, 0)), outputs: @[true])
proc norN*(inputs: varargs[Node]): Node =
  Node(kind: BoxN, name: "1", inputs: inputs.mapIt((it, 0)), outputs: @[false])
proc nandN*(inputs: varargs[Node]): Node =
  Node(kind: BoxN, name: "&", inputs: inputs.mapIt((it, 0)), outputs: @[false])
proc symN*(name: string, inputs: varargs[Node]): Node =
  Node(kind: SymN, name: name, inputs: inputs.mapIt((it, 0)), outputs: @[true])

proc orN*(inputs: varargs[(Node, int)]): Node =
  Node(kind: BoxN, name: "1", inputs: inputs.toSeq, outputs: @[true])
proc andN*(inputs: varargs[(Node, int)]): Node =
  Node(kind: BoxN, name: "&", inputs: inputs.toSeq, outputs: @[true])
proc norN*(inputs: varargs[(Node, int)]): Node =
  Node(kind: BoxN, name: "1", inputs: inputs.toSeq, outputs: @[false])
proc nandN*(inputs: varargs[(Node, int)]): Node =
  Node(kind: BoxN, name: "&", inputs: inputs.toSeq, outputs: @[false])
proc symN*(name: string, inputs: varargs[(Node, int)]): Node =
  Node(kind: BoxN, name: name, inputs: inputs.toSeq, outputs: @[true])

proc hash(n: Node): Hash = hash(cast[pointer](n))



let inputs = @[Node "x3", "x2", "x1"]
let inverted = inputs.mapIt(norN(it))

var outputs: seq[Node]
block:
  var i = 0
  for x3 in 0..1:
    for x2 in 0..1:
      for x1 in 0..1:
        let n = [inverted, inputs]
        outputs.add andN(n[x3][0], n[x2][1], n[x1][2])
        inc i

var outputNames = (0..<outputs.len).mapIt(symN("y" & $it, outputs[it]))



let lines = (
  Line(origin: point2(0, 3),    nodes: inputs, gap: 7),
  Line(origin: point2(4, 0),    nodes: inverted, gap: 6),
  Bus( origin: point2(8, 0),    input: inputs[0], outputs: outputs, color: color(0.6, 0, 0)),
  Bus( origin: point2(8.5, 0),  input: inverted[0], outputs: outputs, color: color(0, 0, 0)),
  Bus( origin: point2(10, 0),   input: inputs[1], outputs: outputs, color: color(0, 0.6, 0)),
  Bus( origin: point2(10.5, 0), input: inverted[1], outputs: outputs, color: color(0, 0, 0)),
  Bus( origin: point2(12, 0),   input: inputs[2], outputs: outputs, color: color(0, 0, 0.6)),
  Bus( origin: point2(12.5, 0), input: inverted[2], outputs: outputs, color: color(0, 0, 0)),
  Line(origin: point2(16, 0),   nodes: outputs, gap: 0),
  Line(origin: point2(20, 0),   nodes: outputNames, gap: 0, align: true),
)



proc placeComponents =
  var nodeRects = initTable[Node, Rect]()

  proc nodeSize(n: Node): Vec2 =
    case n.kind
    of SymN: vec2(1, 1)
    of BoxN: vec2(2, max(2.0, n.inputs.len.float))

  proc inputPortY(n: Node, r: Rect, portIdx: int): float32 =
    case n.kind
    of SymN: r.y
    of BoxN: r.y + r.h * float32(portIdx + 1) / float32(n.inputs.len + 1)

  proc outputPortY(n: Node, r: Rect, portIdx: int): float32 =
    case n.kind
    of SymN: r.y
    of BoxN: r.y + r.h * float32(portIdx + 1) / float32(n.outputs.len + 1)

  type ConnKey = tuple[n: pointer, port: int]
  var busHandled = initHashSet[ConnKey]()

  # Pass 1: collect which (node, portIdx) pairs are connected via buses
  for elem in lines.fields:
    when elem is Bus:
      for outNode in elem.outputs:
        for portIdx, inp in outNode.inputs:
          if inp.n == elem.input:
            busHandled.incl (cast[pointer](outNode), portIdx)

  # Pass 2: place (Node, Rect)
  for elem in lines.fields:
    when elem is Line:
      var pos = elem.origin
      for node in elem.nodes:
        let sz = nodeSize(node)
        var r: Rect
        if elem.align and node.inputs.len > 0:
          let inp0 = node.inputs[0]
          let inRect = nodeRects[inp0.n]
          let connectY = outputPortY(inp0.n, inRect, inp0.port)
          r = rect(pos.x.float32, connectY, sz.x.float32, sz.y.float32)
        else:
          r = rect(pos.x.float32, pos.y.float32, sz.x.float32, sz.y.float32)
          pos.y += sz.y + elem.gap.float
        nodeRects[node] = r
        doc.add node, r

  # Pass 3: place Connection and Branch
  for elem in lines.fields:
    when elem is Line:
      for node in elem.nodes:
        let r = nodeRects[node]
        for portIdx, inp in node.inputs:
          if (cast[pointer](node), portIdx) notin busHandled and inp.n in nodeRects:
            let inRect = nodeRects[inp.n]
            let fromY = outputPortY(inp.n, inRect, inp.port)
            let toY = inputPortY(node, r, portIdx)
            let p1 = point2(inRect.x + inRect.w, fromY)
            let p2 = point2(r.x, toY)
            if abs(fromY - toY) < 0.001:
              doc.add Connection(@[p1, p2])
            else:
              let midX = (p1.x + p2.x) / 2.0
              doc.add Connection(@[
                p1,
                point2(midX, fromY),
                point2(midX, toY),
                p2,
              ])
              doc.add Branch point2(midX, fromY)  # todo

    when elem is Bus:
      let inNode = elem.input
      if inNode in nodeRects:
        let inRect = nodeRects[inNode]
        let busX = elem.origin.x.float32
        let startY = outputPortY(inNode, inRect, 0)

        var busConns: seq[tuple[n: Node, port: int]]
        for outNode in elem.outputs:
          for portIdx, inp in outNode.inputs:
            if inp.n == inNode and outNode in nodeRects:
              busConns.add (outNode, portIdx)

        if busConns.len > 0:
          var minBusY = startY
          var maxBusY = startY
          for bc in busConns:
            let portY = inputPortY(bc.n, nodeRects[bc.n], bc.port)
            minBusY = min(minBusY, portY)
            maxBusY = max(maxBusY, portY)

          # horizontal wire from input node output to bus
          doc.add Connection(@[
            point2(inRect.x + inRect.w, startY),
            point2(busX, startY),
          ]):
            elem.color
          # vertical bus wire
          doc.add Connection(@[
            point2(busX, minBusY),
            point2(busX, maxBusY),
          ]):
            elem.color
          # horizontal branches from bus to each AND gate input port
          for i, bc in busConns:
            let outRect = nodeRects[bc.n]
            let portY = inputPortY(bc.n, outRect, bc.port)
            doc.add Connection(@[point2(busX, portY), point2(outRect.x, portY)]):
              elem.color
            if i != 0 and i != busConns.high:
              doc.add Branch point2(busX, portY):  # branch dot
                elem.color



proc drawComponents =
  doc.forEach (c: Connection, color: Color||color(0, 0, 0)):
    for i in 0..<(c.len-1):
      doc.add lineSection(c[i], c[i + 1]):
        color

  doc.forEach (b: Branch, color: Color||color(0, 0, 0)):
    doc.add circle(center = b.Point2, radius = 0.1):
      color
      Background color

  doc.forEach (n: Node, r: Rect):
    case n.kind
    of BoxN:
      let p = [point2(r.x, r.y), point2(r.x + r.w, r.y), point2(r.x + r.w, r.y + r.h), point2(r.x, r.y + r.h)]
      doc.add lineSection(p[0], p[1])
      doc.add lineSection(p[1], p[2])
      doc.add lineSection(p[2], p[3])
      doc.add lineSection(p[3], p[0])
    
      doc.add Text n.name:
        Position2 point2(r.x + r.w/2, r.y + 0.1)
        PositionAtTop
    
      for i, o in n.outputs:
        let p = point2(r.x + r.w, r.y + r.h * ((i + 1) / (n.outputs.len + 1)))
        if not o:
          doc.add circle(center = p, radius = 0.1):
            Background color(1, 1, 1)
    
    of SymN:
      doc.add lineSection(point2(r.x, r.y), point2(r.x + r.w, r.y))
      doc.add Text n.name:
        Position2 point2(r.x + r.w/2, r.y - 0.1)
        PositionAtBottom


placeComponents()
drawComponents()


