import std/[os, strformat, dynlib, locks]
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



proc compileAndRunScript*(filename: string, outfile: string = "script"): Script =
  new result
  initLock result.lock
  withLock result.lock: result.stage = Compiling

  proc worker(info: tuple[script: ptr ScriptObj, filename, outfile: string]) =
    template result: untyped = info.script[]

    let outfile = info.outfile.withDllExtension
    if (execShellCmd &"nim c --app:lib -o:{quoteShell(outfile)} -d:script {quoteShell(info.filename)}") != 0:
      withLock result.lock: result.stage = Idle
      return
    
    withLock result.lock: result.stage = Executing
    result.lib = loadLib(outfile)
    if result.lib == nil:
      withLock result.lock: result.stage = Idle
      return

    let w = result.lib.symAddr("world_instance")
    if w == nil:
      unloadLib(result.lib)
      result.lib = nil
      withLock result.lock: result.stage = Idle
      return
  
    result.world = cast[ptr World](w)
    withLock result.lock: result.stage = Idle
    
  result.thread.createThread(worker, (result[].addr, filename, outfile))
  

