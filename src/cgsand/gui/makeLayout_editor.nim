import std/[sets]
import pkg/[vmath, chroma, ecs]
import pkg/rice/[rasterTexts, contexts, gl, primitives]
import pkg/toscel/[focus]
import pkg/sigui/[uibase, mouseArea]
import ../logic/[config, makeLayout_editor]

type
  MakeLayoutEditor* = ref object of Uiobj
    rootNode*: MleNode
    componentLibrary*: ComponentLibrary



method drawInner*(this: MakeLayoutEditor, ctx: DrawContext) =
  ##



