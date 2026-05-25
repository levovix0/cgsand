import std/[math]
import sandbox
import ./[shafts]


proc mm*(m: float): float = m * 1e-3


mainModule:
  let bevel = ShaftConjunction(kind: Bevel, radius: 1.6.mm)
  let fillet = ShaftConjunction(kind: Fillet, radius: 2.mm)
  let shaft = Shaft(
    segments: @[
      cylindricSegment(d = 40.mm, l = 82.mm, left = bevel, right = fillet),
      cylindricSegment(d = 45.mm, l = 87.mm),
      cylindricSegment(d = 50.mm, l = 22.5.mm),
      cylindricSegment(d = 68.75.mm, l = 44.875.mm),
      cylindricSegment(d = 50.mm, l = 22.5.mm),
      cylindricSegment(d = 45.mm, l = 23.mm, right = bevel),
    ]
  )

  draw(shaft)
  
