
type
  TerminalBackendStatus* = enum
    backendRunning
    backendFinished

  TerminalBackendObj* = object of RootObj
    outputChannel*: ptr Channel[string]
      ## everything the backend prints goes here, from any thread

  TerminalBackend* = ref TerminalBackendObj


method sendInput*(backend: TerminalBackend, s: string) {.base.} = discard
method resize*(backend: TerminalBackend, cols, rows: int) {.base.} = discard
method close*(backend: TerminalBackend) {.base.} = discard
method status*(backend: TerminalBackend): TerminalBackendStatus {.base.} = backendFinished
