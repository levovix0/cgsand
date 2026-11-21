## build-time information about the application, shown in the "About" dialog.
## the version comes from the nimble file, the maintainers list from the
## MAINTAINERS.txt file in the repository root (baked in at build time),
## library versions from atlas.lock.

import std/[strutils, json, sequtils, algorithm, os]


const repoRoot = currentSourcePath().parentDir.parentDir.parentDir.parentDir


proc extractNimbleVersion(): string =
  let nimble = staticRead(repoRoot / "cgsand.nimble")
  for line in nimble.splitLines:
    let stripped = line.strip()
    if stripped.startsWith("version"):
      let parts = stripped.split('"')
      if parts.len >= 2:
        return parts[^2]
  result = ""


const appVersion* = extractNimbleVersion()

## the MAINTAINERS.txt file is optional; "levovix" is used when it doesn't exist
const maintainers* =
  when compiles(staticRead(repoRoot / "MAINTAINERS.txt")):
    staticRead(repoRoot / "MAINTAINERS.txt").strip()
  else:
    "levovix"

const atlasLockJson = staticRead(repoRoot / "atlas.lock")

proc librariesInfo*(): string =
  ## one line per library: "name (short commit)", sorted by name
  try:
    let items = atlasLockJson.parseJson()["items"]
    var lines: seq[string]
    for name in items.keys.toSeq.sorted:
      let item = items[name]
      let url = item["url"].getStr()
      let repoName = url.split("/")[^1].changeFileExt("")
      let commit = item["commit"].getStr()
      let shortCommit = if commit.len > 8: commit[0 ..< 8] else: commit
      lines.add repoName & " (" & shortCommit & ")"
    result = lines.join("\n")
  except CatchableError:
    result = ""
