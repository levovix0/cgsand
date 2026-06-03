{.used.}

import sandbox, geom2d
import ./utils



setupLevel()


let p = [point2(1, 1), point2(-1, 1), point2(-1, -1), point2(1, -1)]


doc.add circle(p[0], 0.1):
  Background fg_hint

doc.add circle(p[1], 0.1):
  Background fg_hint

doc.add circle(p[2], 0.1):
  Background fg_hint

doc.add circle(p[3], 0.1):
  Background fg_hint


doc.add Text "point2(1, 1)":
  Position2 p[0] + vec2(1, 1)*textMargin
  PositionAtTopLeft
  FontSize 0.25
  fg_hint

doc.add Text "point2(-1, 1)":
  Position2 p[1] + vec2(-1, 1)*textMargin
  PositionAtTopRight
  FontSize 0.25
  fg_hint

doc.add Text "point2(-1, -1)":
  Position2 p[2] + vec2(-1, -1)*textMargin
  PositionAtBottomRight
  FontSize 0.25
  fg_hint

doc.add Text "point2(1, -1)":
  Position2 p[3] + vec2(1, -1)*textMargin
  PositionAtBottomLeft
  FontSize 0.25
  fg_hint


doc.add Text "import sandbox, geom2d, tutorial/l1_basics":
  Position2 point2(0, -2)
  PositionAtBottom
  FontSize 0.25
  fg_hint


doc.add Text "doc.add lineSection(point2(0, 0), point2(1, 0))":
  Position2 point2(0, 2)
  PositionAtTop
  FontSize 0.25
  fg_hint


doc.add Text tr"Create a square on points above":
  Position2 point2(0, 2.5)
  PositionAtTop
  FontSize 0.3
  fg_levelgoal
  LevelGoal()

doc.add Text tr"Call `checkLevel()` to check for completion":
  Position2 point2(0, 3)
  PositionAtTop
  FontSize 0.25
  fg_hint





let lastEntId = doc.entities.high


proc isLevelSuccess: bool =
  var sections: seq[LineSection]

  doc.forEach (id: EntityId, l: LineSection, t: Text):
    if id.int > lastEntId.int:
      sections.add l
  
  let reqSections = [lineSection(p[0], p[1]), lineSection(p[1], p[2]), lineSection(p[2], p[3]), lineSection(p[3], p[0])]
  for y in reqSections:
    block checkExists:
      for x in sections:
        if (x.a ~== y.a and x.b ~== y.b) or (x.b ~== y.a and x.a ~== y.b):
          break checkExists
      # else
      return false
  
  return true


proc checkLevel* =
  if isLevelSuccess():
    doc.forEach (Levelgoal, fg: var Foreground):
      fg = fg_success
    doc.add Text tr"To move to the next level, replace l1_basics with l2_text":
        Position2 point2(0, -2.5)
        PositionAtBottom
        FontSize 0.25
  else:
    doc.forEach (Levelgoal, fg: var Foreground):
      fg = fg_failure

finishLevel()