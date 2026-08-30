## an abstract "open this file" mechanism


type
  Location* = object
    ## a location in a file to open
    path*: string
    line*, col*: int    ## starts from 1, 0 when unknown

  FileOpener* = ref object of RootObj


method canOpen*(this: FileOpener, target: Location): bool {.base.} =
  ## whether `open` makes sense for this file
  false


method open*(this: FileOpener, target: Location) {.base.} =
  discard


proc open*(openers: openArray[FileOpener], target: Location) =
  ## open `target` with the first opener in `openers` that accepts it
  for opener in openers:
    if opener.canOpen(target):
      opener.open(target)
      return
