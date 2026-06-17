import std/sequtils
import sandbox, geom2d, techDraw, interactive
import pkg/sigeo/macros/cursors

type Rotation = V2

letCur t: cache[].mgetOrPut(Rotation, v2(1, 0))

let p = (0..<4).mapIt(p2() + t.rotate(Pi*2 * (it/4)))
for i in 0..<p.len:
  doc.add line(p[i], p[(i + 1) mod 4]), mainLine


ecs_system windowEvent(e: TickEvent):
  let dir =
    if left in e.window.keyboard.pressed: -1
    elif right in e.window.keyboard.pressed: 1
    else: return
  
  t = t.rotate(e.deltaTime.secs * Pi*2 * (1/4) * dir.float)
  redraw e.window
  rerunScript()

