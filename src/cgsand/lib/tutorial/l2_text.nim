{.used.}

import sandbox, geom2d
import ./utils
import annotations/dimensions except textMargin
import strformat


setupLevel()
var p: seq[Text]
for x in -3..2:
  for y in  -1 .. 1:
    p.add(fmt"{x.float32+0.5}, {y.float32-0.5}")
echo(p)



addArrow(point2(3.5,0), v2(1,0),0.4, color(1,0.4,0.4))
doc.add lineSection(point2(-3.25, 0), point2(3.25, 0)), Thickness(0.05), color(1,0.4,0.4)

addArrow(point2(0,1.5), v2(0,1),0.4, color(0.4,1,0.4))
doc.add lineSection(point2(0, -2.25), point2(0, 1.25)), Thickness(0.05), color(0.4,1,0.4)


for k in -3..0:
  doc.add lineSection(point2(-3, float64(k+1)), point2(3, float64(k+1)))
for k in -3..3:
  doc.add lineSection(point2(float64(k), -2), point2(float64(k), 1))


let id_del = doc.spawn Text "0.5, -1.5":
  Position2 point2(0.5, -1.5)
  FontSize 0.2
  PositionAtCenter
  fg_hint

doc.add Text "import sandbox, geom2d, tutorial/l2_text":
  Position2 point2(0, -3)
  PositionAtBottom
  FontSize 0.25
  fg_hint

doc.add Text tr"Fill the table with coordinates of the centers":
  Position2 point2(0, -2.5)
  PositionAtBottom
  FontSize 0.35
  fg_levelgoal
  LevelGoal()

doc.add Text """doc.add Text "x,y":
  PositionAtCenter
  Position2 point2(x, y)
  FontSize 0.2""":
  Position2 point2(0, 2.25)
  PositionAtCenter
  FontSize 0.25
  fg_hint

doc.add Text tr"Use cycles and check lib strformat":
  Position2 point2(0, 3)
  PositionAtCenter
  FontSize 0.25
  fg_hint

doc.add Text tr"Call `checkLevel()` to check for completion":
  Position2 point2(0, 3.5)
  PositionAtTop
  FontSize 0.25
  fg_hint


finishLevel()


let lastEntId = doc.entities.high


proc isLevelSuccess: bool =
  var sections: seq[Text]

  doc.forEach (id: EntityId, t: Text):
    if id.int > lastEntId.int:
      sections.add t
  
  for y in p:
    block checkExists:
      for x in sections:
        if (x == y):
          break checkExists
      # else
      return false
  
  return true


proc checkLevel* =
  doc.despawn(id_del)
  if isLevelSuccess():
    doc.forEach (Levelgoal, fg: var Foreground):
      fg = fg_success
  else:
    doc.forEach (Levelgoal, fg: var Foreground):
      fg = fg_failure

