.pragma library

//
// config.py's `parse_task_name`, which the TaskList was never given.
//
// It is passed to the widget as `parse_text=parse_task_name`, and libqtile
// applies it inside `get_taskname()` — checked in the installed libqtile
// rather than assumed, because that is where the state glyphs turn out to
// come from too. This bar reproduced the widget's LAYOUT and not its text
// pipeline, so every title arrived raw:
//
//     reported, from the user's own bar
//         "✳ Claude Code"          <- U+2733, set by the terminal's title
//         "No file - mpv"          <- the app name qtile strips
//
// Both are in that function. The second half of this file is the reason the
// first half is not simply a list of replacements — see the note there.
//
// A .js library and not a QML function because it is pure text and belongs
// under a unit test more than under a delegate. NOTE the `.pragma library`
// caching trap that NEXT-SESSION.md records: editing this file and saving is
// not enough, the shell has to be restarted.

// Suffixes an application appends to its own window title. Verbatim from
// config.py, order included — a longer entry has to be tried before the
// shorter one it contains.
const REMOVE = [
    // Browsers
    " - Mozilla Firefox",
    " - Firefox",
    " - Chromium",
    " - Google Chrome",
    " - Brave",
    " - Microsoft Edge",
    " - Vivaldi",
    " - Opera",
    // LibreOffice
    " — LibreOffice Writer",
    " — LibreOffice Calc",
    " — LibreOffice Impress",
    // Editors / IDEs
    " - Visual Studio Code",
    " - Code",
    " - VS Code",
    " — Visual Studio Code",
    " - Sublime Text",
    " - Atom",
    " - IntelliJ IDEA",
    " - PyCharm",
    // Terminals
    " — Alacritty",
    " — Kitty",
    " — WezTerm",
    " — GNOME Terminal",
    " - Konsole",
    // Media
    " - VLC media player",
    " - MPV",
    " — Spotify",
    " - YouTube",
    // System / DE noise
    "Built-in Widgets —",
    " — Settings",
    " — Preferences",
    " — System Settings"
];

function parse(text) {
    let out = String(text === undefined || text === null ? "" : text);

    for (let i = 0; i < REMOVE.length; i++)
        out = out.split(REMOVE[i]).join("");

    // ---- THE GENERIC SEPARATOR, AND WHY IT IS NOT A REPLACE ----
    //
    // config.py's list used to end with " - " and " — " as plain entries,
    // removed with str.replace — which deletes EVERY occurrence rather than
    // the one before an application name, so "Ati's Homepage - qutebrowser"
    // came out as "Ati's Homepagequtebrowser", two words welded together, on
    // any title containing a dash at all.
    //
    // A TRAILING " - <name>" is stripped instead, and only when the tail
    // looks like an application name: short, and with no further separator
    // inside it. A real subtitle ("Chapter 3 - The Long Way Home") is left
    // alone. That is the whole reason this is ported as code rather than as
    // a bigger REMOVE list.
    const seps = [" — ", " - "];
    for (let i = 0; i < seps.length; i++) {
        const sep = seps[i];
        const at = out.lastIndexOf(sep);
        if (at <= 0)
            continue;                       // no separator, or nothing before it
        const head = out.substring(0, at);
        const tail = out.substring(at + sep.length);
        if (tail.length <= 25 && tail.indexOf(sep.trim()) < 0)
            out = head;
    }

    // ---- THE LEADING STATUS GLYPH ----
    //
    // This is the half the user's screenshot was showing. The terminal
    // sessions in here set their title to a spinner frame plus the task —
    // "⠂ Fix …", "✳ Upgrade …" — and the frame changes several times a
    // second. In a bar that is a character of pure noise in the highest-value
    // column, and it repaints the widget on every tick.
    //
    // Braille block U+2800–U+28FF is the spinner; the five singles are the
    // done/busy/paused marks that replace it when it stops.
    out = out.replace(/^\s+/, "");
    while (out.length > 0) {
        const c = out.codePointAt(0);
        const isSpinner = c >= 0x2800 && c <= 0x28FF;
        const isMark = c === 0x2733 || c === 0x2713 || c === 0x2717
            || c === 0x25B6 || c === 0x23F8;
        if (!isSpinner && !isMark)
            break;
        out = out.substring(1).replace(/^\s+/, "");
    }

    return out;
}
