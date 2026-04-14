import ./sandbox
import pkg/pixie/fonts as pixieFonts
import pkg/toscel/fonts as toscelFonts

export pixieFonts, toscelFonts


#[ declared in ./sandbox
type
  Text* = string
  FontSize* = float64
]#


proc withSize*(font: Typeface, size: float64 = 1): Font =
  result = newFont(font)


when isMainModule:
  doc.add Text "Hello, world!"

  doc.add Text "The RED":
    font_default
    color(1, 0, 0)
    FontSize 10
    "width = " & $(font_default.withSize(10).layoutBounds("The RED"))

