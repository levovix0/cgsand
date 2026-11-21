## settings window in Master-Detail style:
## on the left — the list of pages, on the right — the contents of the
## selected page. opened by the "Options" menu entry.
##
## api for adding pages:
##
## .. code-block:: nim
##   proc myPageTitle(): string = tr"My page"
##
##   proc buildMyPage(page: Uiobj) =
##     page.makeLayout:
##       - Label.new:
##         text = tr"Hello"
##
##   registerSettingsPage "myPage", myPageTitle, buildMyPage
##
## pages are rebuilt when the selected page or the language changes.

import pkg/sigui/[uibase, mouseArea, scrollArea, animations]
import pkg/toscel/[colors, fonts, comboBox, label, menuBar, modalOverlay, transitions]
import ../logic/[configuration]

type
  SettingsPage* = object
    id*: string
    titleGetter: proc(): string
      ## re-evaluated on every call, so the title follows the current language
    build: proc(page: Uiobj)
      ## fills `page` with the page contents

  SettingsWindow* = ref object of ModalOverlay
    pages: seq[SettingsPage]
    selectedPageIndex: Property[int]

registerComponent SettingsWindow


var settingsPages: seq[SettingsPage]

proc registerSettingsPage*(id: string, titleGetter: proc(): string, build: proc(page: Uiobj)) =
  ## registers a settings page; replaces the page with the same id if it
  ## is already registered
  for i, page in settingsPages:
    if page.id == id:
      settingsPages[i] = SettingsPage(id: id, titleGetter: titleGetter, build: build)
      return
  settingsPages.add SettingsPage(id: id, titleGetter: titleGetter, build: build)


# ----- "General" page -----

proc generalPageTitle(): string = tr"General"

proc buildGeneralPage(page: Uiobj) =
  page.makeLayout:
    # language
    - Label.new:
      left = parent.left
      centerY = parent.top + 20
      text = tr"Language"

    - ComboBox.new as languageCombo:
      right = parent.right
      centerY = parent.top + 20
      w = 160
      otherTextCanBeEntered = false
      fitOptionsWidth = false
      options = @[tr"System", "English", "Русский"]
      selectedOption = (case config.language[]
        of "en": 1
        of "ru": 2
        else: 0)

      on this.optionSelected:
        config.language[] = (case this.selectedOption[]
          of 1: "en"
          of 2: "ru"
          else: "")

    # theme
    - Label.new:
      left = parent.left
      centerY = parent.top + 64
      text = tr"Theme"

    - ComboBox.new as themeCombo:
      right = parent.right
      centerY = parent.top + 64
      w = 160
      otherTextCanBeEntered = false
      fitOptionsWidth = false
      options = @[tr"Dark", tr"Light"]
      selectedOption = (if config.uiTheme[] == "light": 1 else: 0)

      on this.optionSelected:
        config.uiTheme[] = (if this.selectedOption[] == 1: "light" else: "dark")


registerSettingsPage("general", generalPageTitle, buildGeneralPage)


method init*(this: SettingsWindow) =
  procCall this.super.init()

  this.selectedPageIndex = 0.property
  this.pages = settingsPages

  this.content.w[] = 660
  this.content.h[] = 420

  this.makeLayout:
    - UiRect.new:  # window panel
      this.fill(parent)
      radius = 8
      color = binding: colorTheme[].bgOverlay

    # --- left column: pages list ---

    - ScrollArea.new as pageListArea:
      left = parent.left + 12
      top = parent.top + 12
      bottom = parent.bottom - 12
      w = 180

      --- Uiobj.new:  # rows, recreated on language change
        <--- {update}: config.language[]

        # size the rows container, otherwise the rows (which fill it
        # horizontally) would have zero width
        this.fillHorizontal(parent)

        var rowY = 0'f32
        for pageI, page in root.pages:
          let pageIndex = pageI
          let title = page.titleGetter()

          - MouseArea.new:
            x = 0
            y = rowY
            this.fillHorizontal(parent)
            h = 32
            cursor = pointingHand

            - UiRect.new:
              this.fill(parent)
              radius = 4
              color = binding:
                if root.selectedPageIndex[] == pageIndex:
                  if parent.hovered[]: color_bg_accent_button_hovered[]
                  else: color_bg_accent_button[]
                elif parent.hovered[]: color_bg_button_hovered[]
                else: "#00000000".color

              addTransition this.color

            - UiText.new:
              this.left = parent.left + 10
              this.centerY = parent.center
              text = title
              font = font_default.withSize(14)
              color = binding:
                if root.selectedPageIndex[] == pageIndex: color_fg_accent[]
                elif parent.hovered[]: color_fg_active[]
                else: color_fg[]

              addTransition this.color

            on this.clicked:
              root.selectedPageIndex[] = pageIndex

          rowY += 36

    # --- right column: contents of the selected page ---

    - Uiobj.new as pageHost:
      left = pageListArea.right + 12
      right = parent.right - 12
      top = parent.top + 12
      bottom = parent.bottom - 12

      --- Uiobj.new:  # recreated when the selected page or the language changes
        <--- {update}: root.selectedPageIndex[]; config.language[]

        # size the page container, the page contents are anchored to it
        this.fill(parent)

        if root.selectedPageIndex[] in 0 .. root.pages.high:
          let page = root.pages[root.selectedPageIndex[]]

          - UiText.new:  # page title
            this.left = parent.left
            this.top = parent.top
            text = page.titleGetter()
            font = font_default.withSize(18)
            color = binding: colorTheme[].cActive

          - Uiobj.new:  # page contents
            this.left = parent.left
            this.right = parent.right
            this.top = parent.top + 44
            this.bottom = parent.bottom

            page.build(this)

    # the border is the last child, so it draws above the page contents;
    # no `layer` here: layer-attached objects are drawn via drawAfterLayer
    # unconditionally and would be visible even when the overlay is closed
    - UiRectBorder.new:
      this.fill(parent)
      radius = 8
      borderWidth = 1
      color = binding: colorTheme[].borderOverlay
