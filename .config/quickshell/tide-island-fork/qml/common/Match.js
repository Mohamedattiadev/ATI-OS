.pragma library

//
// Match.js — one answer to "which of these did they mean".
//
// FORK — new file. Extracted from PickerLayer.qml, which had it right, and
// promoted because four other panels had it wrong in the same way.
//
// WHY THIS EXISTS
// ---------------
// Reported against the power menu: typing "log" for Log out leaves "Lock
// screen" selected and Enter locks the screen instead. The data says why:
//
//     Lock screen    loginctl lock-session -> hyprlock     <- "log" is here
//     Log out        loginctl terminate-session
//
// Every panel but the picker filtered with a flat `label.includes(q) ||
// detail.includes(q)` and then kept the ORIGINAL ORDER. "Lock screen" is
// first in the list and matches on its detail, so it wins over the row
// whose NAME is what was typed. On a power menu that is not a cosmetic
// ranking problem — it is one keystroke from "log" to a locked screen when
// you meant to log out.
//
// PickerLayer had already met this exact bug from the other direction (its
// own note: "I type c and Clipboard does not come up") and solved it with
// buckets. The solution was correct and stuck in one file.
//
// THE BUCKETS
// -----------
//     4  the label STARTS with the query
//     3  the label contains it
//     2  label or detail contains it
//     1  every character of the query appears in order somewhere
//     0  no match
//
// Not a score. Order INSIDE a bucket is whatever the caller sent, so the
// list does not reshuffle under the cursor beyond the one regrouping the
// keystroke actually caused. That matters on a list you are arrowing
// through while typing.
//
// Spaces in the query are skipped in the subsequence pass, so "qute 2" and
// "qute2" are the same query — a space is a word separator to a person,
// never a character to be found.
//

// The best rank `rank()` can return. Callers walk down from here rather
// than hardcoding 4, so adding a bucket does not need edits in five files.
var BEST = 4;

function rank(label, detail, needle) {
    if (needle === "")
        return BEST;
    var lab = String(label || "").toLowerCase();
    var hay = (lab + " " + String(detail || "")).toLowerCase();
    var q = String(needle).toLowerCase();

    if (lab.indexOf(q) === 0)
        return 4;
    if (lab.indexOf(q) >= 0)
        return 3;
    if (hay.indexOf(q) >= 0)
        return 2;

    var at = 0;
    for (var i = 0; i < q.length; i++) {
        var ch = q.charAt(i);
        if (ch === " ")
            continue;
        at = hay.indexOf(ch, at);
        if (at < 0)
            return 0;
        at += 1;
    }
    return 1;
}

// Rank-ordered filter. `labelOf`/`detailOf` pull the two strings out of
// whatever the caller's items are, so this does not care whether a row is
// a picker item, a theme, a power action or a cheatsheet line.
//
// Returns a NEW array; the caller's own list is never reordered, which is
// what keeps "the unfiltered truth" available for the panels that size
// themselves from it.
function filter(items, needle, labelOf, detailOf) {
    var out = [];
    if (!items)
        return out;
    var q = String(needle || "").trim();
    if (q === "") {
        for (var k = 0; k < items.length; k++)
            out.push(items[k]);
        return out;
    }
    var buckets = [];
    for (var b = 0; b <= BEST; b++)
        buckets.push([]);
    for (var i = 0; i < items.length; i++) {
        var it = items[i];
        var r = rank(labelOf ? labelOf(it) : it,
                     detailOf ? detailOf(it) : "",
                     q);
        if (r > 0)
            buckets[Math.min(r, BEST)].push(it);
    }
    for (var rr = BEST; rr >= 1; rr--)
        for (var j = 0; j < buckets[rr].length; j++)
            out.push(buckets[rr][j]);
    return out;
}
