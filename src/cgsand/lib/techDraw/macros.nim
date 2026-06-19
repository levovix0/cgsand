import std/[macros, strutils]
import sandbox
import ./globals

import pkg/sigeo/macros/[genAliases, cursors]
export genAliases, cursors


proc sketchImpl(procdef: NimNode, procName: NimNode): NimNode =
  #[
    for ```nim
      proc drawSection*(g: GearDesc, sketch = doc, backLines = true, axialLines = true, centralAxial = true, hatching = true) =
        ## ...
    ```
    define something like ```nim
      proc sketchSection*(g: GearDesc, backLines = true, axialLines = true, centralAxial = true, hatching = true): World =
        result = newTechDraw()
        withDocument result: drawSection(g, backLines = backLines, axialLines = axialLines, centralAxial = centralAxial, hatching = hatching)
    ```
    if there are multiple world in function args, result is named tuple
  ]#
 
  var params: seq[NimNode]
  var worlds: seq[NimNode]
  let procdef = procdef.getImpl
  var call = newCall(procdef[0])

  for x in procdef.params[1..^1]:
    for nameSym in x[0..^3]:
      let name = nameSym.strVal.ident
      if nameSym.sameType(bindSym("World")):
        worlds.add nnkIdentDefs.newTree(name, x[^2], x[^1])
      else:
        params.add nnkIdentDefs.newTree(name, x[^2], x[^1])
  
  var rettype = (if worlds.len == 1: bindSym("World") else: nnkTupleTy.newTree())
  
  for x in procdef.params[1..^1]:
    for nameSym in x[0..^3]:
      let name = nameSym.strVal.ident
      if nameSym.sameType(bindSym("World")):
        call.add (if worlds.len == 1: ident("result") else: nnkDotExpr.newTree(ident("result"), name))
        if worlds.len != 1:
          rettype.add nnkIdentDefs.newTree(name, bindSym("World"), newEmptyNode())
      else:
        call.add name

  var worldInit: seq[NimNode]
  if worlds.len == 1:
    worldInit.add nnkAsgn.newTree(ident("result"), newCall(bindSym("newTechDraw")))
  else:
    for x in worlds:
      worldInit.add nnkAsgn.newTree(nnkDotExpr.newTree(ident("result"), x[0]), newCall(bindSym("newTechDraw")))
  

  result = nnkProcDef.newTree(
    nnkPostfix.newTree(
      ident("*"),
      procName,
    ),
    newEmptyNode(),
    newEmptyNode(),
    nnkFormalParams.newTree(@[rettype] & params),
    newEmptyNode(),
    newEmptyNode(),
    newStmtList(worldInit & newCall(bindSym("withDocument"), (if worlds.len == 1: ident("result") else: worldInit[0][0]), call)),
  )


macro defineSketch*(procname: typed, name: static string) =
  let procname = if procname.kind == nnkSym: procname else: procname[^1]
  sketchImpl(procname, ident(name))

macro defineSketch*(procname: typed) =
  let procname = if procname.kind == nnkSym: procname else: procname[^1]
  let name = ident(procname.strVal.replace("draw", "sketch"))
  name.copyLineInfo(procname)
  sketchImpl(procname, name)



when isMainModule:
  type GearDesc* = object

  # todo: if defineSketch is a {.sketch.} pragma instead, something breaks in complex proc definitions, likely a Nim compiler bug
  
  expandMacros:
    proc draw*(g: GearDesc, sketch = doc, backLines = true) =
      discard "a"

    defineSketch draw

    proc draw*(g: GearDesc, sketch = doc, dimensions = doc, backLines = true) =
      discard "b"
    
    defineSketch draw, "sketch2"


