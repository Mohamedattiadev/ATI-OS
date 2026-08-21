// ati-clip — adapted from Omarchy's own shell/plugins/clipboard/Clipboard.qml
// (MIT, see ../../../NOTICE.md). Layout, full data model (wl-paste --watch
// capture, JSON history file, dedup, file:// URI detection), and keyboard
// contract are all matched directly to that file now, not approximated --
// an earlier pass here read copyq's &clipboard tab instead of capturing
// independently, which meant a data-integrity bug in copyq's own text/
// image mime handling (confirmed live: some entries carried raw PNG bytes
// under text/plain) showed up as garbage rows with no way to fix it from
// this side. Capturing directly, the way Omarchy's own file does, means
// that class of bug can't happen here at all.
//
// What's still ATI-OS-specific: the backing scripts this calls
// (ati-clip-capture/ati-clip-paste-text/ati-clip-paste-file/ati-clip-open)
// are ports of Omarchy's bin/omarchy-clipboard-* rather than calls to
// those scripts directly (no OMARCHY_PATH here), and the preview pane
// shows each entry's capture timestamp, which upstream's version doesn't.
//
// Reported live, more than once, that a run of styling passes here (a
// title/count row, hairline rules, a boxed search field, keycap-chip
// footer hints, a strengthened divider) had drifted from Omarchy's own
// look into something closer to this shell's OTHER popups. Reverted back
// to upstream's actual file (basecamp/omarchy, shell/plugins/clipboard/
// Clipboard.qml) line for line, style-wise -- checked directly against a
// real clone, not approximated from memory. Only the two deltas in the
// paragraph above remain.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

Item {
  id: root

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool clearConfirmOpen: false
  property var history: []

  property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  property string captureScript: "ati-clip-capture"
  property string pasteTextScript: "ati-clip-paste-text"
  property string pasteFileScript: "ati-clip-paste-file"
  property string openScript: "ati-clip-view-entry"

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property color scrim: Color.menu.scrim
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property int contentSpacing: Style.spacing.md
  readonly property int cardWidth: Math.min(Style.space(875), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(600), panel.height - Style.gapsOut * 2)
  readonly property int rowHeight: Math.max(Style.space(50), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  readonly property int historyLimit: 300

  function open() {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.cancelClearHistory()
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close(); else root.open()
  }

  function status() {
    return root.opened ? "open" : "closed"
  }

  function loadHistory(raw) {
    root.history = ClipboardHistory.parseHistory(raw)
    if (root.opened) root.rebuildDisplay()
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(root.history.slice(0, root.historyLimit), null, 2) + "\n")
  }

  function addClipboardEntry(entry) {
    var normalized = ClipboardHistory.normalizeEntry(entry)
    if (!normalized) return
    root.history = ClipboardHistory.addEntry(root.history, normalized, root.historyLimit)
    root.saveHistory()
    if (root.opened) root.rebuildDisplay()
  }

  function addClipboardJson(line) {
    root.addClipboardEntry(ClipboardHistory.parseEntryJson(line))
  }

  function requestClearHistory() {
    if (root.history.length === 0) return
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function cancelClearHistory() {
    root.clearConfirmOpen = false
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmClearHistory() {
    root.history = ClipboardHistory.clearHistory()
    root.saveHistory()
    root.selectedIndex = 0
    root.cursorActive = false
    root.disarmPointer()
    root.clearConfirmOpen = false
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function removeDisplayIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.history = ClipboardHistory.removeEntryAt(root.history, row.historyIndex)
    root.saveHistory()

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function rebuildDisplay() {
    var rows = ClipboardHistory.displayRows(root.history, root.filterText, 50)
    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      displayModel.append({
        entryType: row.entryType,
        fullText: row.fullText,
        previewText: row.previewText,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        capturedAt: row.capturedAt || "",
        path: row.path,
        mime: row.mime,
        historyIndex: row.index
      })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  // Was root.applySelected -- the auto-paste path (wl-copy then a
  // synthetic Shift+Insert keystroke 0.15-0.3s later). Asked for
  // directly: activating a row (click or Enter) should only COPY, same
  // as Shift+Enter already did, and leave the actual paste to the user's
  // own Ctrl+V -- "the one in the ctrl+v is the right one". Sidesteps
  // the wl-copy/wtype timing race entirely rather than trusting the
  // retry-loop fix in ati-clip-paste-file/-text to always win it.
  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.copySelected(displayModel.get(index))
  }

  function copyIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.copySelected(displayModel.get(index))
  }

  function openIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.openSelected(displayModel.get(index))
  }

  function copySelected(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Util.execDetached(pasteFileScript + " --copy-only " + row.mime + " " + Util.shellQuote(row.path))
    } else if (row.fullText) {
      Util.execDetached(pasteTextScript + " --copy-only --history-index " + row.historyIndex)
    }
  }

  function openSelected(row) {
    if (!row) return
    root.opened = false
    Util.execDetached(openScript + " --history-index " + row.historyIndex)
  }

  Component.onCompleted: initProc.running = true

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
    onFileChanged: reload()
  }

  // Reap watchers left behind by a previous shell instance, then start our
  // own. setpriv's --pdeathsig means the kernel kills each watcher the
  // moment this shell exits, however it exits, so there is no further
  // lifecycle management needed beyond this.
  Process {
    id: initProc
    command: ["pkill", "-f", "wl-paste .*--watch .*/ati-clip-capture"]
    onExited: {
      currentProc.running = true
      textWatchProc.running = true
      imageWatchProc.running = true
    }
  }

  Process {
    id: currentProc
    command: [root.captureScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addClipboardJson(text)
    }
  }

  Process {
    id: textWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Process {
    id: imageWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.captureScript, "image/png"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  // A watcher that dies takes clipboard history with it, silently: copying
  // still works, the picker still opens, and old entries are all still
  // there, so nothing recorded until the next shell reload. Bring it back
  // instead.
  Timer {
    id: watchRestartTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!textWatchProc.running) textWatchProc.running = true
      if (!imageWatchProc.running) imageWatchProc.running = true
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "ati-clip"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.clearConfirmOpen ? 20 : 0
        focus: root.opened

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.clearConfirmOpen) {
            if (clearConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.close()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            if (event.modifiers & Qt.ShiftModifier) root.requestClearHistory()
            else root.removeDisplayIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1); event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1); event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6); event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6); event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0); event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(displayModel.count - 1); event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive && (event.modifiers & Qt.AltModifier)) root.openIndex(root.selectedIndex)
            else if (root.cursorActive && (event.modifiers & Qt.ShiftModifier)) root.copyIndex(root.selectedIndex)
            else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          // Ctrl+HJKL vim motion, matching Menu.qml's own (ATI-OS's
          // addition there, commit 1825effb) exactly -- same
          // ControlModifier-exact-match convention, same K/J for up/down,
          // same L for activate. H has no submenu to "go back" to here
          // (the list is flat, not a tree), so it takes the same first
          // stage Escape already has: clear the filter if one is set.
          } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_K) {
            root.select(-1); event.accepted = true
          } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_J) {
            root.select(1); event.accepted = true
          } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_L) {
            if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_H) {
            if (root.filterText) root.setFilter("")
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: clearConfirm
          anchors.fill: parent
          opened: root.clearConfirmOpen
          z: 10
          message: "Delete entire clipboard history?"
          confirmText: "Delete"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelClearHistory()
          onConfirmed: root.confirmClearHistory()
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Search clipboard…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing

          Row {
            anchors.fill: parent
            spacing: 0

            Item {
              width: parent.width / 2
              height: parent.height
              clip: true

              ListView {
                id: resultList
                anchors.fill: parent
                anchors.rightMargin: root.contentMargin
                model: displayModel
                clip: true
                spacing: Style.space(4)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  id: row
                  required property int index
                  required property string entryType
                  required property string previewText
                  required property string fullText
                  required property string previewImage

                  readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

                  width: ListView.view.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: hasCursor ? root.selectedBackground : "transparent"

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    anchors.topMargin: Style.space(8)
                    anchors.bottomMargin: Style.space(8)
                    spacing: Style.space(10)

                    Image {
                      visible: row.previewImage.length > 0
                      width: visible ? parent.height : 0
                      height: parent.height
                      source: row.previewImage
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                    }

                    Text {
                      width: parent.width - (row.previewImage.length > 0 ? parent.height + parent.spacing : 0)
                      height: parent.height
                      text: row.previewText
                      color: row.hasCursor ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      opacity: row.entryType === "image" || row.entryType === "file" ? 0.72 : 1.0
                      elide: Text.ElideRight
                      wrapMode: Text.NoWrap
                      verticalAlignment: Text.AlignVCenter
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function(mouse) {
                      root.selectFromPointer(row.index, row, mouse)
                    }
                    onClicked: {
                      root.cursorActive = true
                      root.selectedIndex = row.index
                      root.activateIndex(row.index)
                    }
                  }
                }
              }
            }

            Item {
              id: previewPane
              width: parent.width / 2
              height: parent.height
              clip: true

              property var activeEntry: displayModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count ? displayModel.get(root.selectedIndex) : null

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(1, Style.normalBorderWidth)
                // Was Util.alpha(root.border, 0.28) (upstream's own value,
                // then bumped to 0.75) -- root.border's raw RGB is itself
                // near-black on this theme, so no alpha on top of it reads
                // as visible against the card's black background. The
                // card's OWN outer border stays bright because it goes
                // through Border.surfaceSpec's derivation, not this raw
                // property. Switched to root.foreground (confirmed
                // visible everywhere else -- every row/header label uses
                // it) so the line actually shows up. Verified by pixel-
                // sampling the rendered screenshot, not by eye -- the
                // 0.75 version LOOKED right in one crop and was
                // objectively absent (scanned full-width, zero non-black
                // pixels at the divider's x) in every other.
                color: Util.alpha(root.foreground, 0.35)
              }

              // ATI-OS fix (predates this session's styling pass, kept):
              // this used to be a Column with the image/text row given
              // `height: parent.height - Style.space(24)` -- a flat guess
              // at the header Text's rendered height that didn't match it,
              // so the image's real box ran past the card's bottom edge
              // (reported live: "images come over the frame"). Anchored
              // instead: the header gets its own real implicitHeight, and
              // previewBody fills exactly what's left below it, with
              // clip: true as a second line of defense.
              Text {
                id: previewHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: root.contentMargin
                text: previewPane.activeEntry && previewPane.activeEntry.capturedAt
                  ? "Copied " + previewPane.activeEntry.capturedAt : ""
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Item {
                id: previewBody
                anchors.top: previewHeader.bottom
                anchors.topMargin: Style.spacing.xs
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: root.contentMargin
                clip: true

                Text {
                  visible: previewPane.activeEntry && !previewPane.activeEntry.previewImage
                  anchors.fill: parent
                  text: previewPane.activeEntry ? previewPane.activeEntry.fullText : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  wrapMode: Text.WrapAnywhere
                  clip: true
                  verticalAlignment: Text.AlignTop
                }

                Image {
                  visible: previewPane.activeEntry && previewPane.activeEntry.previewImage
                  anchors.fill: parent
                  source: previewPane.activeEntry ? previewPane.activeEntry.previewImage : ""
                  fillMode: Image.PreserveAspectFit
                  verticalAlignment: Image.AlignTop
                  horizontalAlignment: Image.AlignLeft
                  asynchronous: true
                  smooth: true
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: "\u{F0A79}"
              color: root.selectedText
              opacity: 0.8
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: root.history.length === 0 ? "Clipboard is empty" : "No matches for “" + root.filterText + "”"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }
      }
    }
  }
}
