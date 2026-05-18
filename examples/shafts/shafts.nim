import sandbox


const useCustomFont = not defined(nimcheck)

when useCustomFont:
  import text


type
  SectionShape* = enum
    Circle
    Rectangle

  Material* = object
    tension_limit*: float  ## in pascals

  Section* = object
    case shape*: SectionShape
    of Circle:
      circle*: tuple[
        radius: float  # in meters
      ]
    
    of Rectangle:
      rectangle*: tuple[
        w, h: float  # in meters
      ]
    
    material*: Material
    unknownDimensions*: bool



  ShaftConjunctionKind* = enum
    None
    Bevel
    Fillet

  ShaftConjunction* = object
    kind*: ShaftConjunctionKind
    radius*: float

  ShaftSegment* = object
    length*: float  ## in meters
    section*: Section
    left*, right*: ShaftConjunction

  Shaft* = object
    segments*: seq[ShaftSegment]



let darkTheme* = true


let globals* = doc.spawn(
  CanvasSettings(
    autoSize: true,
    margin: vec2(2, 2),
  ),
  AxisYDown,
  (if darkTheme: Foreground color(0.75, 0.75, 0.8) else: Foreground color(0, 0, 0)),
  FontSize 1,
)
if not darkTheme:
  doc.update globals: add Background color(1, 1, 1)



when useCustomFont:
  let font = findSystemFont(@["firacode", "tinos", "timesnewroman", "dejavuserif"] & defaultSystemFonts)
  doc.update globals: add font



let steel* = Material(tension_limit: 160 * 1e6)

proc cylindricSegment*(
  d, l: float,
  material = steel,
  left = ShaftConjunction(),
  right = ShaftConjunction(),
): ShaftSegment =
  ShaftSegment(
    section: Section(shape: Circle, circle: (radius: d/2), material: material),
    length: l, left: left, right: right
  )



