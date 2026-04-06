import sandbox, geom2d

type
  Positiveness = enum
    `+`
    `-`


let canvasSettings = CanvasSettings_A4_Vertical
# let canvasSettings = CanvasSettings_A4_Horizontal
doc.add canvasSettings

let (w, h) = (canvasSettings.width, canvasSettings.height)


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

