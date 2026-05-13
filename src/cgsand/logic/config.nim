import std/json
import pkg/[localize, chroma]
import pkg/sigui/[properties]
import ./syntax_highlighting
export localize

requireLocalesToBeTranslated ("ru", "")


# var currentScript*: Property[string] = "examples/script.nim".property
var currentScript*: Property[string] = "examples/tutorial_use.nim".property

# todo: make config an object
# todo: save and load config


type
  ColorTheme* = object
    cActive*: Color
    cInActive*: Color
    cMiddle*: Color

    bgScrollBar*: Color
    bgVerticalLine*: Color
    bgLineNumbers*: Color
    bgLineNumbersSelect*: Color
    bgTextArea*: Color
    bgStatusBar*: Color
    bgExplorer*: Color
    bgSelectionLabel*: Color
    bgSelection*: Color
    bgTitleBar*: Color
    bgTitleBarSelect*: Color

    sKeyword*: Color
    sOperatorWord*: Color
    sBuiltinType*: Color
    sControlFlow*: Color
    sType*: Color
    sStringLit*: Color
    sStringLitEscape*: Color
    sNumberLit*: Color
    sFunction*: Color
    sComment*: Color
    sTodoComment*: Color
    sError*: Color

    sLineNumber*: Color

    sText*: Color


const vscodeThemeJson* = staticRead("../../../themes/vscode.json")

proc readColor(node: JsonNode, key: string): Color =
  if node.hasKey(key):
    parseHex(node[key].getStr)
  else:
    color(1, 1, 1)

proc parseColorTheme(json: string): ColorTheme =
  let j = parseJson(json)
  result = ColorTheme(
    cActive: j.readColor("cActive"),
    cInActive: j.readColor("cInActive"),
    cMiddle: j.readColor("cMiddle"),
    bgScrollBar: j.readColor("bgScrollBar"),
    bgVerticalLine: j.readColor("bgVerticalLine"),
    bgLineNumbers: j.readColor("bgLineNumbers"),
    bgLineNumbersSelect: j.readColor("bgLineNumbersSelect"),
    bgTextArea: j.readColor("bgTextArea"),
    bgStatusBar: j.readColor("bgStatusBar"),
    bgExplorer: j.readColor("bgExplorer"),
    bgSelectionLabel: j.readColor("bgSelectionLabel"),
    bgSelection: j.readColor("bgSelection"),
    bgTitleBar: j.readColor("bgTitleBar"),
    bgTitleBarSelect: j.readColor("bgTitleBarSelect"),
    sKeyword: j.readColor("sKeyword"),
    sOperatorWord: j.readColor("sOperatorWord"),
    sBuiltinType: j.readColor("sBuiltinType"),
    sControlFlow: j.readColor("sControlFlow"),
    sType: j.readColor("sType"),
    sStringLit: j.readColor("sStringLit"),
    sStringLitEscape: j.readColor("sStringLitEscape"),
    sNumberLit: j.readColor("sNumberLit"),
    sFunction: j.readColor("sFunction"),
    sComment: j.readColor("sComment"),
    sTodoComment: j.readColor("sTodoComment"),
    sError: j.readColor("sError"),
    sLineNumber: j.readColor("sLineNumber"),
    sText: j.readColor("sText"),
  )

let colorTheme* = parseColorTheme(vscodeThemeJson)


proc color*(sk: CodeKind): Color =
  case sk
  of sKeyword:
    colorTheme.sKeyword
  of sOperatorWord:
    colorTheme.sOperatorWord
  of sBuiltinType:
    colorTheme.sBuiltinType
  of sControlFlow:
    colorTheme.sControlFlow
  of sType:
    colorTheme.sType
  of sStringLit, sCharLit:
    colorTheme.sStringLit
  of sStringLitEscape, sCharLitEscape:
    colorTheme.sStringLitEscape
  of sNumberLit:
    colorTheme.sNumberLit
  of sFunction:
    colorTheme.sFunction
  of sComment:
    colorTheme.sComment
  of sTodoComment:
    colorTheme.sTodoComment
  of sLineNumber:
    colorTheme.sLineNumber
  of sError:
    colorTheme.sError
  else:
    colorTheme.sText
