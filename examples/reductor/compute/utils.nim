import math, macros
import tabledef
export tabledef


proc degToRad*(deg: float): float =
  deg / 180 * Pi


macro dump*(x: untyped): untyped =
  result = nnkBlockStmt.newTree(
    newEmptyNode(),
    nnkStmtList.newTree(
      nnkPragma.newTree(
        nnkExprColonExpr.newTree(
          newIdentNode("warning"),
          (
            if x.kind in {nnkIdent, nnkSym}:
              nnkInfix.newTree(
                newIdentNode("&"),
                newLit(x.repr & " = "),
                nnkPrefix.newTree(
                  newIdentNode("$"),
                  x
                )
              )
            else:
              nnkPrefix.newTree(
                newIdentNode("$"),
                x
              )
          )
        )
      ),
      (
        if x.kind in {nnkIdent, nnkSym}:
          newEmptyNode()
        else:
          x
      )
    )
  )


