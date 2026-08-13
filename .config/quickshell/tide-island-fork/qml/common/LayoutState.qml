import QtQuick
import Quickshell
import Quickshell.Io

//
// FORK — new file. The current Hyprland "layout", as layout-cycle.sh means
// the word, published for the island's resting indicator.
//
// WHY IT EXISTS
// -------------
// hypr/scripts/layout-cycle.sh has carried the gap in its own comment since
// it was written: "qtile's bar had a CurrentLayout widget, so switching
// layouts always said what you switched to. The island has no such widget."
// Its stand-in was a transient showText popup on change only. This is the
// state half of giving the island a real one.
//
// WHY A FILE AND NOT AN IPC PUSH
// ------------------------------
// A push tells you about a CHANGE; a widget needs the VALUE. Every path that
// would have to push -- the $mod Tab cycle, the per-workspace `apply` that
// workspace-layout.sh fires on every switch, and the island simply starting
// up after both -- reduces to "read the current value", and a file already
// holds it. An island restarted mid-session would have missed every push and
// would draw nothing until the next layout change.
//
// WHY A SEPARATE COMPONENT
// ------------------------
// The obvious home is DynamicIslandWindow.qml, which owns the resting
// content. That file is 5,039 lines and does not import Quickshell.Io at
// all; upgread_UI_UX.md's P2-7 is specifically about it, and about the six
// raw Loaders that survived a 46-site sweep because nobody can hold it in
// view at once. Adding a file watcher and a glyph table to it makes that
// worse for no gain. qml/common/ already holds exactly this shape of thing
// -- ForkConfig, NotificationService.
//
// THE FileView IS AN ORDINARY CHILD, NOT A PROPERTY VALUE
// -------------------------------------------------------
// ForkConfig.qml's header records the trap and it applies here unchanged: a
// FileView declared as the value of a property never fires onLoaded or
// onFileChanged, so the shell silently keeps whatever it read first -- with
// nothing in the log. It has to be a child in the default property.
//
Item {
    id: root

    // The raw word layout-cycle.sh writes: monadtall | max | treetab.
    // Empty until the first read, which is a real state and is drawn as
    // nothing rather than as a guess -- see `known`.
    property string layout: ""

    // Whether `layout` is a value this component can actually draw. A layout
    // name it does not recognise is NOT rendered as a fallback glyph: the
    // indicator's whole job is to say which of three layouts you are in, and
    // a wrong-but-plausible icon is worse than an absent one. layout-cycle.sh
    // could grow a fourth layout tomorrow and this file would then say
    // nothing until it is taught the glyph, which is the safe direction.
    readonly property bool known:
        root.layout === "monadtall" || root.layout === "max" || root.layout === "treetab"

    // ---- THE GLYPHS ----
    //
    // JetBrainsMono Nerd Font, which is already this shell's iconFontFamily
    // and already a hard dependency. Coverage was CHECKED rather than
    // assumed, with `fc-list :charset=<cp>`, and each glyph was then rendered
    // at 10, 11, 12 and 13 px to confirm it still reads at the size it is
    // actually used -- coverage says the codepoint exists, not that the shape
    // survives being 11 px tall.
    //
    // ---- THEY ARE ONE FAMILY: THE SAME FRAME, DIFFERENT INTERIORS ----
    //
    // This is what picked the middle glyph, after the first attempt used
    // U+F0C8, a SOLID block, and it was rejected on sight — correctly. Beside
    // two outlined frames a filled blob is not a third member of the set, it
    // is a different kind of mark that happens to be square, and it read as a
    // smudge rather than as a window.
    //
    // U+F096 is the same outlined frame as the other two with nothing inside
    // it, which is precisely what the Max layout is: the frame the other two
    // subdivide, left undivided. Rendered side by side at 13 px to confirm
    // the three read as one set before this was committed.
    //
    //   monadtall  U+F0DB  the frame split in two. The layout IS a master
    //                                     column plus a stack.
    //   max        U+F096  the frame, empty. One window, whole screen.
    //   treetab    U+F00B  the frame, ruled. This one is exact rather than
    //                                     approximate. layout-cycle.sh's own
    //                                     table says the groupbar "is the only
    //                                     thing TreeTab adds to Max" -- the
    //                                     two layouts are one mechanism and
    //                                     the window LIST is the entire
    //                                     difference. So the glyph that
    //                                     distinguishes them is a list.
    //
    readonly property string glyph: {
        switch (root.layout) {
        case "monadtall": return "";
        case "max":       return "";
        case "treetab":   return "";
        default:          return "";
        }
    }

    // For a tooltip or a future settings row. Capitalised as qtile's
    // CurrentLayout widget capitalised them, and as layout-cycle.sh's own
    // `label` does for the showText popup, so the two never disagree about
    // what the layout is called.
    readonly property string label: {
        switch (root.layout) {
        case "monadtall": return "MonadTall";
        case "max":       return "Max";
        case "treetab":   return "TreeTab";
        default:          return "";
        }
    }

    // $XDG_RUNTIME_DIR/hypr-layouts/current, with the same /tmp fallback
    // layout-cycle.sh uses, so the two cannot point at different files on a
    // machine where the variable is unset.
    readonly property string runtimeDir: {
        const x = Quickshell.env("XDG_RUNTIME_DIR");
        return (x && String(x) !== "") ? String(x) : "/tmp";
    }

    function applyText(t) {
        // Trimmed because the writer uses `printf '%s'` (no trailing newline)
        // and a future `echo` would add one. A stray "\n" would make every
        // comparison above fall to default and the indicator would silently
        // vanish, which is precisely the class of failure this tree keeps
        // paying for.
        root.layout = String(t).trim();
    }

    FileView {
        path: root.runtimeDir + "/hypr-layouts/current"
        watchChanges: true
        // Preloaded for the same reason IslandTheme's is: the first frame
        // should already carry the value rather than appearing a beat later.
        preload: true
        // The file does not exist until layout-cycle.sh has run once -- on a
        // fresh boot the island may well start first. That is an expected
        // state, not an error worth a log line every start; `layout` stays
        // empty, `known` stays false, and the indicator draws nothing until
        // the first write, which watchChanges then picks up.
        printErrors: false

        onLoaded: root.applyText(text())
        onFileChanged: {
            reload();
            root.applyText(text());
        }
    }
}
