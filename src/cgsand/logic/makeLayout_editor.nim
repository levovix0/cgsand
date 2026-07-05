import std/[sets]
import pkg/[vmath, chroma, ecs]
import pkg/sigeo/macros/[interfaces, cursors]
import sandbox
import ../logic/[config]


makeInterface Insertable:
  proc toInsertableCode(this;): string
  # proc `==`(this, other;)  # todo


type
  Insertion* = object
    at*: int
    size*: int
    value*: OwnedInsertable


  MleNode* = ref object of RootObj

  MleComponent* = ref object of MleNode
    code*: string
    insertions*: seq[Insertion]

  MleEntity* = ref object of MleNode
    childs*: seq[MleNode]

  
  ComponentLibrary* = ref object




proc toInsertableCode*(p: Point2): string = "p2" & $p

Insertable.implementInterfaceFor(Point2)
converter asOwnedInsertable*(p: Point2): OwnedInsertable = p.toOwnedInsertable
  ## todo: autogenerate


proc replaceCode(this: MleComponent, at: int, size: int, newText: string) =
  ## Replaces a substring in code and updates Insertable positions accordingly.
  ## `at` is the start position, `size` is the length of the region being replaced.
  let before = this.code[0 ..< at]
  let after = this.code[min(at + size, this.code.high) .. ^1]
  let diff = newText.len - size
  this.code = before & newText & after
  for i in 0 ..< this.insertions.len:
    letCur ins: this.insertions[i]
    if ins.at == at and ins.size == size:
      ins.size = newText.len
    elif ins.at >= cast[int](at) + size:
      ins.at += diff


proc replaceInsertion*[T: Insertable](this: MleComponent, insI: int, v: T) =
  let ins = this.insertions[insI]
  let newCode = v.toInsertableCode()
  this.replaceCode(ins.at, ins.size, newCode)
  this.insertions[insI].size = newCode.len





when isMainModule:
  import unittest

  var n = MleNode MleEntity(
    childs: @[
      MleNode MleComponent(
        code: "line(p2(0, 0), p2(1, 1))",
        insertions: @[
          Insertion(value: p2(0, 0), at: 5, size: 8),
          Insertion(value: p2(1, 1), at: 15, size: 8),
        ]
      ),
    ]
  )

  let c1 = n.MleEntity.childs[0].MleComponent
  c1.replaceCode(c1.insertions[0].at, c1.insertions[0].size, "p2(0, 0.5)")
  check c1.code == "line(p2(0, 0.5), p2(1, 1))"
  check (c1.insertions[0].at == 5) and (c1.insertions[0].size == 10)
  check (c1.insertions[1].at == 17) and (c1.insertions[1].size == 8)
  # check (c1.insertions[0]) == Insertion(at: 5, size: 10, value: p2(1, 1))
  # check (c1.insertions[1]) == Insertion(at: 17, size: 8, value: p2(1, 1))
  
  c1.replaceCode(c1.insertions[1].at, c1.insertions[1].size, "p2(0, 0.5)")
  check c1.code == "line(p2(0, 0.5), p2(0, 0.5))"
  check (c1.insertions[0].at == 5) and (c1.insertions[0].size == 10)
  check (c1.insertions[1].at == 17) and (c1.insertions[1].size == 10)
  # check (c1.insertions[0]) == Insertion(at: 5, size: 10, value: p2(0, 0))
  # check (c1.insertions[1]) == Insertion(at: 17, size: 10, value: p2(1, 1))

