import sandbox, geom2d

type
  Positiveness = enum
    `+`
    `-`


doc.add CanvasSettings_A4_Vertical
# doc.add CanvasSettings_A4_Horizontal

let (w, h) = (doc[CanvasSettings].size.x, doc[CanvasSettings].size.y)


let p = [
  `+`: [
    `+`: point2(w/2 - 1, h/2 - 1),
    `-`: point2(w/2 - 1, -h/2 + 1)
  ],
  `-`: [
    `+`: point2(-w/2 + 1, h/2 - 1),
    `-`: point2(-w/2 + 1, -h/2 + 1)
  ],
]

doc.add lineSection(p[`-`][`-`], p[`+`][`+`])
doc.add lineSection(p[`-`][`+`], p[`+`][`-`])

doc.add lineSection(p[`-`][`-`], p[`+`][`-`])
doc.add lineSection(p[`+`][`-`], p[`+`][`+`])
doc.add lineSection(p[`+`][`+`], p[`-`][`+`])
doc.add lineSection(p[`-`][`+`], p[`-`][`-`])


var v = vec2(50, 0)
for i in 0..<6:
  let v2 = v.rotate(Pi*2 / 6)
  doc.add lineSection(point2() + v, point2() + v2)
  v = v2

