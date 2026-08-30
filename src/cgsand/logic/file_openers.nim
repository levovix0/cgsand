## an abstract "open this file" mechanism


type
  FileTarget* = object
    ## a location in a file to open
    path*: string
    line*: int    ## starts from 1, 0 when unknown
    column*: int  ## starts from 1, 0 when unknown

  FileOpener* = ref object of RootObj


method canOpen*(this: FileOpener, target: FileTarget): bool {.base.} =
  ## whether `open` makes sense for this file
  false


method open*(this: FileOpener, target: FileTarget) {.base.} =
  discard


proc openFile*(openers: openArray[FileOpener], target: FileTarget): bool =
  ## open `target` with the first opener in `openers` that accepts it.
  ## returns false when no opener can open it
  for opener in openers:
    if opener.canOpen(target):
      opener.open(target)
      return true
  false
