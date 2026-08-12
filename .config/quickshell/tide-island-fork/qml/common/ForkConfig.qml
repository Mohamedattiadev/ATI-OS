import QtQuick
import Quickshell
import Quickshell.Io

//
// FORK — new file. The settings the PACKAGED backend has never heard of.
//
// WHY THERE ARE TWO CONFIG OBJECTS
// --------------------------------
// `UserConfig` is `IslandBackend`'s compiled UserConfigBackend, and it reads
// the same file this does — ~/.config/tide-island/userconfig.json. It is
// authoritative for the 39 properties it registers (counted out of
// /usr/lib/qt6/qml/IslandBackend/IslandBackend.qmltypes) and it is BLIND to
// everything else: a key it has no property for is simply not exposed to
// QML. There is no way to add one without recompiling the package.
//
// Everything this fork added is in that blind spot. Notch mode, the chord
// HUD, the resting EQ, the theme reveal, the polkit prompt — none of them
// exist upstream, so none of them can have a backend property, so they were
// all hardcoded literals in QML (`property bool notchModeEnabled: true`).
// That is fine right up until someone wants to turn one off, at which point
// the only interface is a text editor and a hot reload.
//
// So the fork's own keys live in the SAME file under a `fork` prefix, and
// this object reads them. The two readers do not conflict: unknown keys are
// inert to UserConfigBackend (verified — the packaged config app has already
// rewritten this file once and every `_key` annotation and every unknown key
// came through), and the `fork` prefix means a future upstream key cannot
// collide with one of ours by accident.
//
// WATCHED, NOT READ ONCE
// ----------------------
// hypr/scripts/island-settings.py writes the file and this notices, so a
// toggle in the settings panel takes effect on the next frame rather than on
// the next shell restart. It is also why that script writes through
// os.replace: a truncate-then-write would give this watcher a real chance to
// parse a half-written file, which is the failure IslandTheme.qml documents
// from the other side.
//
// An invisible Item, not a QtObject, and that is load-bearing for the same
// reason IslandTheme.qml says it is: a FileView declared as the value of a
// property on a bare QtObject constructs happily, reports no error, and
// never fires onLoaded or onFileChanged. The shell then silently keeps its
// defaults and looks exactly like "the settings are not wired up".
//
Item {
    id: root

    visible: false
    width: 0
    height: 0

    // ---- THE DEFAULTS ARE THE PRE-SETTINGS BEHAVIOUR, EXACTLY ----
    //
    // Every one of these is what the corresponding hardcoded literal was
    // before this file existed, so a machine with no `fork*` keys in its
    // config — which is every machine until the panel is used once — behaves
    // identically to the fork before the settings state was added. A default
    // that "improved" something here would be a silent behaviour change
    // shipped under the name of a config file.
    //
    // The exception, and it is deliberate: forkPolkitAgentEnabled defaults
    // FALSE, and there is no prior behaviour it is matching because the
    // island has never been the polkit agent. Default-off is the only safe
    // default for a switch whose failure mode is "no password prompt appears
    // anywhere on the system and nothing says why". See PolkitPromptLayer.qml.
    property bool notchMode: true
    property bool modeKeysEnabled: true
    property bool restingEqEnabled: true
    property bool themeTransitionEnabled: true
    property bool polkitAgentEnabled: false

    // The volume/brightness OSD as a separate circular ring in the middle of
    // the screen, instead of the island's split capsule. Defaults FALSE for
    // the same reason every other switch here defaults to current behaviour:
    // a config file that does not mention it must leave the shell exactly as
    // it was. See qml/osd/RingOsdWindow.qml.
    property bool ringOsdEnabled: false

    // True once the file has been read at all. Distinguishes "the defaults,
    // because there is no config" from "the defaults, because that is what
    // the config says" — which matters for the polkit switch, where the two
    // are the same value and only one of them is a decision.
    property bool loaded: false

    function boolAt(parsed, key, fallback) {
        if (!parsed || parsed[key] === undefined)
            return fallback;
        // Tolerant of the string forms, because this file is edited by hand
        // as well as by island-settings.py, and `"forkNotchMode": "false"`
        // being read as TRUE (a non-empty string is truthy in JS) is the
        // kind of wrong that looks like the setting being ignored.
        const value = parsed[key];
        if (typeof value === "string")
            return value === "true" || value === "1" || value === "yes";
        return value === true;
    }

    function applyJson(text) {
        try {
            const parsed = JSON.parse(text);
            root.notchMode = root.boolAt(parsed, "forkNotchMode", true);
            root.modeKeysEnabled = root.boolAt(parsed, "forkModeKeysEnabled", true);
            root.restingEqEnabled = root.boolAt(parsed, "forkRestingEqEnabled", true);
            root.themeTransitionEnabled = root.boolAt(parsed, "forkThemeTransitionEnabled", true);
            root.polkitAgentEnabled = root.boolAt(parsed, "forkPolkitAgentEnabled", false);
            root.ringOsdEnabled = root.boolAt(parsed, "forkRingOsdEnabled", false);
            root.loaded = true;
        } catch (error) {
            // Keep whatever is already loaded, and do NOT set `loaded`. A
            // half-written or corrupt config must not be able to flip the
            // polkit switch in either direction — the writer renames the file
            // into place atomically so this should be unreachable, and it is
            // here because "should be" is not a guarantee about a file
            // another process writes.
        }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/tide-island/userconfig.json"
        watchChanges: true
        // Preloaded: `notchMode` decides the island's resting SHAPE, and a
        // shell that drew the floating pill for one frame and then snapped
        // to the notch would be a visible flicker on every start.
        preload: true
        printErrors: false

        onLoaded: root.applyJson(text())
        onFileChanged: {
            reload();
            root.applyJson(text());
        }
    }
}
