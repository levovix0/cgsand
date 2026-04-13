import sandbox, geom2d, c3d

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


doc.add arc(point2(0, 0), 75, point2(1, 0), point2(0, 1)):
  color(1, 0.2, 0.2)


doc.add circle(point2(0, 0), 50 / cos(Pi/4)):
  color(0.2, 1, 0.2)
  PointCount 100


doc.add circle(point2(0, 0), 50):
  PointCount 6

