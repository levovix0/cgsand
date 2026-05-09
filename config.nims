
import "src/cgsand/lib/config.nims"


task run, "build and run":
  exec "nim c --debugger:native -r src/cgsand.nim"

task runRelease, "build and run with -d:danger":
  exec "nim c -d:danger -r src/cgsand.nim"

