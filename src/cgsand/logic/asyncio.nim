

type SaveMsg = tuple[filename, content: string]

var gSaveChannel: Channel[SaveMsg]
var gSaveThread: Thread[void]
var gSaveInited = false

proc saveWorker() {.thread.} =
  while true:
    var msg = gSaveChannel.recv()      # block until first request
    while true:                         # drain – keep only the latest
      let (ok, newer) = gSaveChannel.tryRecv()
      if not ok: break
      msg = newer
    try: writeFile(msg.filename, msg.content)
    except: discard

proc initSaveThread() =
  if gSaveInited: return
  gSaveInited = true
  gSaveChannel.open()
  createThread(gSaveThread, saveWorker)

proc scheduleFileSave*(filename, content: string) =
  initSaveThread()
  gSaveChannel.send((filename, content))

