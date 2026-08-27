import std/[os, colors, strformat]

proc fg*(color: Color): string =
  const fgPrefix = "\e[38;2;"
  let rgb = extractRGB(color)
  result = fmt"{fgPrefix}{rgb.r};{rgb.g};{rgb.b}m"


withDir currentSourcePath().parentDir/"../":
  for k, p in walkDir("deps"):
    if k == pcDir:
      withDir p:
        echo fg colLightCyan, "updating: ", fg colGrey, p, "\e[0m"
        try: exec "git pull"
        except: echo fg colRed, "Error updating", "\e[0m"
