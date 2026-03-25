import sigui/[uibase]


type
  CodeEditor* = ref object of Uiobj

registerComponent CodeEditor



method init*(this: CodeEditor) =
  procCall this.super.init()

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = "#202020".color


