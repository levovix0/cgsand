import std/importutils
import pkg/toscel/[transitions]
import pkg/sigui/[uibase, mouseArea]

privateAccess Anchor

type
  Splitter* = ref object of MouseArea
    anchorGlobalX*: Property[float]
    resized*: Event[float]  # signed distance to anchorGlobalX

registerComponent Splitter


proc `achor=`*(this: Splitter, anchor: Anchor) =
  this.fillVertical(anchor.obj)
  this.left = anchor - 2
  this.right = anchor + 2
  this.makeLayout:
    visibility = binding: anchor.obj.visibility[]


method init*(this: Splitter) =
  procCall this.super.init()

  this.makeLayout:
    globalTransform = true

    - UiRect.new:
      this.fill(parent)

      color = binding:
        if parent.hovered[] or parent.grabbed[]: "#0E77D2".color
        else: "#0E77D200".color
      addTransition this.color

    on this.moved:
      if this.grabbed[]:
        root.resized.emit(this.mouseX[] + this.globalX[] - root.anchorGlobalX[])

