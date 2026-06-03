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

requires "jsony"

# --- unstable dependencies ---

requires "sigui >= 0.2.6"
  ## for GUI

requires "shady == 0.1.4"

requires "https://github.com/levovix0/sigeo#head"
  ## for defing continuous geometry in scripts

requires "https://github.com/levovix0/ecs#head"
  ## for communicating with scripts

requires "https://github.com/levovix0/toscel#head"
  ## for basic GUI widgets

