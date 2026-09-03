// ati-anki — the same treatment the translate popup got, on the user's
// explicit request: "make also the anki thing like the one we created for a
// translator win p+e, i meant the ui and logic".
//
// WHAT THIS REPLACES, AND WHY IT IS A NEW SURFACE RATHER THAN A NEW SKIN
// ---------------------------------------------------------------------
// $mod P A used to run rofi_anki directly: eight sequential rofi prompts
// (front language, text, tags, three yes/no audio toggles, an image-URL
// prompt), one screen at a time, Escape-to-abort at every step. That is
// Translate.qml's own "read-only list" problem one level worse — not just
// no place to type, but no way to see or fix an earlier answer once a later
// prompt is on screen. This is the Translate.qml shape instead: one card,
// every field visible and editable together, exactly what Save sends.
//
// THE CARD LOGIC IS NOT REIMPLEMENTED HERE
// -----------------------------------------
// rofi_anki already grew an `--answers FILE` mode for the island's rofi-less
// picker (hypr/scripts/island-picker.py, menu `anki`) — see that script's
// own header. Everything past "the eight answers are known" — the
// AnkiConnect handshake, deck provisioning, Gemini/translate-shell
// fallback, IPA, three flavours of TTS, the image fetch, HTML assembly and
// addNote — is ~200 lines that have nothing to do with which window asked
// the questions, and there is now a THIRD caller for the same JSON
// contract (rofi's own prompts, the island's picker, and this). One copy
// of the card logic, three ways to fill in the same seven keys.
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

  // The editable fields. rofi_anki's own `answer()` keys, held here so
  // Save always sends exactly what the card shows.
  property string text: ""
  property string frontLang: "en"
  property string tags: ""
  property bool voiceNormal: false
  property bool voiceRepeat: false
  property bool voiceSpell: false
  property string imageUrl: ""
  property string statusText: ""

  // ---- preview: translation/synonyms/examples, fetched automatically ----
  //
  // "should add the word with its translation, example etc auto when i
  // click" — rofi_anki always computed these on submit (Gemini if a key
  // is set, translate-shell otherwise), they just never reached the
  // screen: the card went straight to Anki with the front text as the
  // only thing anyone saw. `editingFinished` (Enter OR clicking away —
  // literally "when i click") on the text field now runs the SAME lookup
  // early, through the SAME two functions rofi_anki's own submission
  // uses (see that script's `--preview` flag), so what is shown here and
  // what lands on the card cannot disagree.
  property string previewTranslation: ""
  property string previewSynonyms: ""
  // Newline-separated in the UI, one example per line — split back into
  // an array only when building the submit payload.
  property string previewExamples: ""
  property string previewIpa: ""
  property bool previewBusy: false
  // False until a preview has actually completed once. submit() only
  // sends translation/synonyms/examples when this is true — otherwise
  // rofi_anki falls back to computing them itself exactly as it always
  // did, rather than submitting three empty fields because the popup
  // was closed before the lookup came back.
  property bool previewDone: false

  readonly property var langs: [
    { value: "en", label: "en · English → German" },
    { value: "de", label: "de · German → English" }
  ]

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color scrim: Color.menu.scrim
  readonly property color accent: Color.accent
  readonly property var borderSpec: Border.localOrSurfaceSpec(
    "menu", "border", Color.menu.border, Color.menu.border, Style.normalBorderWidth)

  function familyFor(t) { return isRtl(t) ? "Noto Sans Arabic" : Style.font.family }
  function isRtl(t) { return /[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF\u0590-\u05FF]/.test(String(t || "")); }

  readonly property int fieldHeight:
    Math.max(Style.spacing.controlHeight, Math.round(Style.font.subtitle * 2.4))

  readonly property int cardMaxWidth: 560
  readonly property int contentMargin: Style.spacing.xxl

  signal closed()

  function open(initialText) {
    if (initialText !== undefined && initialText !== null && String(initialText) !== "")
      root.text = String(initialText);
    root.statusText = "";
    root.previewTranslation = "";
    root.previewSynonyms = "";
    root.previewExamples = "";
    root.previewIpa = "";
    root.previewDone = false;
    root.opened = true;
    // ati-anki-popup's own selection hand-off means a card is
    // frequently opened with the front field already full — preview it
    // immediately rather than waiting for a click that may not come
    // (Save is reachable without ever touching the text field again).
    if (root.text.trim() !== "") root.preview();
  }

  function close() {
    root.opened = false;
    root.busy = false;
    root.closed();
  }

  function toggle() { root.opened ? root.close() : root.open("") }
  function status() { return root.opened ? "open" : "closed" }

  // ---- submit ----
  // Absolute path, not the bare name — same reasoning as Translate.qml's
  // queryBin: a script added since the last install run has no symlink on
  // PATH yet, and from QML that failure is invisible (the Process never
  // produces output, so the popup just sits there). The file is always at
  // this path whether or not install.sh has run since.
  readonly property string ankiBin:
    Quickshell.env("HOME") + "/.config/AtiScriptsV1/menu/rofi_anki"

  // Same runtime dir rofi_anki's own answers file lives in
  // (ati-rofi-common.sh's ROFI_RUNTIME_DIR): XDG_RUNTIME_DIR, falling back
  // to /tmp on a session that somehow has neither.
  readonly property string answersPath:
    (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ati-anki-answers.json"

  // ---- preview ----
  // Same absolute-path reasoning as ankiBin above.
  function preview() {
    if (root.text.trim() === "") return;
    root.previewBusy = true;
    const payload = { front_lang: root.frontLang, text: root.text };
    const q = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";
    previewProc.command = ["sh", "-c",
      "printf '%s' " + q(JSON.stringify(payload)) + " > " + q(root.previewPath) +
      " && " + q(root.ankiBin) + " --preview " + q(root.previewPath)];
    previewProc.running = true;
  }

  readonly property string previewPath:
    (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ati-anki-preview.json"

  Process {
    id: previewProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.previewBusy = false;
        try {
          const d = JSON.parse(text);
          root.previewTranslation = String(d.translation || "");
          root.previewSynonyms = Array.isArray(d.synonyms) ? d.synonyms.join(", ") : "";
          root.previewExamples = Array.isArray(d.examples) ? d.examples.join(" | ") : "";
          root.previewIpa = String(d.ipa || "");
          root.previewDone = true;
        } catch (e) {
          // Leaves the fields as they were rather than blanking a preview
          // that already succeeded once — a transient failure (network,
          // Gemini rate limit) should not erase the last good answer.
        }
      }
    }
  }

  function submit() {
    if (root.text.trim() === "") { root.statusText = "nothing to add"; return; }
    root.busy = true;
    root.statusText = "adding to Anki…";

    const answers = {
      front_lang: root.frontLang,
      text: root.text,
      tags: root.tags,
      voice_normal: root.voiceNormal ? "yes" : "no",
      voice_repeat: root.voiceRepeat ? "yes" : "no",
      voice_spell: root.voiceSpell ? "yes" : "no",
      image_url: root.imageUrl
    };
    // Only when a preview actually completed — see previewDone's own
    // comment. rofi_anki treats "translation" key present (even "") as
    // "use exactly this", so an incomplete preview must never add the
    // key at all, not add it empty.
    if (root.previewDone) {
      answers.translation = root.previewTranslation;
      answers.synonyms = root.previewSynonyms.split(",").map((s) => s.trim()).filter((s) => s !== "");
      answers.examples = root.previewExamples.split("|").map((s) => s.trim()).filter((s) => s !== "");
    }
    // Single-quoted and closed/escaped/reopened for any embedded quote,
    // same shell-safe wrap Translate.qml's save() uses — the JSON is
    // itself built from arbitrary user text (front/tags/URL) heading for
    // a shell command line.
    const q = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";
    submitProc.command = ["sh", "-c",
      "printf '%s' " + q(JSON.stringify(answers)) + " > " + q(root.answersPath) +
      " && " + q(root.ankiBin) + " --answers " + q(root.answersPath)];
    submitProc.running = true;
  }

  Process {
    id: submitProc
    onExited: (code, status) => {
      root.busy = false;
      if (code === 0) {
        root.statusText = "added — closing…";
        closeAfterSave.restart();
      } else {
        // rofi_anki already notify-sends the specific reason (AnkiConnect
        // unreachable, missing note type, TTS engine absent…) — this just
        // keeps the card open so the fields are not lost on a failure.
        root.statusText = "failed (exit " + code + ") — see notification, card kept";
      }
    }
  }
  Timer { id: closeAfterSave; interval: 700; onTriggered: root.close() }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "ati-anki"
    WlrLayershell.layer: WlrLayer.Overlay
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

      MouseArea { anchors.fill: parent; onClicked: {} }

      Keys.priority: Keys.BeforeItem
      Keys.onEscapePressed: root.close()

      Column {
        id: layout
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.xl

        Text {
          text: "Anki card"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        // ---- text + front language ----
        Item {
          width: parent.width
          height: Math.max(root.fieldHeight, implicitHeight)

          TextField {
            id: textField
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: parent.width - langDrop.width - Style.spacing.controlGap
            text: root.text
            placeholderText: "word or sentence (front)"
            foreground: root.foreground
            font.family: root.familyFor(root.text)
            horizontalAlignment: root.isRtl(root.text) ? Text.AlignRight : Text.AlignLeft
            onTextEdited: { root.text = text; root.previewDone = false; }
            // Return OR clicking away — Qt's own `editingFinished`, which
            // is literally "when i click" (away from the field). Covers
            // Enter too, so there is no separate onAccepted handler.
            onEditingFinished: root.preview()
            focus: root.opened
          }

          Dropdown {
            id: langDrop
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            rowHeight: parent.height
            width: 190
            showLabel: false
            options: root.langs
            value: root.frontLang
            foreground: root.foreground
            // The front language changes which language the preview
            // translates OUT of, so it changes the answer — same "changing
            // this IS the request to re-run" call Translate.qml's own
            // language dropdown makes.
            onValueChanged: { root.frontLang = value; if (root.text.trim() !== "") root.preview(); }
          }
        }

        // ---- translation preview (auto-filled, editable) ----
        Column {
          width: parent.width
          spacing: Style.spacing.sm
          Text {
            text: root.previewBusy ? "Translation — looking up…" : "Translation"
            color: Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          TextField {
            width: parent.width
            text: root.previewTranslation
            placeholderText: root.previewBusy ? "…" : "auto-filled — click away from the word above"
            foreground: root.foreground
            font.family: root.familyFor(root.previewTranslation)
            font.pixelSize: Style.font.subtitle
            height: Math.max(root.fieldHeight, implicitHeight)
            horizontalAlignment: root.isRtl(root.previewTranslation) ? Text.AlignRight : Text.AlignLeft
            onTextEdited: root.previewTranslation = text
          }
        }

        // ---- synonyms + examples preview (auto-filled, editable) ----
        Column {
          width: parent.width
          spacing: Style.spacing.sm
          // Two Text elements, not one string concatenated onto the
          // "Synonyms" caption — a caption Text has no width bound (the
          // Column doesn't clip), so a long IPA transcription (a run-on
          // sentence's worth of espeak output, not just one word's) ran
          // straight past the card's edge and off the screen. Capped
          // separately so it elides instead.
          Text {
            text: "Synonyms"
            color: Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Text {
            visible: root.previewIpa !== ""
            width: parent.width
            text: "/" + root.previewIpa + "/"
            color: Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            maximumLineCount: 1
          }
          TextField {
            width: parent.width
            text: root.previewSynonyms
            placeholderText: "comma separated — filled by the lookup above, editable"
            foreground: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            height: Math.max(root.fieldHeight, implicitHeight)
            onTextEdited: root.previewSynonyms = text
          }
        }

        Column {
          width: parent.width
          spacing: Style.spacing.sm
          Text {
            text: "Examples"
            color: Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          TextField {
            // Pipe-separated rather than one-per-line: this kit's TextField
            // is Qt Quick Controls' single-line control (no wrapMode, no
            // multi-line text) — matching Style with a genuine multi-line
            // TextArea across the whole kit is its own build, not a field
            // on this card.
            width: parent.width
            text: root.previewExamples
            placeholderText: "example sentences, separated by | — filled by the lookup above, editable"
            foreground: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            height: Math.max(root.fieldHeight, implicitHeight)
            onTextEdited: root.previewExamples = text
          }
        }

        // ---- tags ----
        Column {
          width: parent.width
          spacing: Style.spacing.sm
          Text {
            text: "Tags"
            color: Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          TextField {
            width: parent.width
            text: root.tags
            placeholderText: "space separated — optional"
            foreground: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            height: Math.max(root.fieldHeight, implicitHeight)
            onTextEdited: root.tags = text
          }
        }

        // ---- image URL ----
        Column {
          width: parent.width
          spacing: Style.spacing.sm
          Text {
            text: "Image URL"
            color: Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          TextField {
            width: parent.width
            text: root.imageUrl
            placeholderText: "https://… — optional"
            foreground: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            height: Math.max(root.fieldHeight, implicitHeight)
            onTextEdited: root.imageUrl = text
          }
        }

        // ---- audio toggles ----
        Row {
          width: parent.width
          spacing: Style.spacing.xxl

          Row {
            spacing: Style.spacing.sm
            ToggleSwitch { id: swNormal; checked: root.voiceNormal; foreground: root.accent; onToggled: root.voiceNormal = !root.voiceNormal }
            Text { text: "Word once"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: swNormal.verticalCenter }
          }
          Row {
            spacing: Style.spacing.sm
            ToggleSwitch { id: swRepeat; checked: root.voiceRepeat; foreground: root.accent; onToggled: root.voiceRepeat = !root.voiceRepeat }
            Text { text: "Word ×3"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: swRepeat.verticalCenter }
          }
          Row {
            spacing: Style.spacing.sm
            ToggleSwitch { id: swSpell; checked: root.voiceSpell; foreground: root.accent; onToggled: root.voiceSpell = !root.voiceSpell }
            Text { text: "Spelling"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: swSpell.verticalCenter }
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
              text: root.busy ? "…" : "Add to Anki"
              // Idle Button is transparent/borderless by default — see
              // Ui/Button.qml's state table. Without `bordered` this reads
              // as unlabeled floating text until hovered, reported as
              // "add button ui not good not visible" (also true of
              // Translate.qml's two buttons, fixed there for the same
              // reason).
              bordered: true
              // Same token issue as the audio toggle switches above: this
              // theme's missing shell.toml means Button's border/fill also
              // default to plain foreground, not accent — see Todo.qml's
              // own copy of this comment for the full reasoning.
              foreground: root.accent
              enabled: !root.busy && root.text.trim() !== ""
              onClicked: root.submit()
            }
          }
        }
      }
    }
  }
}
