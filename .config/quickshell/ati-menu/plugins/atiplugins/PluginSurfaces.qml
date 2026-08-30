pragma ComponentBehavior: Bound

import QtQml
import QtQuick
import Quickshell
import Quickshell.Io

//
// ARCHITECTURE.md Phase 3, the fifth and last load point: "bar / popups — a
// Loader per */qml/, wrapped so a failure is contained".
//
// WHY IT LIVES IN ati-menu AND NOT IN A BAR
// ------------------------------------------
// §4 calls this surface "bar / popups", and the obvious reading is "put it
// in the bar". Two things argue against that, and both are already written
// down elsewhere in this repo:
//
//   * There are TWO bars. `bar-switch` stops one to start the other
//     (ati-bar-action's header explains what that costs), so a plugin
//     hosted by the bar would exist in native mode and vanish in island
//     mode, or have to be implemented twice and kept in step.
//   * shell.qml's own header: Quickshell keys its IPC socket and instance by
//     CONFIG PATH, so this process crashing "can never take the bar down
//     with it". Rule 4 of §3 — "a plugin whose QML fails to load is skipped;
//     it must not take the bar down. This is non-negotiable: the bar is the
//     desktop" — is satisfied at the PROCESS level here, not merely by a
//     try/catch. That is a stronger guarantee than a Loader inside the bar
//     could ever give.
//
// ati-menu is exec-once'd unconditionally in autostart.conf, "regardless of
// which bar the session picks", so a plugin surface hosted here is up in
// both modes and outlives a bar switch.
//
// THE CONTRACT A PLUGIN GETS
// --------------------------
// `qml/main.qml` is instantiated exactly once, with no parent and no
// implicit window. A plugin that wants to draw declares its own
// PanelWindow/PopupWindow inside it; a plugin that only wants to run logic
// declares none. Nothing is injected into either bar's layout — there is no
// layout contract to inject into yet, and inventing one here would be
// designing the bar's plugin API by accident, in the commit that was meant
// to prove the loader.
//
Item {
    id: root

    // Written by `ati-plugin sync`; absent until a plugin with a qml/ is
    // installed, which is the shipped state and not a fault.
    property string manifestPath: Quickshell.env("HOME") + "/.cache/ati-plugins/qml.json"
    property var entries: []

    FileView {
        id: manifest
        path: root.manifestPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.entries = Array.isArray(parsed) ? parsed : [];
            } catch (e) {
                // A corrupt manifest is ati-plugin's bug, not the desktop's
                // emergency: drop every plugin surface and keep the shell.
                console.warn("[ati-plugin] could not parse " + root.manifestPath + ": " + e);
                root.entries = [];
            }
        }
        onLoadFailed: root.entries = []
        onFileChanged: reload()
    }

    // Instantiator, not Repeater: a Repeater delegate has to be an Item, and
    // a plugin's root is allowed to be a window or a bare QtObject. This
    // instantiates whatever the plugin declared, parented to nothing.
    Instantiator {
        model: root.entries

        delegate: Loader {
            id: surface
            required property var modelData

            // Asynchronous so a slow or heavy plugin cannot stall the menu's
            // own startup — the shell must be answering its IPC toggle
            // whether or not somebody's plugin is still compiling.
            asynchronous: true
            source: "file://" + surface.modelData.path

            onStatusChanged: {
                if (surface.status === Loader.Error)
                    console.warn("[ati-plugin] " + surface.modelData.name
                                 + ": qml/main.qml failed to load — skipped");
                else if (surface.status === Loader.Ready)
                    console.info("[ati-plugin] " + surface.modelData.name + ": qml loaded");
            }
        }
    }
}
