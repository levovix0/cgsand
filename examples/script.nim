import sandbox, geom2d


doc.add lineSection(point2(-50, -50), point2(50, 50))
doc.add lineSection(point2(-50, 50), point2(50, -50))


var v = vec2(50, 0)
for i in 0..<6:
  let v2 = v.rotate(Pi*2 / 6)
  doc.add lineSection(point2() + v, point2() + v2)
  v = v2

