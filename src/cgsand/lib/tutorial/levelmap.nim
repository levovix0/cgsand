{.used.}

import sandbox, geom2d, text
import ./utils

type
  Level = object
    name: string
    subtitle: string
    origin: Point2

let subtitleColor = fg_hint


setupLevel()


doc.add Text tr"Do not import `tutorial` and `tutorial/lXXX_levelname` at the same time!":
  PositionAtBottom
  Position2 point2(0, -2)
  subtitleColor
  FontSize 0.25

doc.add Level(subtitle: "import tutorial/l1_basics", name: tr"Basics", origin: point2(0, 0))
doc.add Level(subtitle: "import tutorial/l2_text", name: tr"Text", origin: point2(0, 4))


doc.forEach (l: Level):
  let name_wh = font_default.withSize(1).typeset(l.name).layoutBounds
  let subtitle_wh = font_default.withSize(0.5).typeset(l.subtitle).layoutBounds

  let wh = v2(max(name_wh.x, subtitle_wh.x), name_wh.y + subtitle_wh.y) + v2(1, 1)
  let tl = l.origin - wh/2

  doc.add Text l.name:
    Position2 l.origin
    PositionAtBottom

  doc.add Text l.subtitle:
    Position2 l.origin + v2(0, 0.5)
    PositionAtTop
    subtitleColor
    FontSize 0.5

  doc.add line(tl, tl + v2(wh.x, 0))
  doc.add line(tl + v2(wh.x, 0), tl + wh)
  doc.add line(tl + wh, tl + v2(0, wh.y))
  doc.add line(tl + v2(0, wh.y), tl)



finishLevel()

