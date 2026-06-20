import ../sandbox
import std/[times]
import pkg/[vmath, bumpy]
import pkg/siwin/platforms/any/window
export window


declare_ecs_system windowEvent(e: CloseEvent)
declare_ecs_system windowEvent(e: RenderEvent)
declare_ecs_system windowEvent(e: TickEvent)
declare_ecs_system windowEvent(e: ResizeEvent)
declare_ecs_system windowEvent(e: WindowMoveEvent)

declare_ecs_system windowEvent(e: MouseMoveEvent)
declare_ecs_system windowEvent(e: MouseButtonEvent)
declare_ecs_system windowEvent(e: ScrollEvent)
declare_ecs_system windowEvent(e: ClickEvent)

declare_ecs_system windowEvent(e: KeyEvent)
declare_ecs_system windowEvent(e: TextInputEvent)

declare_ecs_system windowEvent(e: TouchEvent)
declare_ecs_system windowEvent(e: TouchMoveEvent)
declare_ecs_system windowEvent(e: TouchPressureChangedEvent)

declare_ecs_system windowEvent(e: StateBoolChangedEvent)
declare_ecs_system windowEvent(e: PopupEvent)
declare_ecs_system windowEvent(e: DropEvent)

declare_ecs_system mainModuleFinished()
declare_ecs_system viewportChanged()


var projectionMatrix* {.exportc: "interactive_systems_projectionMatrix", dynlib.}: proc(): Mat4 {.cdecl.}
var viewportMatrix* {.exportc: "interactive_systems_viewportMatrix", dynlib.}: proc(): Mat4 {.cdecl.}
var viewportWindowBounds* {.exportc: "interactive_systems_viewportWindowBounds", dynlib.}: proc(): Rect {.cdecl.}

## world units per screen pixel for the current viewport (zoom included)
var unitsPerPixel* {.exportc: "interactive_systems_unitsPerPixel", dynlib.}: proc(): float {.cdecl.}

var rerunScript* {.exportc: "interactive_systems_rerunScript", dynlib.}: proc() {.cdecl.}

proc interactive_systems_windowEvent_CloseEvent(e: CloseEvent) {.exportc, dynlib.} = doc.windowEvent(e)
proc interactive_systems_windowEvent_RenderEvent(e: RenderEvent) {.exportc, dynlib.} = doc.windowEvent(e)
proc interactive_systems_windowEvent_TickEvent(e: TickEvent) {.exportc, dynlib.} = doc.windowEvent(e)
proc interactive_systems_windowEvent_ResizeEvent(e: ResizeEvent) {.exportc, dynlib.} = doc.windowEvent(e)
proc interactive_systems_windowEvent_WindowMoveEvent(e: WindowMoveEvent) {.exportc, dynlib.} = doc.windowEvent(e)

proc interactive_systems_windowEvent_MouseMoveEvent(e: MouseMoveEvent) {.exportc, dynlib.} = doc.windowEvent(e)
proc interactive_systems_windowEvent_MouseButtonEvent(e: MouseButtonEvent) {.exportc, dynlib.} = doc.windowEvent(e)
proc interactive_systems_windowEvent_ScrollEvent(e: ScrollEvent) {.exportc, dynlib.} = doc.windowEvent(e)
proc interactive_systems_windowEvent_ClickEvent(e: ClickEvent) {.exportc, dynlib.} = doc.windowEvent(e)

proc interactive_systems_windowEvent_KeyEvent(e: KeyEvent) {.exportc, dynlib.} = doc.windowEvent(e)
proc interactive_systems_windowEvent_TextInputEvent(e: TextInputEvent) {.exportc, dynlib.} = doc.windowEvent(e)

proc interactive_systems_windowEvent_TouchEvent(e: TouchEvent) {.exportc, dynlib.} = doc.windowEvent(e)
proc interactive_systems_windowEvent_TouchMoveEvent(e: TouchMoveEvent) {.exportc, dynlib.} = doc.windowEvent(e)
proc interactive_systems_windowEvent_TouchPressureChangedEvent(e: TouchPressureChangedEvent) {.exportc, dynlib.} = doc.windowEvent(e)

proc interactive_systems_windowEvent_StateBoolChangedEvent(e: StateBoolChangedEvent) {.exportc, dynlib.} = doc.windowEvent(e)
proc interactive_systems_windowEvent_PopupEvent(e: PopupEvent) {.exportc, dynlib.} = doc.windowEvent(e)
proc interactive_systems_windowEvent_DropEvent(e: DropEvent) {.exportc, dynlib.} = doc.windowEvent(e)

proc interactive_systems_mainModuleFinished() {.exportc, dynlib.} = doc.mainModuleFinished()
proc interactive_systems_viewportChanged() {.exportc, dynlib.} = doc.viewportChanged()


proc secs*(d: Duration): float =
  d.inMicroseconds.float / 1e6

proc ms*(d: Duration): float =
  d.inMicroseconds.float / 1e3

