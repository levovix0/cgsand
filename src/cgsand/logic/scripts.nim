import std/[os, strformat, dynlib]
import pkg/[ecs]


type
  Script* = ref ScriptObj
  ScriptObj = object
    lib*: LibHandle
    world*: ptr World


proc `=destroy`(this: ScriptObj) =
  unloadLib(this.lib)



proc withDllExtension(path: string): string =
  let (dir, name, _) = path.splitFile
  when defined(windows):
    dir / name & ".dll"
  else:
    dir / "lib" & name & ".so"



proc compileAndRunScript*(filename: string, outfile: string = "script"): Script =
  let outfile = outfile.withDllExtension
  if (execShellCmd &"nim c --app:lib -o:{quoteShell(outfile)} -d:script {quoteShell(filename)}") != 0: return nil
  
  let lib = loadLib(outfile)
  if lib == nil: return nil

  let w = lib.symAddr("world_instance")
  if w == nil:
    unloadLib(lib)
    return nil
  
  Script(
    lib: lib,
    world: cast[ptr World](w),
  )

