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


doc.add Level(subtitle: "import tutorial/l1_basics", name: tr"Basics", origin: point2(0, 0))


doc.forEach (l: Level):
  let name_wh = font_default.withSize(1).typeset(l.name).layoutBounds
  let subtitle_wh = font_default.withSize(0.5).typeset(l.subtitle).layoutBounds

  let wh = vec2(max(name_wh.x, subtitle_wh.x), name_wh.y + subtitle_wh.y) + vec2(1, 1)
  let tl = l.origin - wh/2

  doc.add Text l.name:
    Position2 l.origin
    PositionAtBottom

  doc.add Text l.subtitle:
    Position2 l.origin + vec2(0, 0.5)
    PositionAtTop
    subtitleColor
    FontSize 0.5

  doc.add lineSection(tl, tl + vec2(wh.x, 0))
  doc.add lineSection(tl + vec2(wh.x, 0), tl + wh)
  doc.add lineSection(tl + wh, tl + vec2(0, wh.y))
  doc.add lineSection(tl + vec2(0, wh.y), tl)



finishLevel()

