import pkg/siwin/platforms/any/window
import pkg/sigui/[uibase, mouseArea, animations, layouts]
import pkg/toscel/[lineEdit, button]
import ../logic/[config]


type
  ToolBar* = ref object of Uiobj
    codeEditor*: Uiobj

registerComponent ToolBar



proc windowControlsWidth*(this: ToolBar): float32 =
  60



method init*(this: ToolBar) =
  procCall this.super.init()

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = "#303030".color

    - MouseArea.new:
      this.fill(parent)

      this.clicked.connectTo this, e:
        if e.double:
          this.parentWindow.maximized = not this.parentWindow.maximized
    

    - MouseArea.new as mouse:
      this.fillVertical(parent)
      right = parent.right
      w = 60

      - UiRect.new:
        this.fill(parent)

        color = binding:
          if mouse.pressed[]: "#ca3e3eff".color
          elif mouse.hovered[]: "#ff5959ff".color
          else: "#00000000".color
      
        - this.color.transition(0.1's):
          easing = outSquareEasing
      
      on this.mouseDownAndUpInside:
        close this.parentWindow
    

    - Layout.row:
      centerY = parent.center
      left = parent.left + 10
      gap = 10

      - Button.new:
        text = tr"Code"
        accent = binding: root.codeEditor.visibility[] == visible

        on this.activated:
          root.codeEditor.visibility[] = (if root.codeEditor.visibility[] == visible: collapsed else: visible)

      - LineEdit.new:
        w = 300
        text = binding: config.currentScript[]

        on this.textEdited:
          config.currentScript[] = this.text[]


