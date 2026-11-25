## compiler diagnostics for the code editor: nimsuggest (persistent process,
## incremental checks) or nim check (one-shot run) execute in a background
## thread, and their output is parsed into editor diagnostics


import std/[os, osproc, streams, strutils, unicode, atomics, options]


type
  DiagnosticSeverity* = enum
    dsError
    dsWarning

  Diagnostic* = object
    file*: string     ## absolute path of the file the message belongs to
    line*: int        ## 0-based line index
    col*: int         ## 0-based UTF-8 byte offset where the underline starts
    severity*: DiagnosticSeverity
    message*: string


proc unescapeNimMessage(s: string): string =
  ## decodes the nimsuggest doc field escaping: \\ \' \" \t \r \n \xNN
  result = ""
  var i = 0
  while i < s.len:
    if s[i] == '\\' and i + 1 < s.len:
      if s[i + 1] == 'x' and i + 3 < s.len:
        try:
          result.add chr(parseHexInt(s[i + 2 .. i + 3]))
          i += 4
          continue
        except ValueError:
          discard
      case s[i + 1]
      of 't': result.add '\t'
      of 'r': result.add '\r'
      of 'n': result.add '\n'
      else: result.add s[i + 1]
      i += 2
    else:
      result.add s[i]
      i.inc


proc parseChkLine*(s: string): Option[Diagnostic] =
  ## parses one nimsuggest `chk` response line:
  ## chk \t skKind \t qualifiedPath \t severity \t filePath \t line \t col \t "doc" [\t quality]
  ## (line is 1-based, col is a 0-based UTF-8 byte offset).
  ## Hints and unrecognized lines (the help text, prompts) produce none.
  let parts = s.split('\t')
  if parts.len < 8 or parts[0] != "chk":
    return none(Diagnostic)

  var severity: DiagnosticSeverity
  case parts[3]
  of "Error": severity = dsError
  of "Warning": severity = dsWarning
  else: return none(Diagnostic)

  var line, col: int
  try:
    line = parseInt(parts[5]) - 1
    col = parseInt(parts[6])
  except ValueError:
    return none(Diagnostic)
  if line < 0:
    return none(Diagnostic)

  var doc = parts[7]
  if doc.len >= 2 and doc[0] == '"' and doc[^1] == '"':
    doc = doc[1 ..< doc.len - 1]

  return some(Diagnostic(
    file: parts[4].absolutePath(),
    line: line,
    col: col,
    severity: severity,
    message: doc.unescapeNimMessage(),
  ))


proc byteColToRuneCol*(runes: seq[Rune], byteOffset: int): int =
  ## converts a 0-based UTF-8 byte offset into a 0-based rune index
  var bytes = 0
  for i, r in runes:
    if bytes >= byteOffset: return i
    bytes += r.toUTF8().len
  return runes.len


proc isNimIdentRune(r: Rune): bool =
  let n = uint32(r)
  (n >= uint32('a') and n <= uint32('z')) or
  (n >= uint32('A') and n <= uint32('Z')) or
  (n >= uint32('0') and n <= uint32('9')) or
  n == uint32('_') or n == uint32('`') or n >= 0x80


proc diagnosticRange*(runes: seq[Rune], byteCol: int): Slice[int] =
  ## converts the reported byte column into a rune range covering the token
  ## starting there (the tools report only the start of the error);
  ## `range.b` is the exclusive end, like in the editor selections
  let first = byteColToRuneCol(runes, byteCol)
  if first >= runes.len:
    return 0 .. 0

  var i = first
  if runes[i] == Rune('"'):
    # a string literal — underline up to the closing quote
    i.inc
    while i < runes.len:
      if runes[i] == Rune('\\'):
        i += 2
      elif runes[i] == Rune('"'):
        i.inc
        break
      else:
        i.inc
    return first .. min(i, runes.len)

  while i < runes.len and isNimIdentRune(runes[i]): i.inc
  if i == first: i.inc  # always underline at least one rune
  return first .. min(i, runes.len)


# ----- nim check output parsing -----

type
  NimCheckParser* = object
    ## stateful parser of `nim check` output; messages can span several lines
    messages: seq[Diagnostic]
    current: Diagnostic
    hasCurrent: bool

proc parseNimCheckLine*(p: var NimCheckParser, line: string) =
  ## feeds one line of `nim check` output: "path(line, col) Severity: message"
  ## (line and col are 1-based; further lines continue the message)
  var pos = -1
  var keyword = ""
  var severity: DiagnosticSeverity = dsError
  var isHint = false
  for kw in ["Error: ", "Warning: ", "Fatal: ", "Hint: "]:
    let i = line.find(kw)
    if i >= 0 and (pos < 0 or i < pos):
      pos = i
      keyword = kw
      isHint = kw == "Hint: "
      severity = (if kw == "Warning: ": dsWarning else: dsError)

  if pos < 0 or isHint:
    # a continuation of the previous message (or hint output we don't show)
    if pos < 0 and p.hasCurrent:
      p.current.message.add "\n" & line
    return

  let head = line[0 ..< pos].strip()
  let lparen = head.rfind('(')
  if head.len == 0 or lparen < 0 or not head.endsWith(")"):
    if p.hasCurrent:
      p.current.message.add "\n" & line
    return

  let inner = head[lparen + 1 ..< head.len - 1]
  let nums = inner.split(',')
  var lineNo, colNo: int
  try:
    if nums.len == 1:
      lineNo = parseInt(nums[0].strip())
      colNo = 1
    elif nums.len == 2:
      lineNo = parseInt(nums[0].strip())
      colNo = parseInt(nums[1].strip())
    else:
      raise newException(ValueError, "")
  except ValueError:
    if p.hasCurrent:
      p.current.message.add "\n" & line
    return

  let path = head[0 ..< lparen].strip()
  if path.len == 0:
    if p.hasCurrent:
      p.current.message.add "\n" & line
    return

  if p.hasCurrent:
    p.messages.add p.current
  p.hasCurrent = true
  p.current = Diagnostic(
    file: path.absolutePath(),
    line: lineNo - 1,
    col: colNo - 1,  # nim check columns are 1-based
    severity: severity,
    message: line[pos + keyword.len ..< line.len],
  )


# ----- background run of nim check -----

type
  NimCheckRun* = ref object
    process: Process
    outputChannel: Channel[string]
    status: Atomic[int]        ## 0 = running, 1 = reader finished
    readerThread: Thread[NimCheckRun]
    parser: NimCheckParser     ## GUI thread only

proc nimCheckReader(r: NimCheckRun) {.thread.} =
  let stream = r.process.outputStream
  while true:
    try:
      r.outputChannel.send(stream.readLine())
    except CatchableError:
      break
  r.status.store(1, moRelease)


proc startNimCheck*(file: string): NimCheckRun =
  ## starts `nim check` on the file in a background thread.
  ## Returns nil when nim is not available.
  let exe = findExe("nim")
  if exe.len == 0: return nil

  let process = startProcess(
    quoteShell(exe) & " check --colors:off --hints:off " & quoteShell(file),
    options = {poUsePath, poStdErrToStdOut, poEvalCommand},
  )

  new result
  result.process = process
  result.outputChannel.open()
  result.status.store(0, moRelaxed)
  result.readerThread.createThread(nimCheckReader, result)


proc pollResults*(r: NimCheckRun): tuple[done: bool, results: seq[Diagnostic]] =
  ## drains the output; when the process has finished, returns all diagnostics
  ## found in its output
  while true:
    let (ok, received) = r.outputChannel.tryRecv()
    if not ok: break
    r.parser.parseNimCheckLine(received)

  if r.status.load(moAcquire) != 0:
    result.done = true
    if r.parser.hasCurrent:
      r.parser.messages.add r.parser.current
      r.parser.hasCurrent = false
    result.results = r.parser.messages
    r.parser = NimCheckParser()


proc stop*(r: NimCheckRun) =
  ## terminates the nim check process and frees its resources
  r.process.terminate()
  joinThread(r.readerThread)
  r.process.close()
  r.outputChannel.close()


# ----- persistent nimsuggest process -----

type
  NimsuggestClient* = ref object
    process: Process
    outputChannel: Channel[string]
    status: Atomic[int]        ## 0 = running, 1 = reader finished
    readerThread: Thread[NimsuggestClient]
    batch: seq[Diagnostic]     ## diagnostics of the response being received (GUI thread only)

proc nimsuggestReader(c: NimsuggestClient) {.thread.} =
  let stream = c.process.outputStream
  while true:
    try:
      c.outputChannel.send(stream.readLine())
    except CatchableError:
      break
  c.status.store(1, moRelease)


proc newNimsuggestClient*(projectFile: string): NimsuggestClient =
  ## spawns `nimsuggest --stdin` with the given file as the project.
  ## Returns nil when nimsuggest is not available.
  let exe = findExe("nimsuggest")
  if exe.len == 0: return nil

  let process = startProcess(
    quoteShell(exe) & " --stdin " & quoteShell(projectFile),
    options = {poUsePath, poStdErrToStdOut, poEvalCommand},
  )

  new result
  result.process = process
  result.outputChannel.open()
  result.status.store(0, moRelaxed)
  result.readerThread.createThread(nimsuggestReader, result)


proc finished*(c: NimsuggestClient): bool =
  ## the nimsuggest process has exited
  c.status.load(moAcquire) != 0


proc requestCheck*(c: NimsuggestClient, file: string) =
  ## asks nimsuggest to check the file; the results arrive through pollResults
  if c.finished(): return
  try:
    c.process.inputStream.write("chk " & file & "\n")
    c.process.inputStream.flush()
  except CatchableError:
    discard


proc pollResults*(c: NimsuggestClient): tuple[done: bool, results: seq[Diagnostic]] =
  ## drains the nimsuggest output; returns the collected diagnostics when the
  ## response batch is complete (an empty line ends it) or the process died
  var receivedAny = false
  while true:
    let (ok, received) = c.outputChannel.tryRecv()
    if not ok: break
    receivedAny = true

    if received.len == 0:
      result.done = true
      result.results = c.batch
      c.batch = @[]
    else:
      let d = parseChkLine(received)
      if d.isSome:
        c.batch.add d.get

  if not result.done and receivedAny and c.finished():
    # the process ended in the middle of a response — drop the partial batch
    c.batch = @[]
    result.done = true


proc stop*(c: NimsuggestClient) =
  ## terminates nimsuggest and frees its resources
  try:
    if not c.finished():
      c.process.inputStream.write("quit\n")
      c.process.inputStream.flush()
  except CatchableError:
    discard
  c.process.terminate()
  joinThread(c.readerThread)
  c.process.close()
  c.outputChannel.close()
