## registry of application keyboard shortcuts, in the spirit of Qt:
## a shortcut (analog of QShortcut) is registered in one place together with
## its key sequences, action and context, and automatically appears in the
## "Key combinations" dialog and in menubar hints.
## new shortcuts: `- (shortcut(["Ctrl+O"], "file.open", "Open")): on this.activated: ...`

import std/[strutils, sequtils]
import pkg/siwin
import pkg/sigui/uibase
import pkg/toscel/focus
import ./configuration


const
  ctrlKeys* = {Key.lcontrol, Key.rcontrol}
  shiftKeys* = {Key.lshift, Key.rshift}
  altKeys* = {Key.lalt, Key.ralt}
  systemKeys* = {Key.lsystem, Key.rsystem}
  allModifierKeys* = ctrlKeys + shiftKeys + altKeys + systemKeys


# ----- key sequences (analog of QKeySequence) -----

proc keySequence*(s: string): set[Key] =
  ## parses a human readable sequence, e.g. "Ctrl+Shift+S" or "Ctrl+Ins";
  ## modifier sides do not matter, a missing or unknown key is a developer error
  for token in s.split('+'):
    let t = token.strip.toLowerAscii
    case t
    of "ctrl", "control": result.incl Key.lcontrol
    of "shift": result.incl Key.lshift
    of "alt": result.incl Key.lalt
    of "super", "meta", "cmd": result.incl Key.lsystem
    of "enter", "return": result.incl Key.enter
    of "esc", "escape": result.incl Key.escape
    of "tab": result.incl Key.tab
    of "space": result.incl Key.space
    of "backspace": result.incl Key.backspace
    of "del", "delete": result.incl Key.del
    of "ins", "insert": result.incl Key.insert
    of "home": result.incl Key.home
    of "end": result.incl Key.End
    of "pageup": result.incl Key.pageUp
    of "pagedown": result.incl Key.pageDown
    of "left": result.incl Key.left
    of "right": result.incl Key.right
    of "up": result.incl Key.up
    of "down": result.incl Key.down
    else:
      if t.len == 1 and t[0] in {'a' .. 'z'}:
        result.incl Key(ord(Key.a) + ord(t[0]) - ord('a'))
      elif t.len == 1 and t[0] in {'1' .. '9'}:
        # siwin names number keys n1 .. n9, n0
        result.incl Key(ord(Key.n1) + ord(t[0]) - ord('1'))
      elif t == "0":
        result.incl Key.n0
      elif t.len >= 2 and t[0] == 'f' and t[1 .. ^1].allIt(it in {'0' .. '9'}):
        let n = t[1 .. ^1].parseInt
        if n in 1 .. 15:
          result.incl Key(ord(Key.f1) + n - 1)
        else:
          raise newException(ValueError, "unknown F-key in shortcut sequence \"" & s & "\": " & t)
      else:
        raise newException(ValueError, "unknown key in shortcut sequence \"" & s & "\": " & t)


proc matchesShortcut*(want, pressed: set[Key]): bool =
  ## `pressed` matches `want` when the non-modifier keys are the same, each
  ## wanted modifier group (ctrl/shift/alt/super, any side) is present and
  ## no extra modifiers are held
  if (want - allModifierKeys) != (pressed - allModifierKeys): return false
  for group in [ctrlKeys, shiftKeys, altKeys, systemKeys]:
    if ((want * group).len > 0) != ((pressed * group).len > 0): return false
  return true


# ----- registry (for the "Key combinations" dialog and menubar hints) -----

type
  AppShortcut* = object
    keys*: seq[set[Key]]
    id*: string
    titleGetter: proc(): string
      ## re-evaluated on every call, so the title follows the current language

var appShortcuts*: seq[AppShortcut]

proc registerShortcutImpl(keys: seq[set[Key]], id: string, titleGetter: proc(): string) =
  ## replaces the shortcut with the same id if it is already registered
  for i, s in appShortcuts:
    if s.id == id:
      appShortcuts[i] = AppShortcut(keys: keys, id: id, titleGetter: titleGetter)
      return
  appShortcuts.add AppShortcut(keys: keys, id: id, titleGetter: titleGetter)


proc shortcutKeys*(id: string): seq[set[Key]] =
  ## key sequences of the registered shortcut, empty when there is none
  for s in appShortcuts:
    if s.id == id:
      return s.keys
  result = @[]


proc shortcutTitle*(id: string): string =
  ## current (translated) title of the registered shortcut, "" when there is none
  for s in appShortcuts:
    if s.id == id:
      return s.titleGetter()
  result = ""


# ----- Shortcut component (analog of QShortcut) -----

type
  ShortcutContext* = enum
    scWindow
      ## the shortcut is active anywhere in the window, whatever is focused
      ## (analog of Qt::WindowShortcut)
    scWidgetWithChildren
      ## the shortcut is active only when the keyboard focus is inside the
      ## parent subtree (analog of Qt::WidgetWithChildrenShortcut)

  Shortcut* = ref object of Uiobj
    sequences: seq[set[Key]]
      ## several sequences activating one action (like QAction::setShortcuts)
    context: ShortcutContext
    id: string
    titleGetter: proc(): string
      ## re-evaluated on every call, so the title follows the current language
    activated*: Event[void]

registerComponent Shortcut


proc shortcut*(sequences: openArray[string], id: string, text: static string, context: ShortcutContext = scWindow): Shortcut =
  ## creates a shortcut to be used as a makeLayout node:
  ## `- (shortcut(["Ctrl+O"], "file.open", "Open")): on this.activated: ...`
  ## `text` is re-translated on every display, so language switching works live
  proc titleGetter(): string = tr(text)
  Shortcut(
    sequences: sequences.mapIt(keySequence(it)),
    context: context,
    id: id,
    titleGetter: titleGetter,
  )


proc focusInSubtree(n: Uiobj, subtree: Uiobj): bool =
  var n = n
  while n != nil:
    if n == subtree: return true
    n = n.parent
  result = false


proc contextActive(this: Shortcut): bool =
  case this.context
  of scWindow: true
  of scWidgetWithChildren: focusInSubtree(currentFocus[], this.parent)


method init(this: Shortcut) =
  procCall this.super.init()
  registerShortcutImpl(this.sequences, this.id, this.titleGetter)


method recieve(this: Shortcut, signal: Signal) =
  if signal of WindowEvent and signal.WindowEvent.event of KeyEvent and signal.WindowEvent.handled == false:
    let e = (ref KeyEvent)signal.WindowEvent.event
    if e.pressed and this.contextActive():
      let pressed = e.window.keyboard.pressed
      for keys in this.sequences:
        if keys.matchesShortcut(pressed):
          signal.WindowEvent.handled = true
          this.activated.emit()
          break

  procCall this.super.recieve(signal)


# ----- display -----

proc keyDisplay(k: Key): string =
  case k
  of Key.lcontrol, Key.rcontrol: "Ctrl"
  of Key.lshift, Key.rshift: "Shift"
  of Key.lalt, Key.ralt: "Alt"
  of Key.lsystem, Key.rsystem: "Super"
  of Key.enter: "Enter"
  of Key.escape: "Esc"
  of Key.tab: "Tab"
  of Key.space: "Space"
  of Key.backspace: "Backspace"
  of Key.del: "Del"
  of Key.insert: "Ins"
  of Key.left: "←"
  of Key.right: "→"
  of Key.up: "↑"
  of Key.down: "↓"
  of Key.pageUp: "PageUp"
  of Key.pageDown: "PageDown"
  of Key.home: "Home"
  of Key.End: "End"
  else:
    let name = $k
    if name.len == 1:
      name.toUpperAscii
    elif name.startsWith("n") and name.len == 2 and name[1].isDigit:
      $name[1]
    elif name.startsWith("f") and name.len >= 2 and name[1 .. ^1].allIt(it.isDigit):
      name.toUpperAscii
    else:
      name.capitalizeAscii()


proc keysDisplay*(keys: set[Key]): string =
  ## human readable key combination, e.g. "Ctrl+Shift+S"
  const modifierOrder = [
    Key.lcontrol, Key.rcontrol,
    Key.lalt, Key.ralt,
    Key.lshift, Key.rshift,
    Key.lsystem, Key.rsystem,
  ]

  var ordered: seq[Key]
  for k in modifierOrder:
    if k in keys: ordered.add k

  for k in keys:
    if k notin modifierOrder:
      ordered.add k

  result = ordered.mapIt(keyDisplay(it)).join("+")


proc sequencesDisplay*(keys: seq[set[Key]]): string =
  ## all sequences of a shortcut, e.g. "Ctrl+Shift+C, Ctrl+Ins"
  keys.mapIt(keysDisplay(it)).join(", ")


proc shortcutDisplay*(id: string): string =
  ## display of the registered shortcut for menubar hints, "" when there is none
  sequencesDisplay(shortcutKeys(id))
