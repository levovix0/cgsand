import std/unicode

proc isWordRune*(r: Rune): bool =
  r.isAlpha or r.uint32 in 48'u32 .. 57'u32 or r == Rune('_')
