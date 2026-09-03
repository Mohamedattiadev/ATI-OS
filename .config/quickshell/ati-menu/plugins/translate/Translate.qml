// ati-translate — the hover/lookup translator popup.
//
// "what i wanted is an intelgent popuip like the google extention appers i
// click on it opens a popupp window has the word and tranasltion and
// epxaliont and sentece , and i they will be as 2 text field i can write
// also what i want inside a dropdown for changeing the lang right , all os
// this showed bi ui ux with qml"
//
// WHAT THIS REPLACES, AND WHY IT IS A NEW SURFACE RATHER THAN A NEW SKIN
// ---------------------------------------------------------------------
// rofi_translator renders its result as a notification, or as rows in the
// generic dmenu list. Both are READ-ONLY lists: a dmenu row is a label plus
// a subtext and there is nowhere to type, no second field, and no control
// that isn't "pick a row". The ask here is an editable form -- two text
// fields you can correct, a language dropdown that re-runs the lookup --
// which is not a restyling of a picker, it is a different kind of window.
// So it is its own plugin beside the clipboard one, on the same terms:
// its own Item, its own state, its own IpcHandler target in shell.qml.
//
// EDITABLE IS THE POINT, NOT A CONVENIENCE
// ----------------------------------------
// Machine translation of a single word out of context is regularly wrong,
// and this popup's whole job is to put a line in your vocabulary notes. A
// read-only popup would file the wrong line. Every one of the four fields
// is editable and what you SEE is exactly what Save writes -- so correcting
// a bad translation, or writing your own explanation, is the normal way to
// use this rather than a workaround.
//
// The explanation and sentence come from Gemini, and this machine's
// ~/.config/secrets.env currently has `GEMINI_API_KEY=` with an empty
// value -- so today those two arrive blank. That is exactly why they are
// typeable: the popup is useful with no API key at all, and simply better
// with one.
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

  // The four editable fields. Held here, not read off the TextFields, so
  // that a re-translate can repopulate them and Save has one source of
  // truth regardless of which of the two wrote them last.
  property string word: ""
  property string translation: ""
  property string explanation: ""
  property string sentence: ""
  property string sourceLang: ""
  // Turkish by default, asked for directly. Kept as a plain property rather
  // than a constant so the dropdown can still change it for the session --
  // picking another language is one click and it sticks until the popup is
  // next opened fresh.
  //
  // Turkish leads the list above for the same reason: a dropdown's first row
  // is where the eye lands, and the default belongs there.
  property string targetLang: "tr"
  property string statusText: ""

  // Matches rofi_translator's own list, which is the set this user actually
  // works in. Kept as {value,label} pairs because Dropdown renders `label`
  // and emits `value` -- a bare "ar" in a dropdown is a worse affordance
  // than "ar · Arabic" for no saving.
  readonly property var languages: [
    { value: "tr", label: "tr · Turkish" },
    { value: "en", label: "en · English" },
    { value: "de", label: "de · German" },
    { value: "ar", label: "ar · Arabic" },
    { value: "fr", label: "fr · French" },
    { value: "es", label: "es · Spanish" }
  ]

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color scrim: Color.menu.scrim
  readonly property color accent: Color.accent
  readonly property var borderSpec: Border.localOrSurfaceSpec(
    "menu", "border", Color.menu.border, Color.menu.border, Style.normalBorderWidth)

  // Clamped against the WINDOW's width, below, not against `Screen` here.
  // `Screen` is an attached property of the item's window, and this Item has
  // no window -- so outside a PanelWindow it resolves to whatever Qt
  // considers primary, which on a multi-monitor session is not necessarily
  // the screen the popup is drawn on. The PanelWindow spans its own output
  // and knows the right number.
  // ---- THE FONT HAS TO CARRY ARABIC, AND Ubuntu DOES NOT ----
  //
  // Style.font.family is "Ubuntu", whose cmap has NO Arabic at all (checked
  // directly). Qt then falls back per character, which is where the
  // "not fully vivible not readble" came from: a fallback chain picked per
  // glyph gives inconsistent shaping and joining across one word.
  //
  // The Qt 6 ordered font list is NOT exposed on this TextField: assigning
  // it is a hard "Cannot assign to non-existent property" at load, which the
  // nested check caught before it ever reached the running shell. Per field.
  function familyFor(t) { return isRtl(t) ? "Noto Sans Arabic" : Style.font.family }

  // Arabic and Hebrew ranges. Used to flip a field's alignment, because a
  // right-to-left string in a left-aligned box reads from the wrong edge and
  // elides from the wrong end.
  function isRtl(t) { return /[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF\u0590-\u05FF]/.test(String(t || "")); }

  // Arabic needs more vertical room than Latin at the same pixel size --
  // its marks sit above and below the baseline, and a box sized for Ubuntu's
  // Latin metrics clips them. Derived from the font size rather than
  // hardcoded so it still tracks a theme that changes the type scale.
  readonly property int fieldHeight:
    Math.max(Style.spacing.controlHeight, Math.round(Style.font.subtitle * 2.4))

  readonly property int cardMaxWidth: 560
  readonly property int contentMargin: Style.spacing.xxl

  signal closed()

  function open(initialWord) {
    if (initialWord !== undefined && initialWord !== null && String(initialWord) !== "")
      root.word = String(initialWord);
    root.statusText = "";
    root.opened = true;
    // Nothing to look up yet if it was summoned with an empty selection --
    // the field is focused and waiting instead, which is the "I want to
    // translate a word I am thinking of" case rofi_translator also allows.
    if (root.word !== "") root.lookup();
  }

  function close() {
    root.opened = false;
    root.busy = false;
    root.closed();
  }

  function toggle() { root.opened ? root.close() : root.open("") }
  function status() { return root.opened ? "open" : "closed" }

  // ---- lookup ----
  // One process, one JSON answer. See ati-translate-query for why the four
  // facts are gathered there rather than in four Processes here.
  // Absolute path, not the bare name. Every other script here reaches its
  // siblings through /usr/local/bin, which install.sh populates -- but a
  // script added since the last install run is simply not there, and from
  // QML that failure is invisible: the Process never produces output, so
  // onStreamFinished never fires and the popup sits on "translating…"
  // forever with nothing in any log. Measured exactly that way. The file is
  // always at this path whether or not anything has been installed.
  readonly property string queryBin:
    Quickshell.env("HOME") + "/.config/AtiScriptsV1/translate/ati-translate-query"

  function lookup() {
    if (root.word.trim() === "") return;
    root.busy = true;
    root.statusText = "translating…";
    queryProc.command = [root.queryBin, root.word, root.targetLang];
    queryProc.running = true;
    lookupTimeout.restart();
  }

  // Belt and braces for the above: trans itself can hang on a dead network
  // (its own timeout is generous), and a spinner with no end is the worst
  // possible outcome for a popup you opened to answer one question.
  Timer {
    id: lookupTimeout
    interval: 30000
    onTriggered: {
      if (!root.busy) return;
      queryProc.running = false;
      root.busy = false;
      root.statusText = "timed out — type a translation, or try again";
    }
  }

  Process {
    id: queryProc
    // Fires even when the command could not be run at all, which stdout's
    // onStreamFinished does not.
    onExited: (code, status) => {
      lookupTimeout.stop();
      if (root.busy) {
        root.busy = false;
        if (code !== 0) root.statusText = "translator failed (exit " + code + ")";
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        lookupTimeout.stop();
        root.busy = false;
        try {
          const d = JSON.parse(text);
          root.translation = String(d.translation || "");
          root.explanation = String(d.explanation || "");
          root.sentence = String(d.sentence || "");
          root.sourceLang = String(d.source || "");
          // An empty translation is a real outcome (both engines rate
          // limited, or no network) and must say so -- silently leaving the
          // old translation on screen next to a new word is worse than an
          // empty field, because it looks like an answer.
          root.statusText = root.translation === ""
            ? "no translation came back — type one, or try again"
            : (root.sourceLang !== "" ? root.sourceLang + " → " + root.targetLang : "");
        } catch (e) {
          root.statusText = "translator returned nothing usable";
        }
      }
    }
  }

  // ---- save ----
  // Straight into the same "### words" section rofi_translator writes, via
  // the same ati-todos-append, with the same --dedupe-prefix so looking a
  // word up twice replaces its entry instead of stacking a second copy.
  // The heredoc is built here rather than piping, because Process has no
  // stdin writer -- `printf ... | ati-todos-append` inside sh -c is the
  // shape that works.
  function save() {
    if (root.word.trim() === "") return;
    const langs = (root.sourceLang !== "" && root.sourceLang !== root.targetLang)
      ? root.sourceLang + " → " + root.targetLang : root.targetLang;
    // Every field is user-editable text heading for a shell command, so
    // each one is single-quoted and any embedded single quote is closed,
    // escaped and reopened ('\'') -- the standard shell-safe wrap. Nothing
    // here is interpolated into the command unquoted.
    const q = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";
    let body = "- **" + root.word + "**";
    if (root.translation !== "") body += " — " + root.translation;
    body += " *(" + langs + ")*\n";
    if (root.explanation !== "") body += "  - " + root.explanation + "\n";
    if (root.sentence !== "") body += "  - _" + root.sentence + "_\n";

    saveProc.command = ["sh", "-c",
      "printf '%s' " + q(body) + " | ati-todos-append words --dedupe-prefix " +
      q("- **" + root.word + "**")];
    saveProc.running = true;
    root.statusText = "saved to ### words";
    closeAfterSave.restart();
  }
  Process { id: saveProc }
  // Long enough to read the confirmation, short enough not to be in the way.
  Timer { id: closeAfterSave; interval: 700; onTriggered: root.close() }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "ati-translate"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive: the first thing you do here is type into a text field, so
    // the popup must own the keyboard outright. Same choice ati-clip makes.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      width: Math.min(root.cardMaxWidth,
                      Math.max(320, panel.width - Style.spacing.huge * 4))
      implicitHeight: card.contentTopInset + layout.implicitHeight + card.contentBottomInset
      height: implicitHeight
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      // Swallows the scrim's click-to-close for clicks on the card itself.
      MouseArea { anchors.fill: parent; onClicked: {} }

      // Esc closes from anywhere in the card, including from inside a text
      // field. Keys.forwardTo on the window would fire before the field
      // sees the key; this sits at the card level with BeforeItem priority
      // only for Escape, so ordinary typing is untouched.
      Keys.priority: Keys.BeforeItem
      Keys.onEscapePressed: root.close()

      // ---- THE INSET IS EXPLICIT, AND HAS TO BE ----
      //
      // BorderSurface's `padding` does NOT lay anything out -- it is a plain
      // Rectangle that only PUBLISHES the inset as contentTopInset/
      // contentLeftInset/... for the caller to anchor against. An
      // `anchors.fill: parent` therefore fills the whole card and ignores
      // the padding entirely, which is what put the title, the "Explanation"
      // label and the status row flat against the border with no margin at
      // all. Every other panel in this kit (Clipboard, Menu, PopupCard,
      // KeyboardPanel, ConfirmDialog) anchors to the four insets by hand for
      // this reason; so does this one now.
      Column {
        id: layout
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.xl

        // ---- title ----
        Text {
          text: "Translate"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        // ---- word + target language ----
        // One explicit row height, not Math.max of two controls that size
        // themselves differently -- a TextField sizes from font+padding and
        // a Dropdown from Style.spacing.controlHeight, so letting each pick
        // its own left them visibly mismatched at the top edge.
        Item {
          width: parent.width
          // Math.max, NOT a flat height. Forcing a height SMALLER than the
          // control's own implicitHeight clips its content, and Noto Sans
          // Arabic's line height at a given pixelSize is considerably taller
          // than Ubuntu's -- which is exactly why the Arabic came out cut off
          // along the bottom edge while the Latin above it was fine. Taking
          // the larger of the two keeps Latin rows aligned to one grid and
          // lets an Arabic row grow to whatever it actually needs.
          height: Math.max(root.fieldHeight, implicitHeight)

          TextField {
            id: wordField
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: parent.width - langDrop.width - Style.spacing.controlGap
            text: root.word
            placeholderText: "word or phrase"
            foreground: root.foreground
            font.family: root.familyFor(root.word)
            horizontalAlignment: root.isRtl(root.word) ? Text.AlignRight : Text.AlignLeft
            // onTextEdited, not onTextChanged: the latter also fires when
            // the binding below writes the field back after a lookup, which
            // would make every result overwrite root.word with itself and
            // fight the user's cursor position.
            onTextEdited: root.word = text
            onAccepted: root.lookup()
            // Focus lands here on open, so a summoned popup with an empty
            // selection is immediately typeable.
            focus: root.opened
          }

          Dropdown {
            id: langDrop
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            rowHeight: parent.height
            width: 150
            showLabel: false
            options: root.languages
            value: root.targetLang
            foreground: root.foreground
            onValueChanged: {
              if (value === root.targetLang) return;
              root.targetLang = value;
              // Changing the target language IS the request to re-translate.
              // Making you press a button afterwards would be a second step
              // for a choice that has exactly one meaning.
              root.lookup();
            }
          }
        }

        // ---- translation ----
        TextField {
          id: transField
          width: parent.width
          height: Math.max(root.fieldHeight, implicitHeight)
          text: root.translation
          placeholderText: root.busy ? "…" : "translation"
          foreground: root.foreground
          font.family: root.familyFor(root.translation)
          font.pixelSize: Style.font.subtitle
          horizontalAlignment: root.isRtl(root.translation) ? Text.AlignRight : Text.AlignLeft
          onTextEdited: root.translation = text
        }

        // ---- explanation ----
        Column {
          width: parent.width
          spacing: Style.spacing.sm
          Text {
            text: "Explanation"
            color: Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          TextField {
            width: parent.width
            text: root.explanation
            placeholderText: "what it means — type your own if blank"
            foreground: root.foreground
            font.family: root.familyFor(root.explanation)
            font.pixelSize: Style.font.bodySmall
            height: Math.max(root.fieldHeight, implicitHeight)
            horizontalAlignment: root.isRtl(root.explanation) ? Text.AlignRight : Text.AlignLeft
            onTextEdited: root.explanation = text
          }
        }

        // ---- example sentence ----
        Column {
          width: parent.width
          spacing: Style.spacing.sm
          Text {
            text: "Example sentence"
            color: Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          TextField {
            width: parent.width
            text: root.sentence
            placeholderText: "a sentence using it"
            foreground: root.foreground
            font.family: root.familyFor(root.sentence)
            font.pixelSize: Style.font.bodySmall
            height: Math.max(root.fieldHeight, implicitHeight)
            horizontalAlignment: root.isRtl(root.sentence) ? Text.AlignRight : Text.AlignLeft
            onTextEdited: root.sentence = text
          }
        }

        // ---- status + actions ----
        Item {
          width: parent.width
          height: Math.max(statusLabel.implicitHeight, actions.implicitHeight)

          Text {
            id: statusLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - actions.width - Style.spacing.controlGap
            text: root.statusText
            color: Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.controlGap

            Button {
              text: root.busy ? "…" : "Translate"
              // Idle Button is transparent/borderless by default (see
              // Ui/Button.qml) — invisible until hovered, reported as "add
              // button ui not good not visible" (also true of the Anki and
              // Todo popups' own action buttons, fixed there too).
              bordered: true
              // Same token issue Todo.qml's/Anki.qml's own buttons and
              // toggle switches hit: this theme's missing shell.toml means
              // Button's border/fill default to plain foreground, not
              // accent, so `bordered` alone was still grey.
              foreground: root.accent
              enabled: !root.busy
              onClicked: root.lookup()
            }
            Button {
              text: "Save to notes"
              bordered: true
              foreground: root.accent
              enabled: root.word.trim() !== ""
              onClicked: root.save()
            }
          }
        }
      }
    }
  }
}
