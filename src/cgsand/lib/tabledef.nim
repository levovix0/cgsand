import math, macros


proc splitInfix(n: NimNode): tuple[items: seq[NimNode], infix: NimNode] =
  if n.kind != nnkInfix: return
  result.infix = n[0]
  var n = n
  while n.kind == nnkInfix and n.len == 3 and n[0] == result.infix:
    result.items.insert n[2]
    n = n[1]
  result.items.insert n


macro columnTable*(prefix, typ, body) =
  result = newStmtList()

  let typ = if typ.kind == nnkAccQuoted and typ.len == 1: typ[0] else: typ

  var header: seq[NimNode]
  var headerVal: seq[NimNode]
  for head in body[0].splitInfix.items:
    let name = ident(prefix.strVal & "_" & head.strVal)
    name.copyLineInfo(head)
    header.add name
    headerVal.add nnkBracket.newTree()
  
  for row in body[1..^1]:
    var i = 0
    for val in row.splitInfix.items:
      if not val.eqIdent("_"):
        headerVal[i].add val
      inc i

  let sec =
    if typ.strVal in ["letSection", "let"]: nnkLetSection
    elif typ.strVal in ["varSection", "var"]: nnkVarSection
    elif typ.strVal in ["constSection", "const"]: nnkConstSection
    else: error("expected letSection|varSection|constSection", typ)
  let defs =
    if typ.strVal in ["letSection", "let"]: nnkIdentDefs
    elif typ.strVal in ["varSection", "var"]: nnkIdentDefs
    elif typ.strVal in ["constSection", "const"]: nnkConstDef
    else: error("expected letSection|varSection|constSection", typ)

  for i, name in header:
    result.add sec.newTree(defs.newTree(name, newEmptyNode(), headerVal[i]))




when isMainModule:
  columnTable example, `const`:
    x1 | x2 | x1_xor_x2
    0  | 0  | 0
    0  | 1  | 1
    1  | 0  | 1
    1  | 1  | 0
  
  for i in 0 ..< example_x1.len:
    echo example_x1[i], " XOR ", example_x2[i], " = ", example_x1_xor_x2[i]

