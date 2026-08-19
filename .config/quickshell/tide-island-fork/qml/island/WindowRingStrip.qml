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

    // Array of { appId, toplevel }. Deliberately does NOT carry focus or
    // title — see the note at openWindows in DynamicIslandWindow.qml.
    property var windows: []
    // The focused toplevel, passed separately so a focus change updates one
    // binding instead of rebuilding the whole model and every delegate.
    property var activeToplevel: null
    // "left" takes the even indices, "right" the odd ones.
    property string side: "left"
    property real revealProgress: 1
    property bool showCondition: true
    property string textFontFamily: ""
    property color accentColor: IslandTheme.accent

    // ---- THE DROP PLAYS ONCE, NOT ON EVERY REBUILD ----
    //
    // Reported as the animation repeating. The cause is not the animation: it
    // is that `windows` is rebuilt whenever the toplevel set OR THE FOCUS
    // changes, so the Repeater tears its delegates down and builds new ones,
    // and a fresh delegate has no idea it is replacing one that had already
    // landed. Every alt-tab re-dropped the whole row.
    //
    // So "has this strip already dropped" is state on the STRIP, which
    // survives delegate churn, rather than on the delegates that are being
    // destroyed. A delegate created after the drop has finished starts at 1
    // and animates nothing.
    //
    // Re-armed only when the strip actually leaves the screen, so the drop
    // still plays when the island reveals itself again. That is the one time
    // it should: the icons are genuinely arriving then.
    property bool dropDone: false
    onShowConditionChanged: if (!showCondition) dropDone = false
    // FORK: the disc behind each icon. IslandTheme.shellFill, passed down, so
    // the plate re-tints with theme-apply like the capsule does instead of
    // being a hardcoded black that follows nothing.
    property color plateColor: IslandTheme.surface

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
    implicitHeight: Metrics.px(32)

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

    // ---- THE DROP: EACH ICON FALLS OUT OF THE ISLAND ----
    //
    // Asked for as "like when you drop water" — the circles should come FROM
    // the island to their position rather than simply being there.
    //
    // A droplet has three readable parts, and the third is the one that sells
    // it: it starts small and concentrated at the source, it travels, and it
    // ARRIVES SLIGHTLY TOO FAR and settles back. That last part is why this
    // uses Motion.spring() and nothing else in this file does — spring is
    // zeta 0.8, underdamped, so it overshoots by design. Everywhere else in
    // this shell that overshoot has been a bug (a clamped 0..1 progress read
    // as a throb, see the arc below), but here it IS the effect: it is the
    // difference between a drop landing and a card sliding into place.
    //
    // The travel is expressed as a horizontal OFFSET toward the notch, not as
    // an absolute start position. The strip does not know where the pill is —
    // it is placed by DynamicIslandWindow, which anchors the left strip's
    // right edge and the right strip's left edge to the pill. So "toward the
    // island" is simply +x for the left strip and -x for the right one, and
    // collapsing the whole strip to the pill edge is the same motion for
    // both sides without either needing the capsule's geometry.
    //
    // STAGGERED, because simultaneity is what makes an animation read as a
    // panel appearing rather than as objects arriving. The icon nearest the
    // notch leads and the outer ones follow, so the sequence reads outward
    // from the island — which is the direction the water is travelling. The
    // Row is built nearest-first for the left strip already (`mine` reverses
    // it), so the model index IS the distance rank on both sides.
    // Latches the drop closed once the last icon has had time to land, so
    // every delegate built after this point skips the animation entirely.
    Timer {
        interval: 55 * Math.max(0, (root.mine ? root.mine.length : 0)) + Motion.morphDuration()
        running: root.showCondition && !root.dropDone && root.mine && root.mine.length > 0
        repeat: false
        onTriggered: root.dropDone = true
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
            // ---- AND NOW EVERY ICON WEARS ONE ----
            //
            // The previous version drew the ring on the FOCUSED window only,
            // on the reasoning that a faint track on all seven walks back
            // into the seven-rings look rejected three times. Asked to put
            // the countdown's ring on the apps and the workspace chip alike,
            // so that reasoning is overruled — and it was wrong in a way
            // worth recording. What was rejected three times was seven rings
            // each in a DIFFERENT per-app hue, competing with each other and
            // with a letter inside. Seven tracks in one accent at a fifth
            // alpha is not that: they read as a set of identical sockets,
            // and the eye goes to the single one with a full arc in it.
            //
            // So the track is on every icon and the arc still marks exactly
            // one. That is also what the countdown actually looks like — its
            // track is always drawn, and only the arc moves.
            delegate: Item {
                // Named, because the icon and the ring both need to read the
                // delegate's own properties and they now sit at different
                // depths: the ring is a child of this Item, the icon is a
                // child of the RING. A bare `parent` would mean two different
                // things in the two places, which is how `winCell.iconSource`
                // silently became undefined once the icon moved inward.
                id: winCell
                required property var modelData
                required property int index

                // 0 while pooled at the island, 1 once landed. A delegate
                // built after the strip has already dropped starts landed —
                // see dropDone on the root.
                property real drop: root.dropDone ? 1 : 0

                // Toward the notch: the left strip's icons pull right, the
                // right strip's pull left. 28 px is a little over the icon's
                // own diameter, which is enough for the eye to read it as
                // travel rather than as a nudge.
                transform: Translate {
                    x: (1 - winCell.drop) * (root.side === "left"
                        ? Metrics.px(28) : -Metrics.px(28))
                }

                // Small at the source and full size on landing, with the
                // scale riding the same 0..1 as the travel so the two cannot
                // drift apart. 0.35 rather than 0 because a dot growing from
                // nothing reads as a pop; a droplet already has volume when
                // it leaves.
                scale: 0.35 + winCell.drop * 0.65
                opacity: winCell.drop

                Behavior on drop {
                    NumberAnimation {
                        duration: Motion.morphDuration()
                        easing.type: Easing.BezierSpline
                        // The one deliberate spring in this file. See the
                        // note on the Row: the overshoot is the drop.
                        easing.bezierCurve: Motion.spring()
                    }
                }

                Timer {
                    // 55 ms apart. Below about 40 the stagger stops being
                    // legible and the row reads as one block; above about 80
                    // the last icon arrives late enough to look like a
                    // separate event.
                    interval: 55 * winCell.index
                    running: !root.dropDone
                    repeat: false
                    onTriggered: winCell.drop = 1
                }

                // ---- IDENTITY, EXCEPT ON X11 WHERE IT CANNOT HOLD ----
                //
                // Measured: on X11, `id=81788942` shows up in BOTH modelData
                // and root.activeToplevel at once and still comes out
                // `active=false`. EwmhState.decorate() builds a brand new JS
                // object per window on EVERY feed frame — even for a window
                // nothing changed about — because it has no cache keyed on
                // window id. `windows` (this delegate's model) and
                // `activeToplevel` (a separate property on the strip) are two
                // independently-dirtied bindings over that same churn, and a
                // title updating mid-frame (any kitty prompt does this
                // constantly) is enough for the Repeater to still be holding
                // a modelData built from an older decorate() call than the
                // one activeToplevel has already moved on to. Same window,
                // two objects, never ===.
                //
                // Wayland's ToplevelHandle has no problem here — it is one
                // real object per surface, handed out by ToplevelManager and
                // never rebuilt — so identity is correct and kept for it.
                // EWMH's decorated objects carry a stable `.id` (the X window
                // id) precisely because the two-way EwmhState fields were
                // already designed to survive being rebuilt; falling back to
                // it only when both sides HAVE one keeps this a no-op on
                // Wayland, where toplevel handles carry no such property.
                readonly property bool isActive: modelData.toplevel !== null
                    && root.activeToplevel !== null
                    && (modelData.toplevel === root.activeToplevel
                        || (modelData.toplevel.id !== undefined
                            && root.activeToplevel.id !== undefined
                            && modelData.toplevel.id === root.activeToplevel.id))
                readonly property string iconSource: root.iconFor(modelData.appId)

                // The outer box is the FOCUS RING's size and never changes,
                // so nothing in the Row shifts when focus moves — only the
                // ring's opacity does. Sizing the item to the icon and
                // growing it for the ring would make the whole strip twitch
                // sideways on every alt-tab.
                // 32, measured off the timer ring beside the notch: its
                // amber circle is 32 px across, these were 26. Same size and
                // same centre line is what makes them one family.
                width: Metrics.px(32)
                height: width

                // The timer's disc: black, and the FULL diameter of the
                // ring rather than a smaller inset circle.
                Rectangle {
                    id: iconPlate
                    anchors.fill: parent
                    radius: width / 2
                    color: root.plateColor
                }

                ProgressRing {
                    anchors.fill: parent
                    // ---- THESE ARE OsdLayer'S NUMBERS, NOT THE COUNTDOWN'S ----
                    //
                    // Three attempts here copied DisplayPanel's countdown
                    // ring. Wrong ring. The one actually meant is the one
                    // that appears beside the notch when the island splits on
                    // a volume or brightness change - OsdLayer.qml around
                    // line 107 - and it differs in every way that matters:
                    //
                    //   countdown        OSD ring
                    //   lineWidth 2.5    lineWidth 4
                    //   showCore false   showCore TRUE  (dark disc)
                    //   accent fill      WHITE fill, white track at 0.16
                    //
                    // The core disc is the whole difference. The countdown is
                    // hollow because it sits on an already-dark panel, so a
                    // disc would fight the digit inside it. Out here the
                    // rings sit on the WALLPAPER, and a hollow ring leaves
                    // each icon floating on whatever happens to be behind it
                    // - which over a busy photo is exactly why these read as
                    // bad no matter how the stroke was tuned. The OSD ring
                    // brings its own dark plate, and the glyph sits ON it.
                    //
                    // White rather than accent for the same reason OsdLayer
                    // is white: it is the only colour that holds against 22
                    // palettes and any wallpaper. The accent moves to the
                    // ARC, which is the one thing that has to mean something.
                    // ---- 4 -> 2. THE STROKE IS AN ACCENT, NOT A FRAME ----
                    //
                    // 4 px came from the timer, where it is right: that ring
                    // IS the element, a gauge you read the sweep of. Here the
                    // ring is not the element — the icon is — and the stroke
                    // only has to say "this one has focus". At 4 px on a 32 px
                    // disc it was a seventh of the diameter, which frames the
                    // icon rather than marking it, and a frame around a small
                    // picture always reads as heavier than it measures.
                    //
                    // 2 px still separates cleanly at this size (the OSD ring
                    // reads as a ring at 3.5 on a much larger circle) while
                    // leaving the icon as the thing you look at.
                    lineWidth: Metrics.px(2)
                    // ---- THE DISC IS A SIBLING, BECAUSE showCore IS TOO SMALL ----
                    //
                    // Measured off the timer in a screenshot: its ring is
                    // 32 px across and its BLACK DISC is 36 - the disc fills
                    // the whole circle and then some. ProgressRing's own core
                    // is `min(width,height) * 0.54`, about 17 px at this
                    // size, so showCore left each icon on a small disc with a
                    // ring of bare WALLPAPER between the disc and the stroke.
                    // That gap is what still read as wrong after the border
                    // came off, and no icon size could have fixed it.
                    //
                    // So the disc is drawn full-size underneath (see
                    // `iconPlate` below) and showCore stays off.
                    showCore: false
                    fillColor: root.accentColor
                    // ---- TWO TRACK ALPHAS, AND THE REASON IS MEASURED ----
                    //
                    // The countdown's track is a flat fifth alpha, and
                    // copying that number verbatim was wrong here: at 0.20
                    // over a bright wallpaper the unfocused tracks were
                    // invisible on screen — the icons sat in nothing and only
                    // the focused ring existed, which is the design this was
                    // meant to replace. Confirmed at 9x against a pale sky.
                    //
                    // This file's FIRST version already knew it and said so:
                    // "that ring sits on a dark panel and these sit on the
                    // wallpaper, where a fifth-alpha stroke stops being a
                    // stroke." That note was dropped when the rings were
                    // rebuilt around icons, and the bug came straight back.
                    //
                    // So 0.45 unfocused, to survive any wallpaper, and 0.20
                    // focused — where the full-strength arc is laid over the
                    // track and a heavy track would fight it.
                    // ---- TWO TRACK ALPHAS, AND THE REASON IS MEASURED ----
                    //
                    // The countdown's track is a flat fifth alpha, and
                    // copying that number verbatim is wrong out here: at 0.20
                    // over a bright wallpaper an unfocused track is invisible.
                    // This file's FIRST version already knew it and said so —
                    // "that ring sits on a dark panel and these sit on the
                    // wallpaper, where a fifth-alpha stroke stops being a
                    // stroke" — and the note was lost when the rings were
                    // rebuilt around icons.
                    //
                    // 0.45 unfocused, to survive any wallpaper; 0.20 focused,
                    // where the full-strength arc lies over the track and a
                    // heavy track would fight it.
// ---- THE TIMER'S TRACK IS OPAQUE, AND THAT IS THE POINT ----
                    //
                    // Five attempts here copied the wrong ring: first
                    // DisplayPanel's countdown, then OsdLayer's. The ring
                    // actually meant is the TIMER's, in
                    // ExpandedPlayerLayer.qml around line 817, and its paint
                    // call is short enough to quote:
                    //
                    //     lineWidth = 5, lineCap round
                    //     strokeStyle "#2b2e35"  -> full circle  (track)
                    //     strokeStyle "#ff9f0a"  -> arc          (elapsed)
                    //
                    // The track is a SOLID OPAQUE COLOUR. Every version of
                    // this strip used a translucent one — accent at 0.20,
                    // then accent at 0.45, then white at 0.16 — and a
                    // translucent stroke over a photograph is not a stroke,
                    // it is a tint of whatever is behind it. That is why the
                    // rings kept reading as faint and wrong however the
                    // alpha was tuned: the problem was never which alpha, it
                    // was that there was an alpha at all.
                    //
// ---- NO BORDER. THE BACKGROUND IS THE ELEMENT ----
                    //
                    // The track is transparent: nothing is stroked around an
                    // unfocused icon at all.
                    //
                    // Every earlier version drew one - accent at 0.20, then
                    // 0.45, then white at 0.16, then the timer's opaque
                    // #2b2e35 - and the last was closest and still wrong.
                    // Putting both in one screenshot shows why: the timer is
                    // a SOLID BLACK DISC carrying a single thin bright ring.
                    // Copying its track colour onto every icon gave each one
                    // a heavy grey border instead, so the strip read as a row
                    // of bordered buttons, which is precisely the complaint
                    // the very first version got, reached from the opposite
                    // direction.
                    //
                    // What carries these is the dark disc BEHIND the icon,
                    // not an outline around it. The disc stays, the border
                    // goes, and the stroke is left to mean the only thing it
                    // should: the accent arc on the focused window, the way
                    // the timer's amber arc marks the timer.
                    trackColor: "transparent"
                    // A window has no 0..1 quantity to show, so the arc
                    // carries the one binary fact: focused sweeps the whole
                    // circle. Animating progress rather than snapping it
                    // makes the ring DRAW ITSELF round on focus, which is
                    // the countdown's own motion played forwards.
                    // No opacity gate any more: the track is always on, so
                    // an unfocused icon sits in a visible socket and the
                    // strip keeps its rhythm whichever window has focus.
                    progress: winCell.isActive ? 1 : 0

                    // ---- fade(), NOT spring(). THIS IS THE "GLOW" BUG ----
                    //
                    // Reported as the focused icon's ring glowing up and
                    // down. It is not a glow and nothing is pulsing: the
                    // spring curve is zeta 0.8, deliberately UNDERDAMPED, so
                    // progress overshoots 1 on the way in. ProgressRing
                    // clamps to 1, which hides the overshoot itself, but the
                    // spring's return dips BACK BELOW 1 before settling - so
                    // the arc closes, retracts a sliver, then closes again.
                    // Read as a throb, and it is really the ring being drawn
                    // one and a bit times.
                    //
                    // Motion.js already states the rule this broke, at the
                    // top of the file: spring (zeta 0.8) for GEOMETRY, fade
                    // (zeta 1.0, critically damped) for opacity and colour,
                    // and "using spring on an opacity Behavior is a real bug,
                    // not a taste choice". Progress is not geometry either -
                    // it is a 0..1 amount with a hard ceiling, and any
                    // overshoot on it is visible as a bounce rather than as
                    // mass. fade() reaches 1 and stops.
                    // NO Behavior. The arc snaps.
                    //
                    // This animated twice and glitched both times: first on
                    // Motion.spring(), whose overshoot on a clamped 0..1 read
                    // as a throb, then on Motion.fade(), which still showed a
                    // glitch because the model rebuilds on every focus change
                    // and the delegate carrying the animation is destroyed
                    // mid-flight. An animation that is routinely interrupted
                    // by the destruction of the thing running it cannot be
                    // made smooth by choosing a better curve.
                    //
                    // Focus is instantaneous in fact, so it is now
                    // instantaneous on screen. Asked for directly after two
                    // failed attempts to animate it well.

                    // ---- THE ICON GOES IN THE RING'S OWN CENTRE SLOT ----
                    //
                    // It used to be a SIBLING of the ring, centred by its own
                    // `anchors.centerIn: parent` on the delegate. That is one
                    // centring too many: the ring paints its circle on a
                    // Canvas that is sized to min(width, height) and centred
                    // in ITS box, while the icon centred itself in the
                    // delegate's box. The two boxes agree only when
                    // everything is exactly square and unrounded.
                    //
                    // HONESTY NOTE, because this repo keeps wrong theories.
                    // The change was made after reading a 10x screenshot as
                    // "the icons sit ~2.5 px below their rings". That reading
                    // was WRONG. Measured properly afterwards - masking the
                    // accent stroke and the icon's own colour and taking both
                    // centroids - it comes out dx -0.8 px, dy -0.2 px, i.e.
                    // concentric to well under a pixel, and the sibling
                    // layout it replaced was concentric too. The apparent
                    // offset was the blur of a NEAREST upscale over a busy
                    // wallpaper, plus a colour mask that caught blue
                    // wallpaper pixels and dragged the ring's centroid.
                    //
                    // The change is kept anyway, on the narrower ground that
                    // one centring beats two: the icon can no longer disagree
                    // with the ring under a future size change, because it is
                    // not positioned independently any more.
                    //
                    // ProgressRing already has a `default property alias
                    // centerContent` — a slot it positions itself, concentric
                    // with the circle it draws, sized to 0.62 of the ring.
                    // That slot exists precisely so a caller can put a glyph
                    // or a number in the middle without knowing where the
                    // middle is; the countdown puts its seconds there. Using
                    // it means the icon cannot disagree with the ring,
                    // because it is no longer being positioned independently.
                    // ---- CLIPPED TO A CIRCLE ----
                    //
                    // The core disc gives every icon a dark plate, but a
                    // themed icon that is itself an opaque SQUARE covers that
                    // plate completely and reads as a tile sitting in a ring
                    // instead of a badge. kitty's is exactly this: a solid
                    // maroon square. Circular ones like brave's already
                    // looked right, which is why the strip read as a mixed
                    // set rather than a family.
                    //
                    // ClippingRectangle with radius = width/2, the same
                    // component the wallpaper picker and the workspace
                    // overview already use for their thumbnails, so every
                    // icon becomes the same disc whatever shape it shipped
                    // as, concentric with the ring around it.
                    ClippingRectangle {
                        anchors.centerIn: parent
                        width: appIcon.width
                        height: width
                        radius: width / 2
                        color: "transparent"

                    IconImage {
                        id: appIcon
                        anchors.centerIn: parent
                        // ---- SIZED OFF THE DIAGONAL, NOT THE WIDTH ----
                        //
                        // Was 15, reasoned as "26 minus the stroke minus a few px
                        // of air". Right sum, wrong shape. The countdown ring
                        // this copies holds a NUMBER, and a digit is narrow, so
                        // its width is what must clear the stroke. An app icon is
                        // a SQUARE, and what must clear the stroke is its
                        // DIAGONAL.
                        //
                        // The arithmetic, which is why the icons read as sitting
                        // wrong rather than merely tight: a 26 px ring with a
                        // 2.5 px stroke leaves an inner circle about 21 px
                        // across. A 15 px square has a diagonal of 15 * 1.414 =
                        // 21.2 px. All four corners therefore landed exactly ON
                        // the stroke - each icon was inscribed in its ring rather
                        // than sitting inside it, touching at four points.
                        //
                        // 13 px gives an 18.4 px diagonal against that same 21 px
                        // inner circle: ~1.3 px of clearance at the corners, so
                        // the ring closes around the icon the way it closes
                        // around the countdown's digits.
                            // The timer's glyph inks 8 x 11 px inside a 32 px
                        // ring: about a third of the diameter, so roughly
                        // 10.5 px of clear disc on each side. 13 px here left
                        // only 9.5 and read as cramped. 11 px is that same
                        // ratio at this diameter - the padding asked for,
                        // taken off the measurement rather than nudged.
                        width: Metrics.px(11)
                        height: width
                        source: winCell.iconSource
                        visible: winCell.iconSource !== ""
                        asynchronous: true
                    }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: winCell.iconSource === ""
                        text: root.initialFor(modelData.appId)
                        color: root.accentColor
                        font.pixelSize: Metrics.font(9)
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                    }
                }

                // ---- THE RING WAS DECORATION ONLY ----
                //
                // Reported as "the win chip, when I open something, not
                // works". It was not a broken click — there was NO CLICK.
                // This file was 681 lines with no MouseArea in it at all: the
                // strip drew which windows exist and which one has focus, and
                // did nothing when you pressed one.
                //
                // That is the worst shape a control can have. It looks like a
                // button, it lights the focused one, it sits where a window
                // switcher sits, and pressing it is indistinguishable from
                // pressing a dead key.
                //
                // LAST CHILD of winCell on purpose, so it is above the ring
                // and the icon; a MouseArea declared earlier would be under
                // them and would still take the press, but the z-order is
                // what makes that true by construction rather than by luck.
                MouseArea {
                    anchors.fill: parent
                    // The whole cell, not just the icon: the icon is 32 px
                    // inside a cell with padding, and a target you have to hit
                    // precisely is a target you miss.
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (event) => {
                        const t = winCell.modelData ? winCell.modelData.toplevel : null;
                        if (!t)
                            return;
                        if (event.button === Qt.MiddleButton) {
                            // Middle closes, which is what a taskbar entry
                            // does everywhere else. Left alone otherwise —
                            // there is no confirmation here and there should
                            // not be one on a left click.
                            if (t.close)
                                t.close();
                            return;
                        }
                        // activate() rather than a `focuswindow` dispatch:
                        // the toplevel object is what the strip already holds,
                        // so this cannot address the wrong window the way an
                        // appId or a title match can when two windows share
                        // one — which is the case this strip is FOR.
                        t.activate();
                    }
                }
            }

        }
    }
}
