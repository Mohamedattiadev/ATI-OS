import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

//
// FORK: which keyboard layout is live, for the resting capsule's language
// readout. The island has never had one; the topbar has carried the same
// thing as a chip since it was built, and this is that logic in the shape
// the island's other non-visual trackers take (LayoutState,
// CompositorWorkspaceTracker) — its own component, so the 5,000-line window
// file does not own an eleventh concern.
//
// WHY IT IS NOT A SECOND COPY OF THE TOPBAR'S
// -------------------------------------------
// It is, and it has to be. Quickshell's QML scanner refuses a module path
// outside the config folder and does not follow a symlink past it, which is
// the measured fact NEXT-SESSION.md leads its four-processes section with —
// so the island's tree cannot import anything from the topbar's. The three
// tables below are therefore duplicated, and each says so, which is the same
// guard against drift that restingWorkspaceAllowance uses.
//
// EVENT-DRIVEN, WITH THE POLL AS A SAFETY NET
// -------------------------------------------
// The topbar's own note records the measurement: the poll command costs
// 32-41 ms and the poll INTERVAL was 3 s, so a layout chip that "visibly
// trails the keypress" was never slow, it was up to three seconds stale.
// Hyprland announces the change on its event socket, one line per keyboard
// device:
//
//     activelayout>>at-translated-set-2-keyboard,Arabic
//     activelayout>>keyd-virtual-keyboard,Turkish
//     activelayout>>video-bus,English (US)
//
// so the layout is taken from the event and the timer drops to a 30 s
// re-sync that only matters if an event is ever missed.
//
// HYPRLAND ONLY, AND DELIBERATELY SILENT ELSEWHERE
// ------------------------------------------------
// The island runs on X11 under qtile too (see IslandWindowX11.qml), where
// there is no event socket and `hyprctl` answers nothing. Rather than poll a
// binary that cannot answer, the whole tracker is gated on
// HYPRLAND_INSTANCE_SIGNATURE — under qtile it never loads, `layoutKey` stays
// at the default, and the readout it feeds draws nothing. That is the right
// degradation for a readout whose whole rule is "say nothing when there is
// nothing to say": qtile's own bar already has a KeyboardLayout widget, and a
// second one wired to a dead source would be worse than none.
//
Item {
    id: root

    visible: false
    width: 0
    height: 0

    // The layout KEY — "us", "ara", "tr", "de" — not the display name.
    // Everything downstream is keyed on it, which is the mistake the topbar's
    // header records making first: taking the first two characters of
    // Hyprland's "English (US)" gives "en", which matches nothing.
    property string layoutKey: "us"

    // The configured list, learned from the device rather than hardcoded, so
    // a machine with a different `kb_layout` still resolves.
    property var layoutKeys: ["us", "ara", "tr", "de"]

    // Which layouts count as "say nothing". A LIST and not `!== "us"`,
    // because the question is "is this the layout I type in by default", and
    // on a machine configured `gb,ara` the answer is `gb`.
    readonly property var silentKeys: ["us", "gb"]

    readonly property bool hyprlandSession:
        String(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "") !== ""

    // The substring each key is recognised BY inside Hyprland's display name.
    // Duplicated from the topbar's `layoutNameHints`, deliberately.
    readonly property var nameHints: ({
        "us": "english", "gb": "english", "ara": "arabic",
        "tr": "turkish", "de": "german", "fr": "french", "es": "spanish"
    })

    // The two letters drawn in the capsule. "GE" for German and not "DE" —
    // the user named the four as "TR, AR, EN, GE", and the readout is for
    // them to read rather than for xkb to parse. Anything not in the table
    // falls back to the key upper-cased, so an unlisted layout still says
    // something truthful instead of vanishing.
    readonly property var codes: ({
        "us": "EN", "gb": "EN", "ara": "AR", "tr": "TR", "de": "GE"
    })

    readonly property string code: codes[layoutKey] || layoutKey.toUpperCase()
    // The whole point of the feature: English says nothing.
    readonly property bool shown: silentKeys.indexOf(layoutKey) < 0 && code !== ""

    function keyForName(displayName) {
        const name = String(displayName).toLowerCase();
        for (let i = 0; i < root.layoutKeys.length; i++) {
            const key = root.layoutKeys[i];
            const hint = root.nameHints[key] || key;
            if (name.indexOf(hint) >= 0)
                return key;
        }
        return "";
    }

    Connections {
        target: root.hyprlandSession ? Hyprland : null

        function onRawEvent(event) {
            if (String(event.name) !== "activelayout")
                return;
            // "<device>,<Display Name>". A device name cannot contain a comma
            // but a display name can — "English (US, intl)" — so this splits
            // on the FIRST one only.
            const data = String(event.data || "");
            const at = data.indexOf(",");
            if (at < 0)
                return;
            const key = root.keyForName(data.substring(at + 1));
            if (key !== "")
                root.layoutKey = key;
        }
    }

    Process {
        id: probe
        command: ["sh", "-c",
            "hyprctl -j devices | python3 -c \"" +
            "import json,sys\n" +
            "d=json.load(sys.stdin)\n" +
            "ks=[k for k in d.get('keyboards',[]) if k.get('main')] or d.get('keyboards',[])\n" +
            "if not ks: sys.exit()\n" +
            "k=ks[0]\n" +
            "print((k.get('active_keymap') or '').strip())\n" +
            "print((k.get('layout') or 'us').strip())\n" +
            "\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const list = (lines[1] || "").trim();
                if (list !== "") {
                    const keys = list.split(",").map((x) => x.trim())
                        .filter((x) => x !== "");
                    if (keys.length > 0)
                        root.layoutKeys = keys;
                }
                // The list is read BEFORE the name is resolved against it,
                // because keyForName walks layoutKeys.
                const key = root.keyForName((lines[0] || "").trim());
                if (key !== "")
                    root.layoutKey = key;
            }
        }
    }

    Timer {
        interval: 30000
        running: root.hyprlandSession
        repeat: true
        triggeredOnStart: true
        onTriggered: probe.running = true
    }

    // ---- THE X11 HALF -------------------------------------------------------
    //
    // The header above says this tracker "never loads" under qtile and that
    // the right degradation is silence, because "qtile's own bar already has a
    // KeyboardLayout widget". That reasoning stopped holding the moment the
    // island BECAME qtile's bar: the widget it deferred to is hidden, so the
    // readout was simply gone rather than deferred.
    //
    // There is no device list to query here, but there is an authority: qtile
    // sets the layout itself, with `setxkbmap -layout <x>`, so it knows the
    // answer exactly. It writes it to this file on every switch and once at
    // startup -- see publish_keyboard_to_island() in qtile's config.py.
    //
    // A FILE, and pushed rather than polled, for the two reasons LayoutState
    // gives: a push tells you about a change while a widget needs the VALUE,
    // so an island restarted mid-session would otherwise draw nothing until
    // you next switched; and a language indicator that notices on a 30 s
    // re-sync is not worth drawing.
    //
    // This sets `layoutKey` directly rather than going through keyForName():
    // that function resolves Hyprland's DISPLAY name ("English (US)") against
    // nameHints, whereas what arrives here is already the key ("us", "ara").
    FileView {
        path: root.runtimeDir + "/hypr-layouts/keyboard"
        watchChanges: true
        preload: true
        // Absent until qtile has published once, which on a fresh boot may be
        // after the island starts. Not an error: layoutKey keeps its default
        // and the readout draws nothing, which is the same silence this
        // tracker has always used for "nothing to say".
        printErrors: false

        onLoaded: root.applyKeyboardFile(text())
        onFileChanged: {
            reload();
            root.applyKeyboardFile(text());
        }
    }

    function applyKeyboardFile(t) {
        // Trimmed for the reason LayoutState trims: the writer uses no
        // trailing newline today and a stray "\n" would match no key, so the
        // readout would silently vanish.
        const key = String(t).trim().toLowerCase();
        if (key !== "")
            root.layoutKey = key;
    }

    readonly property string runtimeDir: {
        const x = Quickshell.env("XDG_RUNTIME_DIR");
        return (x && String(x) !== "") ? String(x) : "/tmp";
    }
}
