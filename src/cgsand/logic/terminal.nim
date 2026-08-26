import std/[unicode, terminal, strutils, os, osproc]
import std/concurrency/atomics
import pkg/[vmath, chroma]
when defined(linux):
  import std/posix

const
  ColorDimBlack*      = parseHtmlHex("#202223")
  ColorDimRed        = parseHtmlHex("#ED1515")
  ColorDimGreen      = parseHtmlHex("#11D116")
  ColorDimYellow     = parseHtmlHex("#F67400")
  ColorDimBlue       = parseHtmlHex("#1D99F3")
  ColorDimMagenta    = parseHtmlHex("#9B59B6")
  ColorDimCyan       = parseHtmlHex("#1ABC9C")
  ColorDimWhite      = parseHtmlHex("#FCFCFC")
  
  ColorBrightBlack   = parseHtmlHex("#7F8C8D")
  ColorBrightRed     = parseHtmlHex("#C0392B")
  ColorBrightGreen   = parseHtmlHex("#1CDC9A")
  ColorBrightYellow  = parseHtmlHex("#FDBC4B")
  ColorBrightBlue    = parseHtmlHex("#3DAEE9")
  ColorBrightMagenta = parseHtmlHex("#D87DFF")
  ColorBrightCyan    = parseHtmlHex("#19B898")
  ColorBrightWhite   = parseHtmlHex("#FFFFFF")

  AnsiDimColors* = [
    ColorDimBlack, ColorDimRed, ColorDimGreen, ColorDimYellow,
    ColorDimBlue, ColorDimMagenta, ColorDimCyan, ColorDimWhite,
  ]

  AnsiBrightColors* = [
    ColorBrightBlack, ColorBrightRed, ColorBrightGreen, ColorBrightYellow,
    ColorBrightBlue, ColorBrightMagenta, ColorBrightCyan, ColorBrightWhite,
  ]


type
  TerminalCursor* = IVec2

  CellFlags = object
    style*: set[Style]
    fg*: Color = ColorDimWhite
    bg*: Color = ColorDimBlack

  TerminalCell* = object
    rune*: Rune = " ".runeAt(0)
    flags*: CellFlags

  TerminalArrangement* = ref object
    size*: IVec2
    data*: seq[TerminalCell]  # y * size.x + x  ->  character at row y, col x
    cursor*: TerminalCursor
    cursorFlags*: CellFlags
    cursorVisible*: bool = true

    savedCursor*: TerminalCursor
    savedCursorFlags*: CellFlags


const MaxTerminalSize = ivec2(10000)  # in characters
const TabWidth = 8



proc `[]`*(this: TerminalArrangement, pos: IVec2): var TerminalCell =
  this.data[pos.y * this.size.x + pos.x]

proc `[]`*(this: TerminalArrangement, x, y: int): var TerminalCell =
  this.data[y * this.size.x + x]


proc `[]=`*(this: TerminalArrangement, pos: IVec2, v: TerminalCell) =
  (this[pos]) = v

proc `[]=`*(this: TerminalArrangement, x, y: int, v: TerminalCell) =
  (this[x, y]) = v


proc clear*(this: TerminalArrangement, to = TerminalCell()) =
  for x in this.data.mitems: x = to

proc resize*(this: TerminalArrangement, v: IVec2) =
  let v = ivec2(v.x.clamp(1, MaxTerminalSize.x), v.y.clamp(1, MaxTerminalSize.y))

  let prevData = move this.data
  this.data = newSeqUninit[TerminalCell](v.x * v.y)
  clear this

  for y in 0..<min(this.size.y, v.y):
    for x in 0..<min(this.size.x, v.x):
      this.data[y * v.x + x] = prevData[y * this.size.x + x]

  this.size = v
  this.cursor = ivec2(this.cursor.x.clamp(0, this.size.x - 1), this.cursor.y.clamp(0, this.size.y - 1))


proc newTerminalArrangement*(size = ivec2(80, 24)): TerminalArrangement =
  new result
  result.resize size


proc scrollDown*(this: TerminalArrangement, ammount = 1) =
  if ammount >= this.size.y:
    clear this
    return
  
  moveMem(this.data[0].addr, this.data[ammount * this.size.x].addr, sizeof(TerminalCell) * (this.size.y - ammount) * this.size.x)
  for i in ((this.size.y - ammount) * this.size.x)..<(this.size.y * this.size.x):
    this.data[i] = TerminalCell()


proc scrollUp*(this: TerminalArrangement, ammount = 1) =
  if ammount >= this.size.y:
    clear this
    return

  moveMem(
    addr this.data[ammount * this.size.x],
    addr this.data[0],
    sizeof(TerminalCell) * (this.size.y - ammount) * this.size.x,
  )
  for i in 0 ..< ammount * this.size.x:
    this.data[i] = TerminalCell()


proc clampCursor*(this: TerminalArrangement) =
  this.cursor = ivec2(
    this.cursor.x.clamp(0, this.size.x - 1),
    this.cursor.y.clamp(0, this.size.y - 1),
  )


proc incCursorPos*(this: TerminalArrangement) =
  inc this.cursor.x

  if this.cursor.x >= this.size.x:
    this.cursor.x = 0
    inc this.cursor.y

  if this.cursor.y >= this.size.y:
    this.scrollDown(this.size.y - this.cursor.y + 1)
    this.cursor.y = this.size.y - 1


proc newline*(this: TerminalArrangement) =
  inc this.cursor.y
  if this.cursor.y >= this.size.y:
    this.scrollDown(this.cursor.y - this.size.y + 1)
    this.cursor.y = this.size.y - 1


proc ansiColor256(n: int): Color =
  ## xterm 256-color palette
  if n < 0 or n > 255: ColorDimWhite
  elif n < 8: AnsiDimColors[n]
  elif n < 16: AnsiBrightColors[n - 8]
  elif n < 232:
    const CubeLevels = [0'f32, 95, 135, 175, 215, 255]
    let i = n - 16
    color(
      CubeLevels[i div 36] / 255,
      CubeLevels[i div 6 mod 6] / 255,
      CubeLevels[i mod 6] / 255,
    )
  else:
    let v = (8 + 10 * (n - 232)).float32 / 255
    color(v, v, v)


proc sgrRgbColor(r, g, b: int): Color =
  color(
    r.clamp(0, 255).float32 / 255,
    g.clamp(0, 255).float32 / 255,
    b.clamp(0, 255).float32 / 255,
  )


proc parseSgrParams(s: string, first, last: int): seq[int] =
  ## [first, last) split on ';' (':' subparameters treated the same), missing/invalid -> 0
  var cur = ""
  for i in first ..< last:
    if s[i] in {';', ':'}:
      result.add (try: parseInt(cur) except: 0)
      cur.setLen 0
    else:
      cur.add s[i]
  result.add (try: parseInt(cur) except: 0)


proc applySgr(this: TerminalArrangement, params: openArray[int]) =
  var i = 0
  while i < params.len:
    let p = params[i]

    case p
    of 0: this.cursorFlags = CellFlags()
    of 1: this.cursorFlags.style.incl styleBright
    of 2: this.cursorFlags.style.incl styleDim
    of 3: this.cursorFlags.style.incl styleItalic
    of 4: this.cursorFlags.style.incl styleUnderscore
    of 5: this.cursorFlags.style.incl styleBlink
    of 6: this.cursorFlags.style.incl styleBlinkRapid
    of 7: this.cursorFlags.style.incl styleReverse
    of 8: this.cursorFlags.style.incl styleHidden
    of 9: this.cursorFlags.style.incl styleStrikethrough

    of 21: discard  # doubly underscored, there is no such style yet
    of 22: this.cursorFlags.style.excl {styleBright, styleDim}
    of 23: this.cursorFlags.style.excl styleItalic
    of 24: this.cursorFlags.style.excl styleUnderscore
    of 25: this.cursorFlags.style.excl {styleBlink, styleBlinkRapid}
    of 27: this.cursorFlags.style.excl styleReverse
    of 28: this.cursorFlags.style.excl styleHidden
    of 29: this.cursorFlags.style.excl styleStrikethrough

    of 30..37: this.cursorFlags.fg = AnsiDimColors[p - 30]
    of 38, 48:
      # 38/48;5;n -> 256-color, 38/48;2;r;g;b -> rgb
      if i + 2 < params.len and params[i + 1] == 5:
        let c = ansiColor256(params[i + 2])
        if p == 38: this.cursorFlags.fg = c
        else: this.cursorFlags.bg = c
        inc i, 2
      elif i + 4 < params.len and params[i + 1] == 2:
        let c = sgrRgbColor(params[i + 2], params[i + 3], params[i + 4])
        if p == 38: this.cursorFlags.fg = c
        else: this.cursorFlags.bg = c
        inc i, 4
    of 39: this.cursorFlags.fg = ColorDimWhite
    of 40..47: this.cursorFlags.bg = AnsiDimColors[p - 40]
    of 49: this.cursorFlags.bg = ColorDimBlack
    of 90..97: this.cursorFlags.fg = AnsiBrightColors[p - 90]
    of 100..107: this.cursorFlags.bg = AnsiBrightColors[p - 100]
    else: discard

    inc i


proc erasedCell(this: TerminalArrangement): TerminalCell =
  ## erasing fills with the current background (background color erase)
  TerminalCell(rune: " ".runeAt(0), flags: CellFlags(fg: ColorDimWhite, bg: this.cursorFlags.bg))


proc eraseInLine*(this: TerminalArrangement, mode: int) =
  case mode
  of 0:  # cursor to end of line
    for x in this.cursor.x.min(this.size.x - 1) ..< this.size.x:
      this[x, this.cursor.y] = this.erasedCell()
  of 1:  # start of line to cursor
    for x in 0 .. this.cursor.x.min(this.size.x - 1):
      this[x, this.cursor.y] = this.erasedCell()
  of 2:  # whole line
    for x in 0 ..< this.size.x:
      this[x, this.cursor.y] = this.erasedCell()
  else: discard


proc eraseInDisplay*(this: TerminalArrangement, mode: int) =
  template clearRows(a, b: int) =
    for y in a ..< b:
      for x in 0 ..< this.size.x:
        this[x, y] = this.erasedCell()

  case mode
  of 0:  # cursor to end of screen
    this.eraseInLine(0)
    clearRows(this.cursor.y + 1, this.size.y)
  of 1:  # start of screen to cursor
    this.eraseInLine(1)
    clearRows(0, this.cursor.y)
  of 2, 3:  # whole screen
    clearRows(0, this.size.y)
  else: discard


proc applyCsi(this: TerminalArrangement, paramsStr: string, final: char) =
  let private = paramsStr.len > 0 and paramsStr[0] == '?'
  # an empty parameter list means 0 (so a bare "CSI m" is a reset)
  let params = parseSgrParams(paramsStr, if private: 1 else: 0, paramsStr.len)

  template n(idx, def: int): int =
    if params.len > idx and params[idx] > 0: params[idx] else: def

  template m(idx: int): int =
    if params.len > idx: params[idx] else: 0

  if private:
    case final
    of 'h', 'l':
      if m(0) == 25: this.cursorVisible = final == 'h'
      # 2004 bracketed paste, 1000..1006 mouse reporting, ...: ignored
    else: discard
    return

  case final
  of 'A': this.cursor.y = max(this.cursor.y.int - n(0, 1), 0).int32
  of 'B': this.cursor.y = min(this.cursor.y.int + n(0, 1), this.size.y - 1).int32
  of 'C': this.cursor.x = min(this.cursor.x.int + n(0, 1), this.size.x - 1).int32
  of 'D': this.cursor.x = max(this.cursor.x.int - n(0, 1), 0).int32
  of 'E':
    this.cursor.x = 0
    this.cursor.y = min(this.cursor.y.int + n(0, 1), this.size.y - 1).int32
  of 'F':
    this.cursor.x = 0
    this.cursor.y = max(this.cursor.y.int - n(0, 1), 0).int32
  of 'G': this.cursor.x = (n(0, 1) - 1).clamp(0, this.size.x - 1).int32
  of 'H', 'f':
    this.cursor.y = (n(0, 1) - 1).clamp(0, this.size.y - 1).int32
    this.cursor.x = (n(1, 1) - 1).clamp(0, this.size.x - 1).int32
  of 'd': this.cursor.y = (n(0, 1) - 1).clamp(0, this.size.y - 1).int32
  of 'J': this.eraseInDisplay(m(0))
  of 'K': this.eraseInLine(m(0))
  of 'S': this.scrollDown(n(0, 1))
  of 'T': this.scrollUp(n(0, 1))
  of 'm': this.applySgr(params)
  of 's':
    this.savedCursor = this.cursor
    this.savedCursorFlags = this.cursorFlags
  of 'u':
    this.cursor = this.savedCursor
    this.clampCursor()
    this.cursorFlags = this.savedCursorFlags
  else: discard  # unsupported sequences are ignored


proc handleInput*(this: TerminalArrangement, s: string, i: var int) =
  ## Consumes as much of `s` starting at ``i`` as possible.
  ## `i` is advanced past everything consumed.
  ## if `s` ends in the middle of an escape sequence or a rune, ``i`` is left at its start,
  ## so the caller can prepend the unconsumed tail to the next chunk.
  while i < s.len:
    if s[i] == '\27':
      if i + 1 >= s.len: return

      case s[i + 1]
      of '[':
        # CSI: parameter bytes (0x30..0x3F), optional intermediate bytes (0x20..0x2F), final byte (0x40..0x7E)
        var j = i + 2
        while j < s.len and s[j].byte in 0x30'u8..0x3F'u8: inc j
        let paramsEnd = j
        while j < s.len and s[j].byte in 0x20'u8..0x2F'u8: inc j
        if j >= s.len: return

        if s[j].byte in 0x40'u8..0x7E'u8:
          this.applyCsi(s[i + 2 ..< paramsEnd], s[j])
          i = j + 1
        else:
          inc i  # malformed, drop just the escape byte

      of ']', 'P', 'X', '^', '_':
        # OSC / DCS / SOS / PM / APC, terminated by BEL or ESC \
        var j = i + 2
        while true:
          if j >= s.len: return
          if s[j] == '\7':
            inc j
            break
          if s[j] == '\27':
            if j + 1 >= s.len: return
            inc j, 2
            break
          inc j
        i = j

      of '(', ')', '#', '%':
        # charset selection: ESC ( <char>
        if i + 2 >= s.len: return
        inc i, 3

      of '7':  # DECSC save cursor
        this.savedCursor = this.cursor
        this.savedCursorFlags = this.cursorFlags
        inc i, 2

      of '8':  # DECRC restore cursor
        this.cursor = this.savedCursor
        this.clampCursor()
        this.cursorFlags = this.savedCursorFlags
        inc i, 2

      else:
        inc i, 2

    elif s[i] < ' ' or s[i] == '\127':
      case s[i]
      of '\l':
        this.cursor.x = 0
        this.newline()
      of '\c': this.cursor.x = 0
      of '\t': this.cursor.x = min(this.cursor.x + (TabWidth - this.cursor.x mod TabWidth), this.size.x - 1)
      of '\8': this.cursor.x = max(this.cursor.x - 1, 0)
      else: discard  # bell and other control chars
      inc i

    else:
      let rl = s.runeLenAt(i)
      if i + rl > s.len: return  # truncated rune

      if this.cursor.x >= this.size.x:
        # deferred wrap: the line exactly filled the last column
        this.cursor.x = 0
        this.newline()

      this[this.cursor] = TerminalCell(rune: s.runeAt(i), flags: this.cursorFlags)
      inc this.cursor.x  # may reach size.x, wrapped lazily by the next rune
      i += rl




# ] ---------------- terminal backends ---------------- [
# A terminal backend is anything the terminal emulator is attached to:
# an external shell process, a compiler, or (in the future) a built-in shell.
# The backend sends what it wants to display to `outputChannel`
# (thread-safe, from any thread) and receives user input via `sendInput`.


when defined(linux):
  # pty support, imported from libc directly since std/posix does not export these
  const
    TIOCSCTTY = 0x540E
    TIOCSWINSZ = 0x5413

  type WinSize = object
    row, col, xpixel, ypixel: cushort

  proc c_posix_openpt(flags: cint): cint {.importc: "posix_openpt", header: "<stdlib.h>".}
  proc c_grantpt(fd: cint): cint {.importc: "grantpt", header: "<stdlib.h>".}
  proc c_unlockpt(fd: cint): cint {.importc: "unlockpt", header: "<stdlib.h>".}
  proc c_ptsname(fd: cint): cstring {.importc: "ptsname", header: "<stdlib.h>".}
  proc c_putenv(s: cstring): cint {.importc: "putenv", header: "<stdlib.h>".}
  proc c_exit(status: cint) {.importc: "_exit", header: "<unistd.h>".}


type
  TerminalBackendStatus* = enum
    backendRunning
    backendFinished

  TerminalBackendObj* = object of RootObj
    outputChannel*: ptr Channel[string]
      ## everything the backend prints goes here, from any thread

  TerminalBackend* = ref TerminalBackendObj

  ExternalShellBackendObj* = object of TerminalBackendObj
    ## an external shell process attached to a virtual terminal:
    ## a pty on linux, plain pipes on windows (todo: ConPTY)
    m_status: Atomic[TerminalBackendStatus]
    m_readerThread: Thread[ShellReaderArgs]
    m_closed: bool
    when defined(linux):
      m_masterFd: cint
      m_pid: int
    else:
      m_process: Process

  ExternalShellBackend* = ref ExternalShellBackendObj

  ShellReaderArgs = object
    fd: cint  # linux: pty master fd
    pid: int  # linux
    process: Process  # non-linux
    channel: ptr Channel[string]
    status: ptr Atomic[TerminalBackendStatus]


method sendInput*(backend: TerminalBackend, s: string) {.base.} = discard
method resize*(backend: TerminalBackend, cols, rows: int) {.base.} = discard
method close*(backend: TerminalBackend) {.base.} = discard
method status*(backend: TerminalBackend): TerminalBackendStatus {.base.} = backendFinished


when defined(linux):
  proc shellPtyReader(args: ShellReaderArgs) {.thread.} =
    var buf: array[4096, char]
    while true:
      let n = posix.read(args.fd, addr buf[0], buf.len.cint)
      if n <= 0: break  # EOF or EIO once the shell exits and the pty is closed
      var chunk = newString(n.int)
      copyMem(chunk[0].addr, buf.addr, n.int)
      args.channel[].send(chunk)

    discard posix.close(args.fd)
    args.status[].store(backendFinished)


  proc spawnShellOnPty(command: string, args: openArray[string]): tuple[masterFd: cint, pid: int] =
    ## forks a new session running `command` with the slave side of a fresh pty
    ## as its controlling terminal and as stdin/stdout/stderr
    let masterFd = c_posix_openpt(O_RDWR or O_NOCTTY)
    if masterFd < 0: raiseOSError(errno.OSErrorCode)
    if c_grantpt(masterFd) != 0 or c_unlockpt(masterFd) != 0:
      let err = errno.OSErrorCode
      discard posix.close(masterFd)
      raiseOSError(err)

    let slaveName = $c_ptsname(masterFd)

    let path =
      if '/' in command: command
      else:
        let found = findExe(command)
        if found.len == 0:
          raise newException(OSError, "shell not found: " & command)
        found

    var argv = allocCStringArray(@[path] & @args)
    defer: deallocCStringArray(argv)

    let needTerm = getEnv("TERM").len == 0
    var termEnv: cstring = nil
    if needTerm: termEnv = "TERM=xterm-256color"

    let pid = fork()
    if pid < 0:
      let err = errno.OSErrorCode
      discard posix.close(masterFd)
      raiseOSError(err)

    if pid == 0:
      # child, only async-signal-safe calls until exec
      discard setsid()
      let slaveFd = open(cstring(slaveName), O_RDWR)
      if slaveFd < 0: c_exit(126)
      discard ioctl(slaveFd, TIOCSCTTY, 0)
      discard dup2(slaveFd, 0)
      discard dup2(slaveFd, 1)
      discard dup2(slaveFd, 2)
      if slaveFd > 2: discard posix.close(slaveFd)
      discard posix.close(masterFd)
      if termEnv != nil: discard c_putenv(termEnv)
      discard execv(cstring(path), argv)
      discard write(2, cstring("cgsand: failed to start shell: "), 31)
      discard write(2, path.cstring, path.len.cint)
      discard write(2, cstring("\n"), 1)
      c_exit(127)

    result = (masterFd, pid.int)


else:
  proc shellPipeReader(args: ShellReaderArgs) {.thread.} =
    let stream = args.process.outputStream
    var buf = ""
    try:
      while not stream.atEnd:
        buf.add stream.readChar()
        if buf.len >= 4096:
          args.channel[].send(buf)
          buf = ""
    except CatchableError: discard
    if buf.len > 0: args.channel[].send(buf)
    discard args.process.waitForExit()
    args.status[].store(backendFinished)


proc shutdown(b: var ExternalShellBackendObj) =
  if b.m_closed: return
  b.m_closed = true

  when defined(linux):
    if b.m_masterFd >= 0:
      discard posix.kill(Pid(b.m_pid), SIGHUP)
      discard posix.close(b.m_masterFd)  # unblocks the reader thread
      b.m_masterFd = -1
  else:
    try: b.m_process.kill()
    except CatchableError: discard

  if b.m_readerThread.running:
    joinThread b.m_readerThread

  when defined(linux):
    if b.m_pid != 0:
      # make sure the shell did not survive the hangup
      discard posix.kill(Pid(b.m_pid), SIGKILL)
      var wstatus: cint
      discard posix.waitpid(Pid(b.m_pid), wstatus, 0)  # no zombie
      b.m_pid = 0


proc `=destroy`(b: var ExternalShellBackendObj) =
  shutdown b


method sendInput*(b: ExternalShellBackend, s: string) =
  if s.len == 0 or b.m_status.load != backendRunning: return

  when defined(linux):
    var i = 0
    while i < s.len:
      let n = posix.write(b.m_masterFd, s[i].unsafeAddr, (s.len - i).cint)
      if n <= 0: break  # the shell is gone, drop the input
      inc i, n.int
  else:
    try:
      b.m_process.inputStream.write(s)
      b.m_process.inputStream.flush()
    except CatchableError: discard


method resize*(b: ExternalShellBackend, cols, rows: int) =
  when defined(linux):
    if b.m_masterFd >= 0:
      var ws = WinSize(row: rows.cushort, col: cols.cushort)
      discard ioctl(b.m_masterFd, TIOCSWINSZ, addr ws)
      # the kernel delivers SIGWINCH to the shell, it redraws its prompt


method close*(b: ExternalShellBackend) =
  shutdown b[]


method status*(b: ExternalShellBackend): TerminalBackendStatus = b.m_status.load


proc newExternalShellBackend*(
  outputChannel: ptr Channel[string], command: string, args: openArray[string] = [],
): ExternalShellBackend =
  ## runs `command` as a terminal backend.
  ## Its output is sent to `outputChannel` from a background thread,
  ## user input is forwarded to the process with `sendInput`.
  new result
  result.outputChannel = outputChannel
  result.m_status.store(backendRunning)

  when defined(linux):
    (result.m_masterFd, result.m_pid) = spawnShellOnPty(command, args)

    var ws = WinSize(row: 24, col: 80)
    discard ioctl(result.m_masterFd, TIOCSWINSZ, addr ws)

    createThread(result.m_readerThread, shellPtyReader, ShellReaderArgs(
      fd: result.m_masterFd, pid: result.m_pid,
      channel: outputChannel, status: result.m_status.addr,
    ))

  else:
    # todo: use ConPTY so the shell behaves fully interactive
    let startArgs =
      if "powershell" in command.toLowerAscii: @args & @["-NoLogo", "-NoExit", "-Command", "-"]
      else: @args

    result.m_process = startProcess(command, args = startArgs, options = {poUsePath, poStdErrToStdOut})

    createThread(result.m_readerThread, shellPipeReader, ShellReaderArgs(
      process: result.m_process,
      channel: outputChannel, status: result.m_status.addr,
    ))
