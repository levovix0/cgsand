import pkg/[ecs]
import pkg/siwin/platforms/any/window
import pkg/sigui/[uibase, mouseArea, animations, layouts]
import pkg/toscel/[comboBox, lineEdit, button]
import ../logic/[config, pdf_renderer]
import std/[os, sequtils]

type
  ToolBar* = ref object of Uiobj
    codeEditor*: Uiobj
    doc*: Property[ptr World]

registerComponent ToolBar



proc windowControlsWidth*(this: ToolBar): float32 =
  180



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

      - ComboBox.new:
        text = binding: config.currentScript[]
        this.options[] = toSeq(walkDirRec(absolutePath("examples"))).mapIt(relativePath(it, absolutePath("examples") / ".."))
        w = 300

        on this.textEdited:
          config.currentScript[] = this.text[]
        
        on this.optionSelected:
          config.currentScript[] = this.text[]


      - Button.new:
        text = tr"Export PDF"
        enabled = binding: root.doc[] != nil

        on this.activated:
          if root.doc[] == nil: return
          let r = PdfRenerer(doc: root.doc[])
          let filters = ["*.pdf".cstring, "*".cstring]
          let filename = "out.pdf"
          if filename != "":
            writePdf filename, r


    - MouseArea.new as mouse1:
      this.fillVertical(parent)
      right = parent.right-120
      w = 60

      - UiRect.new:
        this.fill(parent)

        color = binding:
          if mouse1.pressed[]: "#050F8D".color
          elif mouse1.hovered[]: "#0E2CB1".color
          else: "#00000000".color

        - this.color.transition(0.1's):
          easing = outSquareEasing
      on this.mouseDownAndUpInside:
        this.parentWindow.minimized = true


    - MouseArea.new as mouse2:
      this.fillVertical(parent)
      right = parent.right-60
      w = 60

      - UiRect.new:
        this.fill(parent)

        color = binding:
          if mouse2.pressed[]: "#126731".color
          elif mouse2.hovered[]: "#3bc016".color
          else: "#00000000".color

        - this.color.transition(0.1's):
          easing = outSquareEasing
      on this.mouseDownAndUpInside:
        this.parentWindow.maximized = not this.parentWindow.maximized

