## detection of "binary-looking" files, so they open in the hex editor
## instead of the code editor.
##
## a file is considered binary when its extension is a well known binary
## format, or (for unknown extensions) when its content sniffing shows it is
## not plain text: a NUL byte, a UTF-16 BOM or a high share of control
## characters, similar to how git decides whether a file is text


import std/[os, strutils]


const SniffLimit = 8192
  ## number of bytes checked by the content heuristic, like git does

const BinaryFileExts* = [
  "exe", "dll", "so", "dylib", "a", "lib", "o", "obj", "ko",
  "png", "jpg", "jpeg", "gif", "bmp", "ico", "webp", "tga", "psd", "tif", "tiff",
  "pdf", "zip", "gz", "bz2", "xz", "zst", "7z", "rar", "tar",
  "ttf", "otf", "woff", "woff2", "eot",
  "wasm", "class", "pyc", "jar",
  "bin", "dat", "db", "sqlite", "sqlite3", "iso", "img",
  "mp3", "ogg", "wav", "flac", "mp4", "avi", "mkv", "mov", "webm",
  "msi", "apk", "dmg", "deb", "rpm",
]

const TextFileExts* = [
  "nim", "nims", "nimble", "cfg", "txt", "md", "json", "toml", "ini",
  "yaml", "yml", "xml", "html", "htm", "css", "scss", "svg",
  "c", "h", "cpp", "hpp", "cs", "java", "py", "js", "ts", "rs", "go",
  "sh", "bash", "bat", "ps1", "fish", "sql", "csv", "tsv", "log",
]


proc looksLikeBinaryData*(data: openArray[byte]): bool =
  ## content heuristic: NUL byte, a UTF-16 byte order mark, or more than 10%
  ## control characters other than the usual text whitespace
  if data.len >= 2 and data[0] in {0xFF'u8, 0xFE'u8} and data[1] in {0xFF'u8, 0xFE'u8}:
    return false  # UTF-16 BOM — text with a different encoding

  var controlChars = 0
  for b in data:
    if b == 0: return true
    if b < 0x20 and b notin {0x09'u8, 0x0A'u8, 0x0C'u8, 0x0D'u8, 0x1B'u8} or b == 0x7F:
      inc controlChars

  result = controlChars * 10 > data.len


proc looksLikeBinaryFile*(path: string): bool =
  ## whether the file should be opened as binary (in the hex editor)
  let ext = path.splitFile.ext
  if ext.len > 0:
    let ext = ext[1 .. ^1].toLowerAscii
    if ext in TextFileExts: return false
    if ext in BinaryFileExts: return true

  var file: File
  if not file.open(path, fmRead): return false
  defer: file.close()

  let size = file.getFileSize()
  if size == 0: return false

  var sniff = newSeq[byte](min(size, SniffLimit))
  try:
    let read = file.readBytes(sniff, 0, sniff.len)
    if read == 0: return false
    result = looksLikeBinaryData(sniff[0 ..< read])
  except CatchableError:
    result = false
