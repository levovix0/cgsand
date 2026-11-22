## scene tree panel: lists the entities of the script's document world (doc),
## each entry showing the entity's main component and the source location of
## the `doc.add` statement that generated it; clicking an entry moves the code
## editor cursor to that location

import std/[strutils, locks]
import pkg/[ecs]
import pkg/sigeo/[curves2d]
import pkg/sigui/[uibase, mouseArea, scrollArea, animations]
import pkg/toscel/[fonts, transitions, colors, label]
import ../logic/[configuration, file_openers, scripts]
import ../lib/[sandbox]


type
  SceneRow = object
    eid: EntityId
    label: string
    path: string   ## SourceLocation file, empty when the entity has no location
    line, col: int

  SceneTree* = ref object of Uiobj
    script*: Property[Script]
    scriptStage*: Property[ScriptStage]
    fileOpener* {.unprintable.}: Property[seq[FileOpener]]
    selected: Property[EntityId]
    sceneVersion: Property[int]
      ## bumped when the world is (re)built, rows are recreated on change


registerComponent SceneTree


const
  sceneFontSize = 13'f32
  sceneRowHeight = 24'f32

  ## components that best name the entity when present;
  ## typeid is used instead of the type name because the app does not
  ## reference every component type, so not all names are registered in it
  primaryComponentTypes = [
    typeid(LineSection2), typeid(CircleArc2), typeid(EllipseArc2),
    typeid(Path2), typeid(Path), typeid(Curve2), typeid(OwnedCurve2),
    typeid(Text), typeid(PolygonalSurface3), typeid(SubWorld),
  ]

  ## component names that describe an entity but don't name it well
  utilityComponentTypes = [
    "EntityId", "SourceLocation", "Color", "Stroke", "Fill", "Thickness",
    "PixelThickness", "Dashing", "Hatching", "DashingScale", "Position2",
    "PositionAt", "FontSize", "Transform3", "Layer", "NoBounds",
    "CanvasSettings", "AxisYDirection", "Typeface", "PointCount",
  ]


proc typeName(tid: TypeId): string =
  ## component name for the known component types, "" for the rest
  ## (`ecs.$` for TypeId works only at compile time, so the mapping is manual)
  case tid
  of typeid(EntityId): "EntityId"
  of typeid(LineSection2): "LineSection2"
  of typeid(CircleArc2): "CircleArc2"
  of typeid(EllipseArc2): "EllipseArc2"
  of typeid(Path2): "Path2"
  of typeid(Path): "Path"
  of typeid(Curve2): "Curve2"
  of typeid(OwnedCurve2): "OwnedCurve2"
  of typeid(Text): "Text"
  of typeid(PolygonalSurface3): "PolygonalSurface3"
  of typeid(SubWorld): "SubWorld"
  of typeid(SourceLocation): "SourceLocation"
  of typeid(Color): "Color"
  of typeid(Stroke): "Stroke"
  of typeid(Fill): "Fill"
  of typeid(Thickness): "Thickness"
  of typeid(PixelThickness): "PixelThickness"
  of typeid(Dashing): "Dashing"
  of typeid(Hatching): "Hatching"
  of typeid(DashingScale): "DashingScale"
  of typeid(Position2): "Position2"
  of typeid(PositionAt): "PositionAt"
  of typeid(FontSize): "FontSize"
  of typeid(Transform3): "Transform3"
  of typeid(sandbox.Layer): "Layer"
  of typeid(NoBounds): "NoBounds"
  of typeid(CanvasSettings): "CanvasSettings"
  of typeid(AxisYDirection): "AxisYDirection"
  of typeid(Typeface): "Typeface"
  else: ""


proc entityLabel(archetype: Archetype): string =
  var fallback = ""
  for tid in archetype:
    let name = typeName(tid)
    if name.len == 0 or name == "EntityId": continue
    if tid in primaryComponentTypes: return name
    if fallback.len == 0 and name notin utilityComponentTypes:
      fallback = name
  if fallback.len > 0: fallback else: "entity"


proc sceneRows(w: World): seq[SceneRow] =
  ## all alive entities in creation order
  for i in 0..<w.entities.len:
    let record = w.entities[i].addr
    if record[].archetype.len == 0: continue  # dead slot
    let eid = makeEntityId(i, record[].generation)
    var row = SceneRow(eid: eid, label: entityLabel(record[].archetype))
    if w.hasComponent(eid, SourceLocation):
      let src = w[eid, SourceLocation]
      row.path = src.file
      row.line = src.line
      row.col = src.col
    result.add row


proc collectRows(this: SceneTree): seq[SceneRow] =
  ## rows of the current script's world, empty when there is none
  let script = this.script[]
  if script == nil or script.world == nil: return
  withLock script.lock:
    if script.stage != Idle: return
  sceneRows(script.world[])


method init*(this: SceneTree) =
  procCall this.super.init()

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = binding: colorTheme[].bgExplorer

    - Label.new:
      left = parent.left + 10
      centerY = parent.top + 16
      text = tr"Scene"
      fontSize = 13
      color = binding: colorTheme[].fgMuted

    # the script has just finished (re)building its world — refresh the rows
    on root.scriptStage[] == Idle:
      if root.script[] != nil:
        root.sceneVersion[] = root.sceneVersion[] + 1

    # note: the ScrollArea itself is created once — recreating it (a changable
    # child on it) from a handler that runs inside the window onTick emit would
    # delete its onTick handler while that same emit is still iterating over it
    - ScrollArea.new:
      left = parent.left
      right = parent.right
      top = parent.top + 32
      bottom = parent.bottom

      --- Uiobj.new:  # the rows, recreated when the world is rebuilt
        <--- {update}: root.sceneVersion[]

        w = binding: parent.w[]

        let rows = root.collectRows()

        if rows.len == 0:
          - Label.new:
            left = parent.left + 10
            top = parent.top + 10
            text =
              (if root.script[] == nil: tr"Script is not running" else: tr"Scene is empty")
            fontSize = 13
            color = binding: colorTheme[].fgMuted

        var rowY = 0'f32
        for row in rows:
          var row = row

          - MouseArea.new:
            x = 0
            y = rowY
            this.fillHorizontal(parent)
            h = sceneRowHeight
            cursor = pointingHand

            - UiRect.new:
              this.fill(parent)
              color = binding:
                let isSelected = row.eid == root.selected[]
                if isSelected:
                  if parent.pressed[]: color_bg_accent_button_pressed[]
                  elif parent.hovered[]: color_bg_accent_button_hovered[]
                  else: color_bg_accent_button[]
                else:
                  if parent.pressed[]: color_bg_button_pressed[]
                  elif parent.hovered[]: color_bg_button_hovered[]
                  else: color_bg_button[]

            - UiText.new:
              x = 10
              centerY = parent.center
              text = row.label
              font = font_default.withSize(sceneFontSize)
              color = binding:
                if row.eid == root.selected[]: color_fg_accent[]
                elif parent.pressed[] or parent.hovered[]: color_fg_active[]
                else: color_fg[]

            - UiText.new:
              this.right = parent.right - 10
              centerY = parent.center
              text = (if row.line > 0: $row.line else: "")
              font = font_monospace.withSize(11)
              color = binding: colorTheme[].fgMuted

            on this.clicked:
              root.selected[] = row.eid
              if row.path.len > 0:
                root.fileOpener[].open(Location(path: row.path, line: row.line, col: row.col))

          rowY += sceneRowHeight

        h = rowY
