import sandbox, geom2d

type
  Positiveness = enum
    `+`
    `-`


doc.add CanvasSettings_A4_Vertical
# doc.add CanvasSettings_A4_Horizontal


let p = [
  `+`: [
    `+`: point2(50, 50),
    `-`: point2(50, -50)
  ],
  `-`: [
    `+`: point2(-50, 50),
    `-`: point2(-50, -50)
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

