import QtQuick
import Quickshell
import Quickshell.Widgets

// ProgressRing lives here — the shared ring the countdown and the volume OSD
// draw, and now the focus ring too. Importing the DIRECTORY, not the file: a
// QML component is reached through its module path, and only the two .js
// helpers below are imported by filename.
import "../common"
import "../common/Metrics.js" as Metrics
import "../common/Motion.js" as Motion

//
// FORK — new file. One APP ICON per open window, in the empty bar beside
// the notch: the first window left, the second right, the third left again.
// The focused one wears a thin accent ring; see the delegate for why that
// is the only ring left, and what three earlier designs got wrong.
//
// WHY ALTERNATING AND NOT "ALL ON ONE SIDE"
// -----------------------------------------
// Asked for directly — two terminals should read as one ring on each flank.
// It also happens to be the only split that keeps the island symmetric
// without needing to know anything about the windows: any rule that sorts
// by workspace, or by app, or by age makes the two sides different lengths
// and the notch stops sitting in the middle of its own furniture.
//
// The parity is on the INDEX in the source list, and this component filters
// for its own side rather than being handed a pre-split array. Two strips
// reading the same list with opposite parity cannot disagree; two arrays
// built by a parent can, and the failure is a window that appears on both
// sides or on neither.
//
// WHERE THE LIST COMES FROM
// -------------------------
// Quickshell.Wayland's ToplevelManager, not `hyprctl clients`. It is the
// foreign-toplevel protocol, so it is live — an ObjectModel that updates on
// open/close with no polling — and it carries appId and title directly.
//
// Measured caveat, because it cost a probe to find: ToplevelManager reports
// ZERO toplevels until the shell owns a real surface. A ShellRoot with no
// PanelWindow gets an empty list forever and no warning, which reads exactly
// like "this compositor does not support the protocol". The island has
// surfaces, so this is only a trap for the throwaway instance you test in.
//
// NOT INTERACTIVE: the island's input Region is mainCapsule's rectangle
// alone, so everything out here is drawn and unclickable. A ring you could
// click would need the mask widened, and a full-width clickable strip at the
// top of the screen eats desktop clicks for the whole session.
//
Item {
    id: root

    // Array of { appId, title, active }.
    property var windows: []
    // "left" takes the even indices, "right" the odd ones.
    property string side: "left"
    property real revealProgress: 1
    property bool showCondition: true
    property string textFontFamily: ""
    property color accentColor: "#51afef"

    readonly property int parity: side === "left" ? 0 : 1

    readonly property var mine: {
        const picked = [];
        const source = windows || [];
        for (let index = 0; index < source.length; index++) {
            if (index % 2 === parity)
                picked.push(source[index]);
        }
        // The left strip grows AWAY from the notch, so its first window has
        // to sit nearest the pill — that is the right-hand end of a Row.
        // Reversing here rather than mirroring the layout keeps the ring
        // contents upright; LayoutMirroring would flip the glyphs too.
        return side === "left" ? picked.reverse() : picked;
    }

    implicitWidth: strip.implicitWidth
    implicitHeight: Metrics.px(26)

    opacity: showCondition ? revealProgress : 0
    visible: opacity > 0.01 && mine.length > 0

    Behavior on opacity {
        NumberAnimation {
            duration: root.showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()
        }
    }

    // ---- APP ID -> ICON, AND WHY THE CHAIN HAS FIVE LINKS ----
    //
    // Measured against the seven windows actually open when this was
    // written, because a chain built from one example is a chain with one
    // link. `Quickshell.iconPath(id, true)` — the `true` is `check`, so a
    // miss returns "" rather than a broken image — resolved only THREE of
    // the seven on the appId alone:
    //
    //   kitty                        -> image://icon/kitty      (exact)
    //   pcmanfm-qt                   -> image://icon/pcmanfm-qt (exact)
    //   org.qutebrowser.qutebrowser  -> ""  but the trailing segment
    //                                   "qutebrowser" resolves
    //   brave-browser                -> ""  but brave-browser.desktop
    //                                   exists and carries Icon=brave-desktop
    //   scratch-term1 / scratch-term2 / sum-md -> "" and always will
    //
    // Hence: exact, then lowercased, then the trailing dotted segment (the
    // reverse-DNS case), then the desktop entry's own Icon= key (the brave
    // case — the icon is named nothing like the app), then the alias map.
    //
    // THE ALIAS MAP IS NOT A HACK, IT IS THE ONLY TRUTHFUL ANSWER for those
    // last three. They are kitty windows launched with `--class` to make
    // them addressable as scratchpads — verified by reading `comm` off each
    // window's pid, all three are `kitty`. There is no desktop entry and no
    // icon named `sum-md` anywhere on the system, and there never will be,
    // because the name is this user's own. Showing kitty's icon is not a
    // guess about what they might be; it is what they are.
    readonly property var appIdAliases: ({
        "scratch-term1": "kitty",
        "scratch-term2": "kitty",
        "sum-md": "kitty"
    })

    function iconFor(appId) {
        const raw = String(appId || "").trim();
        if (raw === "")
            return "";

        const aliased = root.appIdAliases[raw] || root.appIdAliases[raw.toLowerCase()] || raw;

        const direct = Quickshell.iconPath(aliased, true);
        if (direct)
            return direct;

        const lowered = Quickshell.iconPath(aliased.toLowerCase(), true);
        if (lowered)
            return lowered;

        const segments = aliased.split(".");
        if (segments.length > 1) {
            const tail = Quickshell.iconPath(segments[segments.length - 1].toLowerCase(), true);
            if (tail)
                return tail;
        }

        // Scanning DesktopEntries.applications rather than calling
        // heuristicLookup: in a throwaway probe instance heuristicLookup
        // returned null for EVERY id including kitty's, and the entry list
        // was length 0, so the helper could not be told apart from an
        // unpopulated singleton. The launcher reads .applications.values
        // and demonstrably works, so this reads the same thing.
        const entries = (DesktopEntries && DesktopEntries.applications)
            ? DesktopEntries.applications.values : [];
        const wanted = aliased.toLowerCase();
        for (let index = 0; index < entries.length; index++) {
            const entry = entries[index];
            if (!entry || !entry.icon)
                continue;
            const entryId = String(entry.id || "").toLowerCase().replace(/\.desktop$/, "");
            if (entryId !== wanted)
                continue;
            const viaEntry = Quickshell.iconPath(entry.icon, true);
            if (viaEntry)
                return viaEntry;
        }

        return "";
    }

    // Last resort only, and it should now be unreachable for every window
    // this machine actually opens. Kept because the alternative to a letter
    // is a blank gap in the strip, which reads as a bug rather than as an
    // unknown app.
    function initialFor(appId) {
        const text = String(appId || "?").replace(/^org\./, "");
        return text.length ? text.charAt(0).toUpperCase() : "?";
    }

    Row {
        id: strip
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.px(5)

        Repeater {
            model: root.mine

            // ---- REAL APP ICONS, AND A RING ONLY ON THE FOCUSED ONE ----
            //
            // Three designs were rejected here before this one, and the
            // record matters because the fourth was nearly a fourth guess:
            //
            //   1. bordered Rectangle circles with a letter — "reads as
            //      buttons"
            //   2. ProgressRing with showCore true — the dark core disc
            //      filled the hole and they read as "coins"
            //   3. ProgressRing with showCore false, 26 px, lineWidth 2.5,
            //      per-app hue in the track at 0.45 alpha, full arc for the
            //      focused window — "still not good looking"
            //
            // The diagnosis that ended it: all three differed only in how
            // the ring was stroked, and the constant across all three was a
            // coloured ring wrapped around a SINGLE LETTER derived from the
            // appId. An initial is what an avatar falls back to when it has
            // no picture, so it always reads as a fallback — no amount of
            // ring tuning was going to fix a thing that was wrong inside the
            // ring. The per-app hue was part of the same mistake: it existed
            // only to tell one letter from another.
            //
            // So the letter is gone, and with it the reason for seven
            // coloured rings. The ring survives as exactly one ring — around
            // the FOCUSED window — which is the single fact the strip needs
            // to carry and now the only ornament on it. Chosen by the user
            // from ASCII previews rather than by building a fourth version
            // and asking.
            //
            // ---- AND THAT RING IS ProgressRing, NOT A BORDERED Rectangle ----
            //
            // The first icon version drew the focus ring as a Rectangle with
            // radius width/2 and a flat 1.5 px border, and it was rejected on
            // sight: "if they were like the clock timer one it will be
            // better". That ring is qml/common/ProgressRing.qml as the
            // display panel's countdown draws it — DisplayPanel.qml:832 —
            // and its look does not come from being round, it comes from a
            // faint TRACK circle with a full-strength ARC laid over it in
            // round caps. A plain border has neither, which is why a shape
            // with the same diameter and the same colour still read as a
            // different object.
            //
            // Copied from that countdown exactly, not approximated:
            // lineWidth 2.5, showCore FALSE, and a track that is the same
            // colour as the fill at a fifth alpha (#33ffcc66 over #ffcc66).
            // showCore stays off for the same reason it is off there — the
            // core disc is what made version 2 read as coins, and here it
            // would sit behind the app icon.
            //
            // The one deliberate departure: this ring is drawn ONLY on the
            // focused window, so unfocused icons stay bare. Putting a faint
            // track on all seven would be closer to the countdown still, but
            // it walks straight back into the seven-rings look that was
            // rejected three times.
            delegate: Item {
                required property var modelData

                readonly property bool isActive: !!modelData.active
                readonly property string iconSource: root.iconFor(modelData.appId)

                // The outer box is the FOCUS RING's size and never changes,
                // so nothing in the Row shifts when focus moves — only the
                // ring's opacity does. Sizing the item to the icon and
                // growing it for the ring would make the whole strip twitch
                // sideways on every alt-tab.
                width: Metrics.px(26)
                height: width

                ProgressRing {
                    anchors.fill: parent
                    lineWidth: 2.5
                    showCore: false
                    fillColor: root.accentColor
                    trackColor: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                        root.accentColor.b, 0.20)
                    // A window has no 0..1 quantity to show, so the arc
                    // carries the one binary fact: focused sweeps the whole
                    // circle. Animating progress rather than snapping it
                    // makes the ring DRAW ITSELF round on focus, which is
                    // the countdown's own motion played forwards.
                    progress: parent.isActive ? 1 : 0
                    opacity: parent.isActive ? 1 : 0

                    Behavior on progress {
                        NumberAnimation {
                            duration: Motion.morphDuration()
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.spring()
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.morphDuration()
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.spring()
                        }
                    }
                }

                IconImage {
                    id: appIcon
                    anchors.centerIn: parent
                    // Inside the ring with a clear gap: the ring is the
                    // outer 26 with a 2.5 px stroke, this is 15, so ~3 px of
                    // air on each side. Butting the icon against the stroke
                    // was how version 1 turned into a button.
                    width: Metrics.px(15)
                    height: width
                    source: parent.iconSource
                    visible: parent.iconSource !== ""
                    asynchronous: true
                }

                Text {
                    anchors.centerIn: parent
                    visible: parent.iconSource === ""
                    text: root.initialFor(modelData.appId)
                    color: root.accentColor
                    font.pixelSize: Metrics.font(9)
                    font.family: root.textFontFamily
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
