import std/atomics



type
  SaveMsg = tuple[filename, content: string]

var gSaveChannel: Channel[SaveMsg]
var gSaveThread: Thread[void]
var gSaveInited = false

# counts of scheduled and completed file writes; used by fileSavesPending
# to detect when a scheduled save has not reached the disk yet
var gScheduledSaves: Atomic[int]
var gCompletedSaves: Atomic[int]
gScheduledSaves.store(0)
gCompletedSaves.store(0)

proc saveWorker() {.thread.} =
  while true:
    var msg = gSaveChannel.recv()      # block until first request
    var consumed = 1
    var latest = @[msg]                # keep only the latest request per file
    while true:                        # drain – drop requests superseded by a newer one
      let (ok, newer) = gSaveChannel.tryRecv()
      if not ok: break
      inc consumed
      var superseded = false
      for i, m in latest:
        if m.filename == newer.filename:
          latest[i] = newer
          superseded = true
          break
      if not superseded:
        latest.add newer
    for m in latest:
      try: writeFile(m.filename, m.content)
      except: discard
    # superseded requests are counted as completed too: their newer version
    # was written just above, so nothing scheduled is left in flight
    discard gCompletedSaves.fetchAdd(consumed)

proc initSaveThread() =
  if gSaveInited: return
  gSaveInited = true
  gSaveChannel.open()
  createThread(gSaveThread, saveWorker)

proc scheduleFileSave*(filename, content: string) =
  initSaveThread()
  discard gScheduledSaves.fetchAdd(1)
  gSaveChannel.send((filename, content))

proc fileSavesPending*(): bool =
  ## true while there are writes scheduled by scheduleFileSave that have not
  ## reached the disk yet; readers that want to detect external file changes
  ## should wait for this to become false, otherwise they may see their own
  ## not-yet-written content (or partially written content) as "external"
  gScheduledSaves.load(moRelaxed) != gCompletedSaves.load(moRelaxed)
