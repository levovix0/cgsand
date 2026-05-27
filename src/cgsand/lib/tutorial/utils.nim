import pkg/localize
import sandbox
export localize


type
  LevelGoal* = object




requireLocalesToBeTranslated ("ru", "")

globalLocale[0] = systemLocale()


let fg* = Foreground color(1, 1, 1)
let fg_hint* = Foreground color(0.5, 0.5, 0.5)
let fg_levelgoal* = fg
let fg_success* = color(0.4, 1, 0.4)
let fg_failure* = color(1, 0.4, 0.4)
let bg* = Background color(0, 0, 0, 0)
let transparent* = color(0, 0, 0, 0)

# todo: let levelgoal* = (LevelGoal(), fg_levelgoal)

let textMargin* = 0.1


proc setupLevel* =
  # globals = doc.spawn(  # todo: `spawn` should allow same syntax as `add`
  #   CanvasSettings(autoSize: true, margin: vec2(2, 2)),
  #   AxisYDown,
  #   FontSize 1,
  #   fg,
  #   bg,
  # )
  doc.update globals: add CanvasSettings(autoSize: true, margin: vec2(2, 2))
  doc.update globals: add AxisYDown
  doc.update globals: add FontSize 1
  doc.update globals: add fg
  doc.update globals: add bg


template finishLevel* =
  updateTranslations()

