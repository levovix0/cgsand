import std/[math]
import sandbox, geom2d
import pkg/sigeo/surfaces/[grids]
import ./[shafts]


proc mm*(m: float): float = m * 1e-3


proc revolveX(profile: openArray[Point3], pointCount = 32): Grid3 =
  result.kind = Triangles
  let n = profile.len
  for i in 0..<n:
    let p = profile[i]
    let r = sqrt(p.y * p.y + p.z * p.z)
    for j in 0..<pointCount:
      let angle = j.float * 2 * Pi / pointCount.float
      result.points.add point3(p.x, r * cos(angle), r * sin(angle))
  for i in 0..<(n - 1):
    for j in 0..<pointCount:
      let j1 = (j + 1) mod pointCount
      let a = int32(i * pointCount + j)
      let b = int32((i + 1) * pointCount + j)
      let c = int32((i + 1) * pointCount + j1)
      let d = int32(i * pointCount + j1)
      result.indices.add @[a, b, c, a, c, d]


proc draw3d*(profile: World, doc = doc) =
  profile.forEach (curve: LineSection2):
    doc.add PolygonalSurface3 revolveX(@[
      point3(curve.startPoint.x, max(0, curve.startPoint.y), 0),
      point3(curve.endPoint.x, max(0, curve.endPoint.y), 0)
    ])

  profile.forEach (curve: CircleArc2):
    var points: seq[Point3]
    for t in 0..16:
      let p = curve.pointAt(t/16)
      points.add point3(p.x, p.y, 0)
    doc.add PolygonalSurface3 revolveX(points)


mainModule:
  doc[globals, CanvasSettings].margin = v2(10.mm, 10.mm)
  
  let bevel = ShaftConjunction(kind: Bevel, radius: 1.6.mm)
  let fillet = ShaftConjunction(kind: Fillet, radius: 2.mm)
  let shaft = Shaft(
    segments: @[
      cylindricSegment(d = 40.mm, l = 82.mm, left = bevel, right = fillet),
      cylindricSegment(d = 45.mm, l = 87.mm),
      cylindricSegment(d = 50.mm, l = 22.5.mm),
      cylindricSegment(d = 68.75.mm, l = 44.875.mm),
      cylindricSegment(d = 50.mm, l = 22.5.mm),
      cylindricSegment(d = 45.mm, l = 23.mm, right = bevel),
    ]
  )

  var profile = World()

  draw(shaft, dimensions = nil, sketch = profile)
  draw3d(profile)
  
