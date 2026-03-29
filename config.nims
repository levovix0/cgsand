
import "src/cgsand/lib/config.nims"


task run, "build and run":
  exec "nim c -r src/cgsand.nim"

