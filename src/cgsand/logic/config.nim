import pkg/localize
import pkg/sigui/[properties]
export localize

requireLocalesToBeTranslated ("ru", "")


# var currentScript*: Property[string] = "examples/script.nim".property
var currentScript*: Property[string] = "examples/logical_scheme.nim".property

# todo: make config an object
# todo: save and load config


