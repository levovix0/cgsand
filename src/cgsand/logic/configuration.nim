import std/[json, os, macros]
import pkg/[localize, chroma, jsony]
import pkg/sigui/[events, properties, uiobj]
import pkg/toscel/fonts
export localize

requireLocalesToBeTranslated ("ru", "")

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


macro genconfig(typename, body: untyped) =
  type Types = seq[tuple[name: NimNode, recList: NimNode]]
  var types: Types
  var propertyComment: string

  proc impl(x: NimNode, recList: var NimNode, path: NimNode) =
    if x.kind == nnkStmtList:
      for x in x:
        impl(x, recList, path)

    elif x.kind == nnkCall and x[1].kind == nnkStmtList and (x[1].len != 1 or x[1][0].kind in {nnkCall, nnkCommentStmt}):
      let subName = ident(path.strVal & "/" & x[0].strVal)
      subName.copyLineInfo(x[0])
      var subRecList = nnkRecList.newTree()
      impl(x[1], subRecList, subName)
      types.add (name: subName, recList: subRecList)
      recList.add newIdentDefs(nnkPostfix.newTree(ident("*"), x[0]), subName)
    
    elif x.kind == nnkCall:
      let name = x[0]
      
      var typ = newEmptyNode()
      var init = newEmptyNode()
      var typinit = x[1]
      if typinit.kind == nnkStmtList: typinit = typinit[0]
      if typinit.kind == nnkAsgn:
        typ = typinit[0]
        init = typinit[1]
      else:
        typ = typinit
      
      recList.add nnkIdentDefs.newTree(
        nnkPostfix.newTree(ident("*"), name),
        nnkBracketExpr.newTree(bindSym("Property"), typ),
        newCall(nnkBracketExpr.newTree(bindSym("property"), typ), init),
      )
      propertyComment = ""  # todo: remember property comment to show it in settings editor

    elif x.kind == nnkCommentStmt:
      if propertyComment != "": propertyComment.add "\n"
      propertyComment.add x.strVal
    
    else:
      error("unexpected syntax", x)
  
  var recList = nnkRecList.newTree()
  for x in body:
    impl(x, recList, ident("Config"))

  result = nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nnkPostfix.newTree(ident("*"), typename),
      newEmptyNode(),
      nnkObjectTy.newTree(
        newEmptyNode(),
        newEmptyNode(),
        recList
      )
    )
  )

  for (name, recList) in types:
    result.add nnkTypeDef.newTree(
      name,
      newEmptyNode(),
      nnkObjectTy.newTree(
        newEmptyNode(),
        newEmptyNode(),
        recList
      )
    )


genconfig Config:
  scriptFile: string = "examples/tutorial_use.nim"

  window:
    w: int = 1280
    h: int = 720
    maximized: bool = false

  codeEditorVisible: bool = true
  terminalVisible: bool = true

  # todo: make proper attachable and floating panels in toscel
  codeEditorPortion: float = 1
  previewPortion: float = 1
  terminalPortion: float = 0.5

  ## terminal shell executable, empty = platform default (fish on linux, powershell on windows)
  shellPath: string = ""

  ## how many lines of scrollback history the terminal main screen keeps (0 disables history)
  terminalScrollbackLines: int = 1000



proc parseHook*(s: string, i: var int, res: var Color) =
  var str: string
  parseHook(s, i, str)
  res = str.toColor

proc dumpHook*(s: var string, v: Color) =
  dumpHook(s, v.toHtmlHex)


proc parseHook*[T](s: string, i: var int, res: var Property[T]) =
  parseHook(s, i, res.unsafeVal)

proc dumpHook*[T](s: var string, v: Property[T]) =
  dumpHook(s, v.unsafeVal)



proc getConfigFilePath*(): string =
  # Checking local path next to the binary
  let localPath = getAppDir() / "config.json"
  if fileExists(localPath):
    return localPath
    
  # If there is no local path, we return the system path.
  return getConfigDir() / "cgsand" / "config.json"

let configFilePath* = getConfigFilePath()

proc loadConfig*: Config =
  if fileExists(configFilePath):
    try:
      fromJson(readFile(configFilePath), Config)
    except: Config()
  else: Config()

proc save*(cfg: Config) =
  try:
    createDir(configFilePath.parentDir)
    writeFile(configFilePath, pretty(cfg.toJson.parseJson))
  except: discard


var config* = loadConfig()


proc getShellCommand*(): string =
  ## shell executable used by the terminal:
  ## `shellPath` from the config, or a platform default
  if config.shellPath[].len > 0:
    return config.shellPath[]

  when defined(windows):
    "powershell"
  else:
    let fish = findExe("fish")
    if fish.len > 0: return fish

    result = getEnv("SHELL")
    if result.len == 0: result = "/bin/sh"


proc subscribe[T](v: var T) =
  when T is Property:
    v.changed.firstHandHandler = proc(env: pointer) {.nimcall.} =
      save config
  else:
    for field in v.fields:
      subscribe field

subscribe config


const vscodeThemeJson = staticRead("../../../themes/vscode.json")

let colorTheme* = vscodeThemeJson.fromJson(ColorTheme)


let font_monospace* = findSystemFont(@["firacode", "monospace", "consola"] & @["roboto", "ubuntu", "notosans", "arial", "adwaitasans"])

