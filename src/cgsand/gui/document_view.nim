import sigui/[uibase]


type
  DocumentView* = ref object of Uiobj

registerComponent DocumentView



method init*(this: DocumentView) =
  procCall this.super.init()

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = "#282828".color


