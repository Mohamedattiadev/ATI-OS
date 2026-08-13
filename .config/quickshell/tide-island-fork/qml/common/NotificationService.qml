pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

//
// FORK — new file. The island SERVES org.freedesktop.Notifications now,
// instead of watching someone else serve it.
//
// ================= WHAT THIS REPLACES =================
//
// `SystemServices.notificationReceived(appName, summary, body)` — a spy
// signal on the session bus, three strings wide. It is not a server, and
// dunst was the real one, which is why upgread_UI_UX.md P0-1 could prove
// with a single `notify-send` that EVERY notification on this desktop was
// drawn twice: the island's capsule at top centre and dunst's card at top
// right, on the same frame, in two different design languages.
//
// That is worse than a duplicate. It means the island's notification
// design had never been in service — dunst's card is the one with the
// icon, the app name and the border, so dunst's card is the one the eye
// went to, and every hour spent on NotificationHistory.qml was invisible.
//
// ================= WHY THREE STRINGS WERE A DEAD END =================
//
// The spy signal carried no `id`, no `replaces_id`, no urgency, no
// actions, no image hints and no close signal. So even with dunst gone,
// the island could not have implemented dismiss, urgency styling, action
// buttons or replace-in-place — which is most of what a notification
// system IS. The missing pieces were not unwritten UI; they were
// unreachable through the interface being used.
//
// `NotificationServer` carries all of them, and replace-in-place comes
// free rather than as a feature: the server reuses the SAME Notification
// object for a `replaces_id`, so anything bound to that object updates
// itself. A progress notification from a file copy rewrites its own
// capsule instead of stacking twenty of them.
//
// ================= THE HAZARD, STATED PLAINLY =================
//
// Owning a well-known bus name is a one-owner job. If this server has a
// bug, notifications stop SYSTEM-WIDE and fail silently — the same shape
// of hazard as a polkit agent, which is why REQUIREMENTS.md item 1 ended
// with the polkit prompt being removed rather than finished.
//
// Two things follow, and both are deliberate:
//
//   * `keepOnReload: true`. Without it every config reload drops the bus
//     name and re-acquires it, and anything that arrived in the gap is
//     gone. With it the name survives a reload, which is the single most
//     common event in this repo's workflow.
//
//   * dunst stays INSTALLED. It comes out of autostart.conf only, so it
//     is one `dunst &` away at any time, and `submap-indicator.sh` already
//     depends on `dunstctl` — as does the control centre's Silent row,
//     which was rewritten onto it two commits before this one. Removing
//     the package would break both for no gain.
//
// Test both directions before trusting it: with the island running AND
// with it killed. A notification server that works only while the shell
// is up is a shell that eats your notifications when it crashes.
//
Singleton {
    id: root

    // Emitted for every notification the bus delivers. The parameter is a
    // live Notification object, not a copy — `summary`, `body`, `urgency`
    // and `actions` all change under it when the sender replaces it.
    signal posted(var notification)

    // Everything still on screen or in history, newest last. The server
    // owns the list; `tracked` below is what puts things into it.
    readonly property alias notifications: server.trackedNotifications

    NotificationServer {
        id: server

        // Survive a config reload without dropping the bus name. See the
        // hazard note above.
        keepOnReload: true

        // These are ADVERTISED CAPABILITIES, not preferences: they are
        // what `GetCapabilities` answers, and senders change what they
        // send based on the reply. Claiming a capability the UI does not
        // implement is therefore a way to receive markup nobody renders.
        //
        // So each one below is on because something downstream handles it:
        persistenceSupported: true    // history survives dismissal
        bodySupported: true
        bodyMarkupSupported: true     // Text.RichText in the capsule
        actionsSupported: true        // action buttons, invoked on click
        imageSupported: true          // image / appIcon in the icon slot

        // Off, and each for a reason rather than by omission:
        bodyHyperlinksSupported: false  // nothing opens a URL from a capsule
        bodyImagesSupported: false      // inline <img> in a 56 px capsule
        actionIconsSupported: false     // no icon set for them yet — P2-9
        inlineReplySupported: false     // needs a text field in the notch

        onNotification: function (notification) {
            // Tracked, or the object is destroyed the moment this handler
            // returns and every binding onto it becomes undefined — the
            // capsule would render an empty notification and nothing would
            // say why. This one line is what makes the object live long
            // enough to be shown, dismissed and kept in history.
            notification.tracked = true;
            root.posted(notification);
        }
    }
}
