import std/[os, strformat, strutils, dynlib, locks]
import pkg/[ecs]


type
  ScriptStage* = enum
    Idle
    Compiling
    Executing
    # BuildingRenderTree

  Script* = ref ScriptObj
  ScriptObj* = object
    lib*: LibHandle
    world*: ptr World
    stage* {.guard: lock.}: ScriptStage
    lock*: Lock

    thread: Thread[tuple[script: ptr ScriptObj, filename, outfile: string]]


proc `=destroy`(this: ScriptObj) =
  if this.lib != nil:
    unloadLib(this.lib)

  if this.thread.running:
    joinThread this.thread



proc withDllExtension(path: string): string =
  let (dir, name, _) = path.splitFile
  when defined(windows):
    dir / name & ".dll"
  else:
    dir / "lib" & name & ".so"



when not defined(windows):
  import posix

  type SigJmpBuf {.importc: "sigjmp_buf".} = object

  # must be a macro to not create a new stackframe
  {.emit: """
#include <setjmp.h>
#include <signal.h>
#define nimSigsetjmp(env, savemask) sigsetjmp(*(sigjmp_buf*)(env), (savemask))
static void nimSiglongjmp(void* env, int val) { siglongjmp(*(sigjmp_buf*)env, val); }
""".}
  proc sigsetjmpW(env: var SigJmpBuf, savemask: cint): cint {.importc: "nimSigsetjmp", nodecl.}
  proc siglongjmpW(env: var SigJmpBuf, val: cint) {.importc: "nimSiglongjmp", nodecl, noreturn.}


when not defined(windows):
  var tlsScriptJmpBuf {.threadvar.}: SigJmpBuf
  var tlsInScriptLoad {.threadvar.}: bool

  {.push stackTrace: off.}
  proc scriptCrashSignalHandler(sig: cint) {.noconv.} =
    # stackTrace is off so Nim won't set up a frame here
    if tlsInScriptLoad:
      siglongjmpW(tlsScriptJmpBuf, 1)
    # else
    signal(sig, SIG_DFL)
    discard kill(getpid(), sig)
  {.pop.}


proc generateScriptWrapper(scriptPath, wrapperPath: string) =
  ## Generates a wrapper DLL that isolates the user script from the host process.
  ##
  ## For Nim exceptions (IndexDefect, ValueError, etc): the script's non-import code
  ## is placed inside `proc scriptRun()` which is called from a module-level try/except.
  ## Any Nim exception that escapes scriptRun is caught here and recorded in `script_load_failed`.
  ##
  ## Native crashes (SIGSEGV, SIGFPE): the DLL is compiled with -d:noSignalHandler
  ## so it does not install Nim's built-in signal handler (which would otherwise call c_raise(SIG_DFL) and kill the process).
  ## Instead the host installs a siglongjmp-based handler in tryLoadScriptLib before calling loadLib.
  ## On crush tryLoadScriptLib then returns (nil, nil).
  let lines = readFile(scriptPath).splitLines()
  var importLines, bodyLines: seq[string]
  for line in lines:
    let s = line.strip()
    if s.startsWith("import ") or s.startsWith("from ") or
       s == "import"           or s == "from":
      importLines.add line
    else:
      bodyLines.add line

  var bodyIndented = ""
  for line in bodyLines:
    if line.strip().len > 0:
      bodyIndented.add "  " & line & "\n"
    else:
      bodyIndented.add "\n"

  # Import statements from the user script must be at module level (Nim does not allow `import` inside try/except)
  # so the script is split: import lines go to the wrapper's top level; everything else goes into scriptRun().
  writeFile(wrapperPath, &"""
{importLines.join("\n")}

var scriptLoadFailed* {{.exportc: "script_load_failed", dynlib.}}: bool = false

proc scriptRun() =
  discard  # ensures the proc body is never empty
{bodyIndented}
try:
  scriptRun()
except CatchableError as e:
  scriptLoadFailed = true
  stderr.writeLine("script error: " & e.msg)
except Defect as e:
  scriptLoadFailed = true
  stderr.writeLine("script defect: " & e.msg)
""")


proc tryLoadScriptLib(path: string): tuple[lib: LibHandle, world: ptr World] =
  ## Loads the script DLL with two-layer crash protection.
  ## Returns (nil, nil) on any failure.
  when defined(windows):
    let lib = loadLib(path)
    if lib == nil: return
    let failed = cast[ptr bool](lib.symAddr("script_load_failed"))
    if failed != nil and failed[]:
      unloadLib(lib)
      return
    let w = lib.symAddr("world_instance")
    if w == nil:
      unloadLib(lib)
      return
    return (lib, cast[ptr World](w))
  else:
    # prevSig* must be set BEFORE sigsetjmpW so they are not clobbered by longjmp.
    tlsInScriptLoad = true
    let prevSigsegv = signal(SIGSEGV, scriptCrashSignalHandler)
    let prevSigfpe  = signal(SIGFPE,  scriptCrashSignalHandler)

    if sigsetjmpW(tlsScriptJmpBuf, 1) != 0:
      # A native crash fired inside the DLL initialiser.
      # The lib handle is in an indeterminate state — skip unloadLib to avoid a secondary fault.
      tlsInScriptLoad = false
      discard signal(SIGSEGV, prevSigsegv)
      discard signal(SIGFPE,  prevSigfpe)
      return  # (nil, nil)

    let lib = loadLib(path)  # DLL init (scriptRun) runs here

    tlsInScriptLoad = false
    discard signal(SIGSEGV, prevSigsegv)
    discard signal(SIGFPE,  prevSigfpe)

    if lib == nil: return

    # Nim-exception protection via wrapper try/except
    let failed = cast[ptr bool](lib.symAddr("script_load_failed"))
    if failed != nil and failed[]:
      unloadLib(lib)
      return  # (nil, nil)

    let w = lib.symAddr("world_instance")
    if w == nil:
      unloadLib(lib)
      return

    return (lib, cast[ptr World](w))


proc compileAndRunScript*(filename: string, outfile: string = "script"): Script =
  new result
  initLock result.lock
  withLock result.lock: result.stage = Compiling

  proc worker(info: tuple[script: ptr ScriptObj, filename, outfile: string]) =
    template result: untyped = info.script[]

    let outfile = info.outfile.withDllExtension
    let wrapperPath = info.outfile & "_wrapper.nim"

    generateScriptWrapper(info.filename, wrapperPath)

    # -d:noSignalHandler: prevents the DLL from installing Nim's built-in SIGSEGV handler, which would overwrite our siglongjmp-based one.
    if (execShellCmd &"nim c --app:lib -d:noSignalHandler -o:{quoteShell(outfile)} -d:script {quoteShell(wrapperPath)}") != 0:
      withLock result.lock: result.stage = Idle
      return

    withLock result.lock: result.stage = Executing

    let (lib, world) = tryLoadScriptLib(outfile)
    result.lib = lib
    result.world = world
    withLock result.lock: result.stage = Idle

  result.thread.createThread(worker, (result[].addr, filename, outfile))
