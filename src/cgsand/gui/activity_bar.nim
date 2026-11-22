## vertical activity bar like in VS Code: a column of icon buttons on the far
## left, switching which panel is shown next to it (files explorer / scene tree)

import pkg/pixie
import pkg/sigui/[uibase, mouseArea, animations]
import pkg/toscel/[colors, transitions]
import ../logic/configuration
import ./icons


type
  ActivityView* = enum
    ## which panel the activity bar shows
    avNone     ## the left panel is hidden
    avFiles    ## the file explorer
    avScene    ## the scene tree

  ActivityBar* = ref object of Uiobj
    active*: Property[ActivityView]

  ActivityButton = ref object of MouseArea
    bar: ActivityBar
    view: ActivityView
    icon: Property[Image]


registerComponent ActivityBar
registerComponent ActivityButton


const activityButtonHeight = 44'f32


proc toggle*(this: ActivityBar, view: ActivityView) =
  ## clicking a button shows its panel, or hides the whole panel
  ## if it is already open with this view (VS Code behavior)
  let target =
    case view
    of avFiles: "files"
    of avScene: "scene"
    of avNone: ""

  if target.len == 0: return

  if config.fileTreeVisible[] and config.leftPanelView[] == target:
    config.fileTreeVisible[] = false
  else:
    config.leftPanelView[] = target
    config.fileTreeVisible[] = true


proc iconFor(view: ActivityView, color: Color, uiScale: float32): Image =
  case view
  of avFiles: filesIcon(uiScale, color)
  of avScene: sceneTreeIcon(uiScale, color)
  of avNone: nil


method init(this: ActivityBar) =
  procCall this.super.init()

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = binding: colorTheme[].bgTitleBar

    active = binding:
      if config.fileTreeVisible[]:
        (if config.leftPanelView[] == "scene": avScene else: avFiles)
      else:
        avNone

    for view in [avFiles, avScene]:
      let view = view

      - ActivityButton.new as button:
        x = 0
        y = (if view == avFiles: 0'f32 else: activityButtonHeight)
        this.fillHorizontal(parent)
        h = activityButtonHeight
        cursor = pointingHand

        this.bar = root
        this.view = view

        icon = binding:
          iconFor(view, color(1, 1, 1), this.root.uiScale[])

        - UiRect.new:
          this.fill(parent)
          color = binding:
            if parent.hovered[]: colorTheme[].bgTitleBarSelect
            else: "#00000000".color

          - this.color.transition(0.1's):
            easing = outSquareEasing

        # active view indicator, like in the VS Code activity bar
        - UiRect.new:
          this.left = parent.left
          this.fillVertical(parent)
          w = 2
          color = binding:
            if root.active[] == view: colorTheme[].cActive
            else: "#00000000".color

          - this.color.transition(0.1's):
            easing = outSquareEasing

        - UiImage.new:
          this.centerIn(parent)
          this.w[] = 32
          this.h[] = 32
          this.colorOverlay[] = true  # the icon image is a white mask, colored here
          color = binding:
            (if root.active[] == view: colorTheme[].sText else: colorTheme[].fgMuted)
          this.image = binding:
            let img = parent.icon[]
            if img != nil:
              this.root.ctx.imageFromBuffer(ivec2(img.width.int32, img.height.int32), img.data[0].addr)
            else:
              nil

        on this.clicked:
          this.bar.toggle(view)
