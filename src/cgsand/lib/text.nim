import ./sandbox
import pkg/sigui/rendering as siguiRendering
import pkg/toscel/fonts as toscelFonts

export siguiRendering except Path, DrawContext
export toscelFonts


#[ declared in ./sandbox
type
  Text* = string
  FontSize* = float64
]#


when isMainModule:
  doc.add Text "Hello, world!"

  doc.add Text "The RED":
    font_default
    color(1, 0, 0)
    FontSize 10
    "width = " & $(font_default.withSize(10).layoutBounds("The RED"))

