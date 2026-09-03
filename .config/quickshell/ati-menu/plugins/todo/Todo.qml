// ati-todo — a first QML surface for the open-task list, on the same terms
// Translate.qml and Anki.qml already established for their own keys.
//
// "why the todo win+p+t not like the other qml, it's rofi — make it qml
// one."
//
// v1 SCOPE: LIST + ADD + TOGGLE DONE, DELIBERATELY NOT ALL OF rofi_todo
// --------------------------------------------------------------------
// rofi_todo (AtiScriptsV1/notes/rofi_todo) is ~400 lines: four session
// tabs, priority AND colour tags, subtasks, a "working on" marker, inline
// edit, due-date changes, yank-to-clipboard. Porting all of that in one
// pass was declined in favour of list + add + toggle done — the rest
// stays on rofi_todo, same key it always had, still reachable.
//
// v2: PREVIEW PANE + VIM MOTION + TAB-TO-DONE
// ---------------------------------------------
// Asked for directly, twice: "should have a right handside preview that
// showes the whole todo thing if long and scrollable with wraped text",
// "i should be able to use the vim motion to go up down to my todos",
// "tabs can switched with the tab key to go to the done todos etc".
// Three additions, not a rewrite:
//   - a right-hand pane showing the SELECTED row's full text, wrapped and
//     scrollable, for what the list's own single line elides with "…";
//   - j/k (and the arrows) move a selection cursor instead of mouse-only,
//     Enter/Space toggles the row under it — live only while the add
//     field does NOT have focus, so typing a task still types "j" and "k";
//   - Tab flips between the open list and ati-todo-popup's new
//     `list-done` (same file, same JSON shape, the opposite checkbox).
// Priority/colour-tag editing, subtasks, the working-on marker, inline
// edit, due-date changes and yank are STILL not here — v2 added a second
// tab and a cursor, not the rest of rofi_todo.
//
// THE FILE FORMAT IS NOT REIMPLEMENTED HERE EITHER
// ---------------------------------------------------
// ati-todo-popup (AtiScriptsV1/notes/ati-todo-popup) owns the markdown
// parsing/rewriting, reading and locking the EXACT SAME
// ~/*TODOS/TODOS.md + .rofi_todo.lock rofi_todo already uses — a task
// added or checked off here shows up in rofi_todo and vice versa.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property bool opened: false
  property bool busy: false
  property string statusText: ""
  property string newTaskText: ""
  // "open" | "done" — which of ati-todo-popup's two lists is showing.
  property string viewMode: "open"
  // {line, text, prio, due, dueToday[, doneAt]} — see ati-todo-popup's
  // `list` / `list-done`. Always the CURRENT viewMode's rows; switching
  // modes replaces this rather than holding both lists at once, so a
  // stale toggle can never remove a row from the wrong array.
  property var tasks: []
  // Selection cursor into the SORTED list (see sortedTasks()), for the
  // vim motion and the preview pane. Clamped on every read, not just on
  // change, since `tasks` can shrink out from under it (a toggle removes
  // the row it just acted on).
  property int currentIndex: 0

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color scrim: Color.menu.scrim
  readonly property color accent: Color.accent
  readonly property var borderSpec: Border.localOrSurfaceSpec(
    "menu", "border", Color.menu.border, Color.menu.border, Style.normalBorderWidth)

  readonly property int cardMaxWidth: 880
  readonly property int cardMaxHeight: 560
  readonly property int contentMargin: Style.spacing.xxl
  readonly property int previewPaneWidth: 300

  signal closed()

  function open() {
    root.statusText = "";
    root.viewMode = "open";
    root.currentIndex = 0;
    root.opened = true;
    root.refresh();
  }

  function close() {
    root.opened = false;
    root.busy = false;
    root.closed();
  }

  function toggle() { root.opened ? root.close() : root.open() }
  function status() { return root.opened ? "open" : "closed" }

  // Priority high-to-low, due-today first within a priority — same
  // ordering v1 had. Only the open list needs this: `list-done` already
  // comes back newest-checked-first from ati-todo-popup's own `jq sort_by`.
  function sortedTasks() {
    if (root.viewMode !== "open") return root.tasks;
    const rank = { high: 2, normal: 1, low: 0 };
    return root.tasks.slice().sort((a, b) => {
      if (a.dueToday !== b.dueToday) return a.dueToday ? -1 : 1;
      return (rank[b.prio] || 1) - (rank[a.prio] || 1);
    });
  }

  function clampedIndex(list) {
    if (list.length === 0) return -1;
    return Math.max(0, Math.min(root.currentIndex, list.length - 1));
  }

  // Absolute path — same reasoning as Translate.qml's queryBin and
  // Anki.qml's ankiBin: a script added since the last install run has no
  // PATH symlink yet, and from QML that failure is silent.
  readonly property string backendBin:
    Quickshell.env("HOME") + "/.config/AtiScriptsV1/notes/ati-todo-popup"

  function refresh() {
    root.busy = true;
    listProc.command = [root.backendBin, root.viewMode === "done" ? "list-done" : "list"];
    listProc.running = true;
  }

  function switchTab() {
    root.viewMode = (root.viewMode === "open") ? "done" : "open";
    root.currentIndex = 0;
    root.refresh();
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.busy = false;
        try {
          root.tasks = JSON.parse(text);
          root.currentIndex = 0;
          root.statusText = root.tasks.length === 0
            ? (root.viewMode === "done" ? "nothing done yet" : "nothing open")
            : "";
        } catch (e) {
          root.tasks = [];
          root.statusText = "could not read the task list";
        }
      }
    }
  }

  function toggleTask(line) {
    // Optimistic removal — whichever list is showing only ever holds rows
    // matching ITS checkbox state, so acting on one always means it
    // leaves the visible list, not that its row flips state in place.
    root.tasks = root.tasks.filter((t) => t.line !== line);
    toggleProc.command = [root.backendBin, "toggle", String(line)];
    toggleProc.running = true;
  }
  Process { id: toggleProc; onExited: (code) => { if (code !== 0) root.refresh(); } }

  // Toggles whatever the cursor is currently on — Ctrl+Return and the
  // delegate's own click both funnel through this.
  function toggleCurrent() {
    const list = root.sortedTasks();
    const i = root.clampedIndex(list);
    if (i < 0) return;
    root.toggleTask(list[i].line);
  }

  // ---- keyboard: Tab/Ctrl+H/Ctrl+L switch tabs, Ctrl+J/Ctrl+K move,
  // Ctrl+Return toggles ----
  //
  // "up not working most of the time" + "after i move i can not write in
  // the field normal, i should use cursor to get into [it]" — both from
  // the SAME cause. This is attached to addField's own Keys.onPressed
  // (below), not only the card's: an item's own Keys.onPressed fires
  // BEFORE its default (C++) key handling, and QtQuick's TextField has
  // hard-coded Emacs-style editing shortcuts on Linux — Ctrl+K is
  // "delete to end of line", Ctrl+H is "backspace". Attached only at the
  // card level (v2's first cut), Ctrl+K/H never reached this function at
  // all while the field had focus: TextField's own internal handler
  // consumed them first — Ctrl+J has no such built-in meaning, which is
  // exactly why "down" worked and "up" (Ctrl+K) mostly didn't, and why
  // Ctrl+H (meant to switch tabs) was quietly editing the field instead
  // of ever reaching switchTab(). Bare Tab has the same problem for a
  // different reason: `Toggle`'s own `activeFocusOnTab: true` makes it a
  // stop on Qt's native Tab-focus-chain, which (like the Emacs shortcuts)
  // runs as native focus traversal, not a QML key event this function
  // could intercept from the card alone — hence focus visibly leaving the
  // add field and typing going nowhere until you clicked back into it.
  // Handling every one of these directly on addField, before TextField's
  // own C++ handling ever runs, is what actually stops all three.
  //
  // Toggle moved off bare Enter/Space onto Ctrl+Return for the same
  // reason plain j/k gave way to Ctrl+J/K: with the field now reliably
  // KEEPING focus (Tab no longer steals it), a bare Enter/Space guarded
  // by "only when unfocused" would almost never fire — Ctrl+Return has no
  // such ambiguity to guard against, since plain Enter must still submit
  // the field and plain Space must still type a space there.
  function handleKey(event) {
    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
    if (event.key === Qt.Key_Tab || (ctrl && (event.key === Qt.Key_H || event.key === Qt.Key_L))) {
      root.switchTab();
      event.accepted = true;
      return;
    }
    if (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_Down)) {
      const list = root.sortedTasks();
      if (list.length > 0) root.currentIndex = Math.min(root.clampedIndex(list) + 1, list.length - 1);
      event.accepted = true;
      return;
    }
    if (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_Up)) {
      const list = root.sortedTasks();
      if (list.length > 0) root.currentIndex = Math.max(root.clampedIndex(list) - 1, 0);
      event.accepted = true;
      return;
    }
    if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
      root.toggleCurrent();
      event.accepted = true;
      return;
    }
    // Bare arrows too, when nothing is typing — a mouseless fallback that
    // needs no Ctrl since an arrow key never types a character anywhere.
    if (!addField.activeFocus && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
      const list = root.sortedTasks();
      if (list.length > 0) {
        root.currentIndex = event.key === Qt.Key_Down
          ? Math.min(root.clampedIndex(list) + 1, list.length - 1)
          : Math.max(root.clampedIndex(list) - 1, 0);
      }
      event.accepted = true;
    }
  }

  function addTask() {
    const t = root.newTaskText.trim();
    if (t === "") return;
    root.newTaskText = "";
    root.busy = true;
    root.statusText = "adding…";
    const q = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";
    addProc.command = ["sh", "-c", q(root.backendBin) + " add " + q(t)];
    addProc.running = true;
  }
  Process {
    id: addProc
    onExited: (code) => {
      if (code !== 0) { root.busy = false; root.statusText = "add failed"; }
      else root.refresh();
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "ati-todo"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      width: Math.min(root.cardMaxWidth,
                      Math.max(320, panel.width - Style.spacing.huge * 4))
      implicitHeight: Math.min(root.cardMaxHeight,
                               card.contentTopInset + leftColumn.implicitHeight + card.contentBottomInset)
      height: implicitHeight
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      // BeforeItem so this sees every key before the focused TextField
      // does — belt and braces for handleKey below, which is also (and
      // primarily) attached directly to addField itself; see that
      // property's own comment for why the field needs its own copy.
      // Escape is unconditional, as before.
      Keys.priority: Keys.BeforeItem
      Keys.onEscapePressed: root.close()
      Keys.onPressed: function(event) { root.handleKey(event); }

      Row {
        id: contentRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.xl

        Column {
          id: leftColumn
          width: parent.width - root.previewPaneWidth - contentRow.spacing
          spacing: Style.spacing.xl

          // ---- title + tabs ----
          Item {
            width: parent.width
            height: Math.max(titleText.implicitHeight, tabsRow.implicitHeight)

            Text {
              id: titleText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Todo"
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            // Discoverability for the Tab binding — not clickable on
            // purpose, matching how the rest of this card treats Tab as a
            // KEY, not a mouse target; clicking a label here would be a
            // second, silently-diverging way to do the same thing.
            Row {
              id: tabsRow
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.md
              Text {
                text: "Open"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: root.viewMode === "open"
                color: root.viewMode === "open" ? root.accent : Qt.darker(root.foreground, 1.4)
              }
              Text {
                text: "·"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Qt.darker(root.foreground, 1.45)
              }
              Text {
                text: "Done"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: root.viewMode === "done"
                color: root.viewMode === "done" ? root.accent : Qt.darker(root.foreground, 1.4)
              }
              Text {
                text: "  (Tab / ^H ^L)"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Qt.darker(root.foreground, 1.45)
              }
            }
          }

          // ---- add ----
          Item {
            width: parent.width
            height: Math.max(root.fieldHeightFor(addField), addButton.implicitHeight)
            visible: root.viewMode === "open"

            TextField {
              id: addField
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - addButton.width - Style.spacing.controlGap
              height: Style.spacing.controlHeight
              text: root.newTaskText
              placeholderText: "add a task…"
              foreground: root.foreground
              font.family: Style.font.family
              onTextEdited: root.newTaskText = text
              onAccepted: root.addTask()
              focus: root.opened
              // Primary handler, not the card's — see handleKey's own
              // comment for why this has to run here, before this
              // field's built-in Ctrl+H/Ctrl+K editing shortcuts do.
              Keys.onPressed: function(event) { root.handleKey(event); }
            }

            Button {
              id: addButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "Add"
              // Button's idle state is transparent with no border by
              // default (see Ui/Button.qml's own state table) — visible
              // only once hovered. `bordered` opts into the normal-state
              // border everywhere else in the kit that needs to read as a
              // button at rest instead of floating, unlabeled text.
              bordered: true
              // Same token issue as the toggle switches (see that
              // comment): Button's border/fill/text all key off ONE
              // `foreground`, and this theme's missing shell.toml means
              // the "normal"/"hover" tokens fall back to plain foreground
              // — so a merely-bordered button was still grey, not coloured.
              // Unlike Toggle's switch, Button's foreground doesn't also
              // paint anything else's label, so accent here is just this
              // button, not a side effect on unrelated text.
              foreground: root.accent
              enabled: root.newTaskText.trim() !== ""
              onClicked: root.addTask()
            }
          }

          // ---- list ----
          ListView {
            id: listView
            width: parent.width
            height: Math.min(Style.spacing.controlHeight * 7,
                             Math.max(Style.spacing.controlHeight, contentHeight))
            clip: true
            spacing: Style.spacing.sm
            boundsBehavior: Flickable.StopAtBounds
            model: root.sortedTasks()
            currentIndex: root.clampedIndex(root.sortedTasks())
            highlightFollowsCurrentItem: true

            // A hand-rolled row instead of the shared `Toggle` component.
            // "the toggle button should be with color not just gray" — the
            // reason it was gray is structural, not a shade pick: this
            // theme ships no shell.toml, so Style.qml's `selected-color`
            // token (what a checked ToggleSwitch paints itself with) falls
            // back to its own default, "foreground" — and `Toggle` shares
            // ONE `foreground` property between its label text AND its
            // switch, so the only way to make the switch read as accent
            // through that one property is to make the LABEL accent too,
            // which is worse, not fixed. Splitting the switch out as its
            // own bare `ToggleSwitch` (no label baked in) sidesteps the
            // token entirely: its `foreground` only ever paints the track
            // and knob, so it can be `root.accent` without touching the
            // row's actual text colour.
            delegate: BorderSurface {
              id: rowDelegate
              required property var modelData
              required property int index
              width: listView.width
              implicitHeight: Math.max(54, rowContent.implicitHeight + Style.spacing.huge)
              height: implicitHeight
              radius: Style.cornerRadius

              // The vim cursor, not hover — same "hasCursor" role Toggle's
              // own version played, just computed locally now.
              readonly property bool hot: index === root.currentIndex || rowMouse.containsMouse
              color: Style.controlFill(false, hot, root.foreground, root.accent)
              borderSpec: Border.controlSpec(hot ? "hover-cursor" : "normal", root.foreground, root.accent)

              readonly property string descriptionText: root.viewMode === "done"
                ? (modelData.doneAt || "")
                : [
                    modelData.dueToday ? "due today" : "",
                    modelData.prio !== "normal" ? modelData.prio + " priority" : ""
                  ].filter((s) => s !== "").join(" · ")

              Row {
                id: rowContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: rowDelegate.borderLeft + Style.spacing.rowPaddingX
                anchors.rightMargin: rowDelegate.borderRight + Style.spacing.rowPaddingX
                spacing: Style.spacing.rowPaddingX

                Column {
                  width: parent.width - doneSwitch.width - parent.spacing
                  spacing: Style.spacing.xs
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    text: rowDelegate.modelData.text
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    visible: rowDelegate.descriptionText !== ""
                    text: rowDelegate.descriptionText
                    // Colour-coded rather than uniformly muted: high
                    // priority in the theme's own urgent colour, due-today
                    // in accent — "the side content also... with colors",
                    // and these two are exactly the states rofi_todo's own
                    // PRIO_HIGH_COLOR/DUE_COLOR already called out that
                    // this port had flattened to one grey caption.
                    color: root.viewMode !== "done" && rowDelegate.modelData.prio === "high" ? Color.urgent
                      : root.viewMode !== "done" && rowDelegate.modelData.dueToday ? root.accent
                      : Qt.darker(root.foreground, 1.3)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                  }
                }

                ToggleSwitch {
                  id: doneSwitch
                  checked: root.viewMode === "done"
                  foreground: root.accent
                  interactive: false   // the row's own MouseArea owns the click
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.currentIndex = rowDelegate.index; root.toggleTask(rowDelegate.modelData.line); }
              }
              HoverHandler {
                onHoveredChanged: if (hovered) root.currentIndex = rowDelegate.index
              }
            }
          }

          Text {
            visible: root.tasks.length === 0 && !root.busy
            width: parent.width
            text: root.viewMode === "done" ? "nothing done yet" : "nothing open"
            color: Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          // ---- status ----
          // Falls back to the key hint when there is nothing more urgent
          // to say — a status message (adding…, add failed, …) always
          // takes priority over it, same as it always has.
          Text {
            width: parent.width
            text: root.busy ? "…" : (root.statusText !== "" ? root.statusText : "^J/^K move · ^Return toggle · click also works")
            color: Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        // ---- right-hand preview pane ----
        // The list's own row elides long text with "…" — this shows the
        // SELECTED row's full text, wrapped, in a pane that scrolls once
        // it is taller than the card, for the ones long enough to need it.
        //
        // "the side content also right hand side with colors etc" — it was
        // a flat, barely-distinct shade of the card's own background with
        // no colour anywhere in it. An accent-toned border (BorderSurface,
        // same control-border machinery every other bordered surface in
        // this kit uses, rather than a bespoke Rectangle border) and a
        // colour-matched heading tie it visibly to the row it is
        // previewing instead of reading as an empty grey box beside it.
        BorderSurface {
          id: previewPane
          width: root.previewPaneWidth
          height: leftColumn.height
          radius: Style.cornerRadius
          color: Qt.darker(root.background, 1.15)
          borderSpec: Border.controlSpec("hover-cursor", root.foreground, root.accent)
          padding: Style.spacing.lg

          readonly property var currentTask: {
            const list = root.sortedTasks();
            const i = root.clampedIndex(list);
            return i >= 0 ? list[i] : null;
          }

          Column {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: previewPane.contentTopInset
            anchors.leftMargin: previewPane.contentLeftInset
            anchors.rightMargin: previewPane.contentRightInset
            spacing: Style.spacing.sm

            Text {
              text: previewPane.currentTask
                ? (root.viewMode === "done" ? "Done" : "Preview")
                : "Preview"
              color: root.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              visible: previewPane.currentTask
                && [previewPane.currentTask.dueToday ? "x" : "",
                    previewPane.currentTask.prio !== "normal" ? "x" : "",
                    previewPane.currentTask.doneAt || ""].join("") !== ""
              width: parent.width
              text: previewPane.currentTask ? [
                previewPane.currentTask.dueToday ? "due today" : "",
                (previewPane.currentTask.prio && previewPane.currentTask.prio !== "normal") ? previewPane.currentTask.prio + " priority" : "",
                previewPane.currentTask.doneAt || ""
              ].filter((s) => s !== "").join(" · ") : ""
              color: previewPane.currentTask && previewPane.currentTask.prio === "high" ? Color.urgent
                : previewPane.currentTask && previewPane.currentTask.dueToday ? root.accent
                : Qt.darker(root.foreground, 1.3)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Flickable {
              id: previewFlick
              width: parent.width
              height: leftColumn.height - previewPane.contentTopInset - previewPane.contentBottomInset - Style.spacing.xxl
              contentWidth: width
              contentHeight: previewText.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Text {
                id: previewText
                width: previewFlick.width
                text: previewPane.currentTask ? previewPane.currentTask.text : "select a task to preview it here"
                color: previewPane.currentTask ? root.foreground : Qt.darker(root.foreground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
              }
            }
          }
        }
      }
    }
  }

  function fieldHeightFor(f) { return Math.max(Style.spacing.controlHeight, f.implicitHeight) }
}
