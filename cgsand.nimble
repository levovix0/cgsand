# Package

version       = "0.1.0"
author        = "levovix"
description   = "Code-geometric sandbox"
license       = "MIT"
srcDir        = "src"
bin           = @["cgsand"]



requires "nim >= 2.2.4"



# --- stable dependencies ---

requires "localize >= 0.3.5" #d1b5ae63
  ## for translations

# --- unstable dependencies ---

requires "sigui#35ba4728"
  ## for GUI

requires "https://github.com/levovix0/sigeo#c4a8cc1f"
  ## for defing continuous geometry in scripts

requires "https://github.com/levovix0/ecs#d18b9fe8"
  ## for communicating with scripts

requires "https://github.com/levovix0/toscel#dda9f55"
  ## for basic GUI widgets



# --- package lock for dependencies of dependencies, to ensure reproducability ---

requires "siwin#54c0ca5b"
requires "shady#fa75f793"
requires "opengl#8e2e098f"
requires "print#fb09637d"
requires "fusion#0b0a0273"
requires "bumpy#edc6e19d"
requires "vmath#eac8527b"
requires "chroma#8bf4a093"
requires "pixie#5eda4949"
requires "x11#29aca5e5"
requires "crunchy#98eb6526"
requires "zippy#bcb8c1e1"
requires "flatty#07f6ba8a"
requires "nimsimd#3f6b2668"

