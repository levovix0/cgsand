# ---------------- terminal backends ----------------
# A terminal backend is anything the terminal emulator is attached to:
# an external shell process, a compiler, or (in the future) a built-in shell.
# The backend sends what it wants to display to `outputChannel`
# (thread-safe, from any thread) and receives user input via `sendInput`.

import std/concurrency/[atomics]
import ./[backend]

when defined(linux):
  import std/[posix, os]

when defined(windows):
  import std/[strutils, dynlib]
  import std/[winlean, os]


type
  ExternalShellBackendObj* = object of TerminalBackendObj
    ## an external shell process attached to a virtual terminal:
    ## a pty on linux, ConPTY on windows
    m_status: Atomic[TerminalBackendStatus]
    m_readerThread: Thread[ShellReaderArgs]
    m_closed: bool
    when defined(linux):
      m_masterFd: cint
      m_pid: int
    when defined(windows):
      m_pty: Handle
      m_pipeIn: Handle   # we write the user's input here
      m_pipeOut: Handle  # we read the pty output here
      m_process: Handle

  ExternalShellBackend* = ref ExternalShellBackendObj

  ShellReaderArgs = object
    channel: ptr Channel[string]
    status: ptr Atomic[TerminalBackendStatus]
    when defined(linux):
      fd: cint  # pty master fd
      pid: int
    when defined(windows):
      pipeOut: Handle


when defined(linux):
  # pty support, imported from libc directly since std/posix does not export these
  const
    TIOCSCTTY = 0x540E
    # TIOCGWINSZ = 0x5413
    TIOCSWINSZ = 0x5414

  type WinSize = object
    row, col, xpixel, ypixel: cushort

  proc c_posix_openpt(flags: cint): cint {.importc: "posix_openpt", header: "<stdlib.h>".}
  proc c_grantpt(fd: cint): cint {.importc: "grantpt", header: "<stdlib.h>".}
  proc c_unlockpt(fd: cint): cint {.importc: "unlockpt", header: "<stdlib.h>".}
  proc c_ptsname(fd: cint): cstring {.importc: "ptsname", header: "<stdlib.h>".}
  proc c_putenv(s: cstring): cint {.importc: "putenv", header: "<stdlib.h>".}
  proc c_exit(status: cint) {.importc: "_exit", header: "<unistd.h>".}


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

    let term = getEnv("TERM")
    var termEnv: cstring = nil
    # the shell needs a real TERM, otherwise it degrades (fish skips its terminal handshake for dumb)
    if term.len == 0 or term == "dumb":
      termEnv = "TERM=xterm-256color"

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



when defined(windows):
  # ConPTY support, imported from kernel32 directly since std/winlean does not have it
  const
    ProcThreadAttributePseudoconsole = 0x00020016
    ExtendedStartupinfoPresent = 0x00080000
    StartfUseStdHandles = 0x00000100

  type
    WinCoord = object
      x, y: int16

    StartupInfoW = object
      cb: int32
      reserved, desktop, title: WideCString
      x, y, xSize, ySize, xCountChars, yCountChars, fillAttribute, flags: int32
      showWindow: int16
      cbReserved2: int16
      lpReserved2: pointer
      stdInput, stdOutput, stdError: Handle

    StartupInfoExW = object
      startupInfo: StartupInfoW
      attributeList: pointer

    ProcessInformationW = object
      process, thread: Handle
      pid: int32
      reserved: int32

  proc cCreatePipe(fdRead, fdWrite: var Handle, sa: pointer, size: int32): int32 {.stdcall, importc: "CreatePipe", header: "<windows.h>".}
  proc cReadFile(h: Handle, buf: pointer, size: int32, nRead: var int32, ov: pointer): int32 {.stdcall, importc: "ReadFile", header: "<windows.h>".}
  proc cWriteFile(h: Handle, buf: pointer, size: int32, nWritten: var int32, ov: pointer): int32 {.stdcall, importc: "WriteFile", header: "<windows.h>".}
  proc cCloseHandle(h: Handle): int32 {.stdcall, importc: "CloseHandle", header: "<windows.h>".}
  proc cTerminateProcess(h: Handle, code: int32): int32 {.stdcall, importc: "TerminateProcess", header: "<windows.h>".}
  # NOTE: the size parameter is SIZE_T (8 bytes on x64), it must not be int32
  proc cInitializeProcThreadAttributeList(buf: pointer, count, flags: int32, size: var int): int32 {.stdcall, importc: "InitializeProcThreadAttributeList", header: "<windows.h>".}
  proc cUpdateProcThreadAttribute(lst: pointer, flags, attr: int32, value: pointer, size: int, prev, retSize: pointer): int32 {.stdcall, importc: "UpdateProcThreadAttribute", header: "<windows.h>".}
  proc cDeleteProcThreadAttributeList(lst: pointer) {.stdcall, importc: "DeleteProcThreadAttributeList", header: "<windows.h>".}
  proc cCreateProcessW(app, cmd: WideCString, pa, ta: pointer, inherit, flags: int32, env, dir: pointer, si: pointer, pi: pointer): int32 {.stdcall, importc: "CreateProcessW", header: "<windows.h>".}

  type
    CreatePseudoConsoleProc = proc(size: WinCoord, hInput, hOutput: Handle, flags: int32, phPC: var Handle): int32 {.stdcall, gcsafe.}
    ResizePseudoConsoleProc = proc(hpc: Handle, size: WinCoord): int32 {.stdcall, gcsafe.}
    ClosePseudoConsoleProc = proc(hpc: Handle) {.stdcall, gcsafe.}
    ReleasePseudoConsoleProc = proc(hpc: Handle) {.stdcall, gcsafe.}

    ConptyApi* = object
      ## the pseudoconsole functions to use.
      ## Preferred source is the conpty.dll/OpenConsole.exe pair shipped with the app
      ## (the same binaries node-pty redistributes): the inbox conhost ConPTY is
      ## broken on some systems (child processes fail console init with 0xC0000142).
      ## Falls back to the kernel32 exports on systems where the dll is not present.
      lib: LibHandle  ## never unloaded: the pty state lives in this dll's heap
      createPseudoConsole: CreatePseudoConsoleProc
      resizePseudoConsole: ResizePseudoConsoleProc
      closePseudoConsole: ClosePseudoConsoleProc
      releasePseudoConsole: ReleasePseudoConsoleProc  # conpty.dll only, noop otherwise

  proc loadConptyApi(): ConptyApi =
    proc loadFrom(lib: LibHandle, names: tuple[create, resize, close, release: string]): ConptyApi =
      if lib != nil:
        let create = cast[CreatePseudoConsoleProc](symAddr(lib, names.create.cstring))
        let resize = cast[ResizePseudoConsoleProc](symAddr(lib, names.resize.cstring))
        let close = cast[ClosePseudoConsoleProc](symAddr(lib, names.close.cstring))
        if create != nil and resize != nil and close != nil:
          result.lib = lib
          result.createPseudoConsole = create
          result.resizePseudoConsole = resize
          result.closePseudoConsole = close
          let release = cast[ReleasePseudoConsoleProc](symAddr(lib, names.release.cstring))
          if release != nil:
            result.releasePseudoConsole = release
          else:
            result.releasePseudoConsole = proc(hpc: Handle) {.stdcall, gcsafe.} = discard

    # conpty.dll looks up OpenConsole.exe next to itself, both files must be shipped together
    let appDir = getAppDir()
    for dir in [appDir / "conpty", appDir.parentDir / "resources" / "conpty", appDir]:
      result = loadFrom(loadLib(dir / "conpty.dll"),
        ("ConptyCreatePseudoConsole", "ConptyResizePseudoConsole", "ConptyClosePseudoConsole", "ConptyReleasePseudoConsole"))
      if result.createPseudoConsole != nil:
        return

    # no bundled dll: use the inbox kernel32 implementation
    result = loadFrom(loadLib("kernel32.dll"),
      ("CreatePseudoConsole", "ResizePseudoConsole", "ClosePseudoConsole", ""))
    if result.createPseudoConsole == nil:
      raise newException(OSError, "CreatePseudoConsole is not available on this system")

  var conptyApi: ConptyApi  # loaded once on first use

  proc conpty(): ConptyApi =
    if conptyApi.createPseudoConsole == nil:
      conptyApi = loadConptyApi()
    conptyApi




  proc shellConPtyReader(args: ShellReaderArgs) {.thread.} =
    var buf: array[4096, char]
    while true:
      var n: int32 = 0
      if cReadFile(args.pipeOut, addr buf[0], buf.len.int32, n, nil) == 0 or n <= 0:
        break  # EOF once the pty is closed and the shell exits
      var chunk = newString(n.int)
      copyMem(chunk[0].addr, buf.addr, n.int)
      args.channel[].send(chunk)

    discard cCloseHandle(args.pipeOut)
    args.status[].store(backendFinished)


  proc spawnShellOnConPty(command: string, args: openArray[string]): tuple[pty, pipeIn, pipeOut, process: Handle] =
    ## starts `command` attached to a fresh ConPTY as its console
    let api = conpty()

    var inRead, inWrite, outRead, outWrite: Handle = 0
    if cCreatePipe(inRead, inWrite, nil, 0) == 0:
      raiseOSError(osLastError())
    if cCreatePipe(outRead, outWrite, nil, 0) == 0:
      let err = osLastError()
      discard cCloseHandle(inRead)
      discard cCloseHandle(inWrite)
      raiseOSError(err)

    var hPty: Handle = 0
    let hr = api.createPseudoConsole(WinCoord(x: 80, y: 24), inRead, outWrite, 0, hPty)
    # the pty holds its ends of both pipes now, ours can go
    discard cCloseHandle(inRead)
    discard cCloseHandle(outWrite)
    if hr != 0:
      raise newException(OSError, "CreatePseudoConsole failed with hresult " & $hr)

    var attrSize: int = 0
    discard cInitializeProcThreadAttributeList(nil, 1, 0, attrSize)
    var attrBuf = newSeq[byte](attrSize)
    if cInitializeProcThreadAttributeList(addr attrBuf[0], 1, 0, attrSize) == 0 or
        cUpdateProcThreadAttribute(
          addr attrBuf[0], 0, ProcThreadAttributePseudoconsole,
          # the kernel wants the HPCON value itself, not a pointer to it
          cast[pointer](hPty), sizeof(Handle), nil, nil,
        ) == 0:
      let err = osLastError()
      cDeleteProcThreadAttributeList(addr attrBuf[0])
      api.closePseudoConsole(hPty)
      raiseOSError(err)

    var si = StartupInfoExW(startupInfo: StartupInfoW(
      cb: int32 sizeof(StartupInfoExW),
      # the child must not touch our std handles, its console is the pty
      flags: StartfUseStdHandles,
    ))
    si.attributeList = addr attrBuf[0]
    var pi = ProcessInformationW()

    var cmdlineW = newWideCString(quoteShellCommand(@[command] & @args))
    if cCreateProcessW(nil, cmdlineW, nil, nil, 0, ExtendedStartupinfoPresent, nil, nil, addr si, addr pi) == 0:
      let err = osLastError()
      cDeleteProcThreadAttributeList(addr attrBuf[0])
      api.closePseudoConsole(hPty)
      raise newException(OSError, "failed to start shell: " & command & ", " & $err)

    cDeleteProcThreadAttributeList(addr attrBuf[0])
    discard cCloseHandle(pi.thread)
    # conpty.dll: drop the setup keep-alive so the pty ends with the shell
    api.releasePseudoConsole(hPty)
    result = (hPty, inWrite, outRead, pi.process)


proc shutdown(b: var ExternalShellBackendObj) {.raises: [].} =
  if b.m_closed: return
  b.m_closed = true

  when defined(linux):
    if b.m_masterFd >= 0:
      discard posix.kill(Pid(b.m_pid), SIGHUP)
      discard posix.close(b.m_masterFd)  # unblocks the reader thread
      b.m_masterFd = -1
  when defined(windows):
    if b.m_pipeIn != 0:
      discard cCloseHandle(b.m_pipeIn)
      b.m_pipeIn = 0
    if b.m_pty != 0:
      # closing the pty closes the console session (the shell sees its window closed)
      # and unblocks the reader thread
      try: conptyApi.closePseudoConsole(b.m_pty)
      except: discard
      b.m_pty = 0

  if b.m_readerThread.running:
    try: joinThread b.m_readerThread
    except: discard

  when defined(linux):
    if b.m_pid != 0:
      # make sure the shell did not survive the hangup
      discard posix.kill(Pid(b.m_pid), SIGKILL)
      var wstatus: cint
      discard posix.waitpid(Pid(b.m_pid), wstatus, 0)  # no zombie
      b.m_pid = 0
  when defined(windows):
    if b.m_process != 0:
      # make sure the shell did not survive the console close
      discard cTerminateProcess(b.m_process, 1)
      discard cCloseHandle(b.m_process)
      b.m_process = 0


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
  when defined(windows):
    var i = 0
    while i < s.len:
      var n: int32 = 0
      if cWriteFile(b.m_pipeIn, s[i].unsafeAddr, (s.len - i).int32, n, nil) == 0 or n <= 0:
        break
      inc i, n.int


method resize*(b: ExternalShellBackend, cols, rows: int) =
  when defined(linux):
    if b.m_masterFd >= 0:
      var ws = WinSize(row: rows.cushort, col: cols.cushort)
      discard ioctl(b.m_masterFd, TIOCSWINSZ, addr ws)
      # the kernel delivers SIGWINCH to the shell, it redraws its prompt
  when defined(windows):
    if b.m_pty != 0:
      discard conptyApi.resizePseudoConsole(b.m_pty, WinCoord(x: cols.int16, y: rows.int16))


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

  elif defined(windows):
    let shellArgs =
      if args.len > 0: @args
      elif "powershell" in command.toLowerAscii: @["-NoLogo"]
      else: @[]

    (result.m_pty, result.m_pipeIn, result.m_pipeOut, result.m_process) = spawnShellOnConPty(command, shellArgs)

    createThread(result.m_readerThread, shellConPtyReader, ShellReaderArgs(
      pipeOut: result.m_pipeOut,
      channel: outputChannel, status: result.m_status.addr,
    ))
