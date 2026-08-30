// The little square that appears beside the pointer when you highlight a
// word. Click it and the translate popup opens on that word.
//
// "i want it without clicking on the keymaps i want a small square appers
// near the cursor when i hover any word ok and when i click it appers got
// it? like the google translation extenetion"
//
// WHAT "HOVER" CAN ACTUALLY MEAN HERE, AND WHY THIS IS NOT A COMPROMISE
// --------------------------------------------------------------------
// No Wayland client can read the word under the pointer in another app --
// that is the security model, not a missing feature, and no amount of work
// gets around it. But the Google extension people picture does not read what
// you hover either: it watches what you SELECT, and puts its icon beside the
// selection. That behaviour is fully reachable here, because a selection is
// published -- the PRIMARY selection is a Wayland protocol, and highlighting
// a word IS setting it.
//
// So: highlight a word (which is the same gesture you already make), and the
// square appears at the pointer. No keybind, no menu, nothing to remember.
//
// IT MUST NEVER TAKE THE KEYBOARD
// -------------------------------
// This window can appear while you are mid-sentence in an editor, because
// selecting text is something you do constantly and not always to translate.
// WlrKeyboardFocus.None is therefore not a detail -- a badge that grabbed
// focus on every selection would eat keystrokes several times a minute and
// would be the single most disruptive thing on the desktop. It is
// click-only, and clicking is the only way it does anything at all.
//
// It also gets out of the way by itself: it fades after a few seconds, and
// a new selection replaces it rather than stacking a second one.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: badge

  // The word this badge is offering to translate.
  property string word: ""
  property bool shown: false
  property int cursorX: 0
  property int cursorY: 0

  // The disc itself. The WINDOW is larger (see `pad`) so the shadow has
  // somewhere to fall -- a layer-shell surface clips to its own size, so a
  // shadow drawn at the disc's exact bounds is simply not rendered.
  readonly property int boxSize: 21
  readonly property int pad: 4
  // Down and to the right of the pointer, the way every selection affordance
  // sits -- far enough not to be under the cursor itself (which would make
  // it flicker as you finish dragging a selection), close enough to read as
  // belonging to it.
  readonly property int offsetX: 12
  readonly property int offsetY: 14

  signal requested(string word)

  function show(w, x, y) {
    if (String(w).trim() === "") return;
    badge.word = String(w);
    badge.cursorX = x;
    badge.cursorY = y;
    badge.shown = true;
    hideTimer.interval = badge.idleMs;
    hideTimer.restart();
  }

  function hide() {
    badge.shown = false;
    hideTimer.stop();
  }

  // ---- THE BADGE ALWAYS GOES AWAY. HOVER EXTENDS, IT NEVER DISABLES. ----
  //
  // This used to be `onEntered: hideTimer.stop()`, which is the obvious way
  // to stop it vanishing from under the pointer on the way to a click -- and
  // it is why the badge sometimes never disappeared at all. Stopping the
  // timer makes `onExited` the ONLY thing that can restart it, and on a
  // 21px always-on-top layer surface that leave event is not guaranteed: the
  // pointer can leave the output, a fullscreen client can take the pointer,
  // the surface can be hidden and reshown under a stationary cursor. Any of
  // those strands the badge on screen with nothing left to dismiss it.
  //
  // So every state sets a BOUNDED interval and restarts. Hovering buys a
  // generous grace period rather than an indefinite one, and the badge is
  // guaranteed to clear itself no matter which events do or do not arrive.
  readonly property int idleMs: 4000    // shown, not touched
  readonly property int hoverMs: 12000  // pointer is on it -- plenty to click
  readonly property int leaveMs: 900    // pointer left -- go soon, not instantly

  Timer {
    id: hideTimer
    interval: badge.idleMs
    onTriggered: badge.hide()
  }

  PanelWindow {
    id: win
    visible: badge.shown
    color: "transparent"
    WlrLayershell.namespace: "ati-translate-badge"
    WlrLayershell.layer: WlrLayer.Overlay
    // See the header. Never, under any circumstance, Exclusive here.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Anchored to two edges and sized to the box, so the window IS the
    // badge: a full-screen transparent window would swallow pointer events
    // across the whole desktop even with nothing drawn, which on an Overlay
    // layer means the desktop stops responding to the mouse.
    anchors { top: true; left: true }
    implicitWidth: badge.boxSize + badge.pad * 2
    implicitHeight: badge.boxSize + badge.pad * 2

    // Clamped to the screen, or a selection made near the right or bottom
    // edge puts the badge half off it.
    margins.left: Math.max(0, Math.min(badge.cursorX + badge.offsetX - badge.pad,
                                       (screen ? screen.width : 1920) - implicitWidth))
    margins.top: Math.max(0, Math.min(badge.cursorY + badge.offsetY - badge.pad,
                                      (screen ? screen.height : 1080) - implicitHeight))

    // ---- THE MARK ----
    //
    // First version was an outlined dark square with a Nerd Font
    // `nf-fa-language` glyph in it, and it read badly: at 22px that glyph is
    // a tiny letter INSIDE a drawn box, so the badge was a box within a box,
    // and the outline-on-dark gave it almost no separation from whatever
    // text it was floating over.
    //
    // A FILLED circle instead. Filled, because this is a button you are
    // meant to click and the strongest signal for that is a solid shape with
    // its symbol reversed out of it -- the same reason Google's own is a
    // solid disc. Circular, because it cannot then be mistaken for one of
    // the desktop's own square chrome elements at a glance.
    //
    // 文 rather than an icon-font glyph, and that is a font-safety decision
    // as much as a design one: "Symbols Nerd Font" is NOT installed on this
    // machine (fc-match falls back to Noto Sans CJK, silently), so every
    // Nerd glyph here only renders because Qt happens to find a patched font
    // per-character. U+6587 is in Noto Sans CJK JP, which IS installed and
    // IS named correctly, so this one mark is the only thing on the badge
    // that cannot silently become a hex box.
    // ---- SHADOW ----
    // Three stacked discs at falling opacity rather than a blur shader: at
    // 28px a real Gaussian is indistinguishable from this and costs a
    // render target on a surface that sits above everything else on screen.
    // Each ring is 2px wider than the one above it and a third as opaque,
    // which reads as a soft edge.
    Repeater {
      model: 3
      Rectangle {
        required property int index
        width: badge.boxSize + (index + 1) * 2
        height: width
        radius: width / 2
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2 + 1
        color: "#000000"
        opacity: 0.16 / (index + 1)
      }
    }

    Rectangle {
      id: box
      width: badge.boxSize
      height: badge.boxSize
      radius: width / 2
      anchors.centerIn: parent
      // Dark disc with an accent RING and an accent glyph, not a solid
      // accent disc with the glyph reversed out. The bar's own chrome is
      // exactly this -- a dark chip with an accent border -- so the badge
      // now reads as part of the same desktop instead of as a warning dot
      // dropped on top of it. It also stops fighting whatever is behind it:
      // a saturated fill competes with page content, a dark one recedes.
      color: mouse.containsMouse ? Qt.lighter(Color.popups.background, 1.4)
                                 : Color.popups.background
      Behavior on color { ColorAnimation { duration: 120 } }

      // The ring is the accent now, and it is what makes the badge legible
      // at all against a dark page -- the disc itself is nearly the same
      // value as most editors' backgrounds, so the outline carries the
      // shape.
      border.width: 1
      border.color: Color.accent

      scale: mouse.containsMouse ? 1.12 : 1.0
      Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

      Text {
        anchors.centerIn: parent
        // md-translate. THE FAMILY NAME MATTERS MORE THAN THE CODEPOINT.
        //
        // "Symbols Nerd Font" is not installed here -- fc-match falls back
        // to Noto Sans CJK, silently -- which is why the topbar has been
        // bitten twice by 5-hex-digit Supplementary-PUA glyphs rendering as
        // hex boxes. Named against a family that actually exists
        // (`fc-match "JetBrainsMono Nerd Font"` resolves to itself) this
        // codepoint IS present: checked directly in the installed
        // JetBrainsMono/FiraMono cmaps.
        //
        // So this is the real Material "translate" mark rather than
        // fa-language's letter-in-a-box, which read as a box inside a box,
        // or 文, which is a Chinese character standing in for the idea.
        // String.fromCodePoint, NOT a "\uF05CA" literal. JavaScript's \u
        // escape takes EXACTLY four hex digits, so that string is \uF05C
        // followed by a literal "A" -- a different glyph and a stray letter,
        // with no error anywhere. U+F05CA is above the BMP and needs the
        // surrogate pair this builds.
        text: String.fromCodePoint(0xF05CA)
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: Math.round(badge.boxSize * 0.62)
        color: Color.accent
        renderType: Text.NativeRendering
      }

      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          badge.requested(badge.word);
          badge.hide();
        }
        // Extend, never stop. See the note on the timer above for why this
        // is the difference between "waits for you" and "never goes away".
        onEntered: { hideTimer.interval = badge.hoverMs; hideTimer.restart() }
        onExited: { hideTimer.interval = badge.leaveMs; hideTimer.restart() }
      }
    }
  }
}
