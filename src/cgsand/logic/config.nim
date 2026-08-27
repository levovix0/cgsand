import std/[json, os]
import pkg/[localize, chroma, jsony]
import pkg/sigui/[events, properties]
import pkg/toscel/fonts
export localize

requireLocalesToBeTranslated ("ru", "")


type
  Config* = object
    lastOpenedScript*: string = "examples/tutorial_use.nim"

    windowW*: int = 1280
    windowH*: int = 720
    codeEditorVisible*: bool = true

    # todo: make proper attachable and floating panels in toscel
    codeEditorPortion*: float = 1
    previewPortion*: float = 1
    terminalPortion*: float = 0.5

    ## terminal shell executable, empty = platform default (fish on linux, powershell on windows)
    shellPath*: string = ""

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
    writeFile(configFilePath, pretty(%*cfg))
  except: discard


var currentConfig* = loadConfig()


proc getShellCommand*(): string =
  ## shell executable used by the terminal:
  ## `shellPath` from the config, or a platform default
  if currentConfig.shellPath.len > 0:
    return currentConfig.shellPath

  when defined(windows):
    "powershell"
  else:
    let fish = findExe("fish")
    if fish.len > 0: return fish

    result = getEnv("SHELL")
    if result.len == 0: result = "/bin/sh"

var bindings_configAutosave: EventHandler


template autosaveProperty*[T](p: var Property[T], fieldOfConfig) =
  bind bindings_configAutosave
  bind save

  proc `saveConfigOn p change` =
    currentConfig.fieldOfConfig = p[]
    save(currentConfig)
  p[] = currentConfig.fieldOfConfig
  connect(p.changed, bindings_configAutosave, `saveConfigOn p change`)

template autosaveProperty*[T](p: var Property[T]) =
  bind bindings_configAutosave
  bind save

  proc `saveConfigOn p change` =
    currentConfig.p = p[]
    save(currentConfig)
  p[] = currentConfig.p
  connect(p.changed, bindings_configAutosave, `saveConfigOn p change`)


var currentScript*: Property[string]
autosaveProperty currentScript, lastOpenedScript


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


let font_monospace* = findSystemFont(@["firacode", "monospace", "consola"] & @["roboto", "ubuntu", "notosans", "arial", "adwaitasans"])

