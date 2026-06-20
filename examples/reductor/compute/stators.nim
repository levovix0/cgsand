## stators - staticly dispatched and combinable iterators

type
  Stator* = concept var x
    get(x) is typed
    next(x) is bool

  HasRemaining* = concept var x
    remaining(x) is int

  SeqIter*[T] = object
    target*: ptr seq[T]
    i*: int = -1

  SeqReverseIter*[T] = object
    target*: ptr seq[T]
    i*: int
  
  StepIter*[T, St] = object
    inner*: St
    step*: Natural
  



template yieldType*[T](stator: SeqIter[T]): untyped = T

proc iter*[T](target {.byref.}: seq[T]): SeqIter[T] =
  result = SeqIter[T](target: target.addr, i: -1)

proc get*[T](stator: SeqIter[T]): T =
  stator.target[][stator.i]

proc next*[T](stator: var SeqIter[T]): bool =
  inc stator.i
  result = stator.i in 0..stator.target[].high

proc remaining*[T](stator: SeqIter[T]): int =
  stator.target[].len - stator.i - 1



template yieldType*[T](stator: SeqReverseIter[T]): untyped = T

proc reverseIter*[T](target {.byref.}: seq[T]): SeqReverseIter[T] =
  result = SeqReverseIter[T](target: target.addr, i: target.len)

proc get*[T](stator: SeqReverseIter[T]): T =
  stator.target[][stator.i]

proc next*[T](stator: var SeqReverseIter[T]): bool =
  dec stator.i
  result = stator.i in 0..stator.target[].high

proc remaining*[T](stator: SeqReverseIter[T]): int =
  stator.i



template yieldType*[T, St](stator: StepIter[T, St]): untyped = T

proc step*[St](inner: St, step: int): auto =
  result = StepIter[yieldType(inner), St](inner: inner, step: step.Natural)

proc get*[T, St](stator: var StepIter[T, St]): T =
  get(stator.inner)

proc next*[T, St](stator: var StepIter[T, St]): bool =
  for _ in 0..<stator.step:
    if not next(stator.inner): return false
  result = true

proc remaining*[T; St: HasRemaining](stator: var StepIter[T, St]): int =
  result = remaining(stator.inner) mod stator.step



proc skip*(stator: Stator, count: int): Stator =
  result = stator
  for _ in 0..<count:
    if not next(result): return

proc to*[St: Stator](stator: St, t: typedesc[seq]): auto =
  var stator = stator
  result = newSeq[yieldType(stator)]()

  when compiles(remaining(stator)):
    result.setLen remaining(stator)
    var i = 0
    while next(stator):
      result[i] = get(stator)
      inc i
  else:
    while next(stator):
      result.add get(stator)

iterator items*[St: Stator](stator: St): yieldType(default(St)) =
  var stator = stator
  while next(stator):
    yield get(stator)

proc filterStImpl[T; St: Stator](stator: St, filter: proc(x: T): bool): St =
  result = stator
  while next(result):
    if filter(get(result)):
      return

template filterSt*[St: Stator](stator: St, filter: untyped): St =
  bind filterStImpl
  filterStImpl[yieldType(stator), St](stator, filter)



template mapImpl[T; Rt; St: Stator](stator: St, applier: proc(x: T): Rt): untyped =
  type MapStator = object
    st: St

  template yieldType(stator: MapStator): untyped = Rt
  
  proc get(mst: var MapStator): T =
    applier(get(mst.st))

  proc next(mst: var MapStator): bool =
    next(mst.st)

  when compiles(remaining(stator)):
    proc remaining(mst: var MapStator): int =
      remaining(mst.st)

  MapStator(st: stator)

template map*[St: Stator](stator: St, applier: untyped): auto =
  bind mapImpl
  mapImpl[yieldType(stator), typeof(applier(default(yieldType(stator)))), St](stator, applier)

template mapIt*[St: Stator](stator: St, applier: untyped): auto =
  bind mapImpl
  proc applierF(it {.inject.}: yieldType(stator)): auto = applier
  mapImpl[yieldType(stator), typeof(applierF(default(yieldType(stator)))), St](stator, applierF)



when isMainModule:
  var a = @[0, 1, 2, 3, 4, 5]
  echo a.reverseIter.skip(1).step(2).skip(1).to(seq)
  echo a.iter.mapIt(it * 2).to(seq)
