.pragma library

//
// ============================================================
//  Copying, on BOTH display servers
// ============================================================
//
// FORK — new file. Reported as part of "i want the same island things where
// 100% working in the hypr to work in qtile": under qtile every copy in this
// shell silently did nothing.
//
// THE CAUSE. Quickshell has no clipboard API, so every copy here is a
// process, and every one of them was `wl-copy`. That is correct under
// Hyprland and inert under qtile — wl-copy needs a Wayland display, exits
// non-zero without one, and `execDetached` has no exit code to report, so the
// failure is perfectly silent. Six call sites had it: the shelf's yank, its
// copy-path action, both hosts' "a text entry is opened by copying it", and
// the calculator's result.
//
// WHICH TOOL, AND WHY THE SPLIT IS ON WAYLAND_DISPLAY
// ---------------------------------------------------
// The RULES already settle this for screenshots and it is the same fact:
// **split on `WAYLAND_DISPLAY`, not on `XDG_SESSION_TYPE`**. Under Hyprland
// `DISPLAY` is ALSO set — XWayland is running — so "is DISPLAY set" answers
// yes in both sessions and would pick xclip inside Hyprland. WAYLAND_DISPLAY
// is set in exactly one of the two.
//
// `XDG_SESSION_TYPE` is worse again: the display manager sets it, and it is
// absent for a session started any other way.
//
// AND THE TEST IS MADE BY THE SHELL, NOT BY QML
// ----------------------------------------------
// `Quickshell.env()` could answer the same question one turn earlier, and
// deliberately does not. A copy is a process either way, so the branch is
// free where it is; putting it in `sh` means the decision is made in the
// environment the copying tool will actually run in, which is the only one
// that can be wrong. It also keeps this a `.pragma library` with no QML
// context, so every layer can call it without an import cycle.
//
// xclip rather than xsel because xclip is what is installed here and what
// qtile's own qdrop.py reaches for first; both take a MIME type, and the
// uri-list form is what makes a paste into a file manager arrive as FILES
// rather than as a line of text.
//
// NOTE FOR THE NEXT EDIT: `.pragma library` JS is CACHED and Quickshell does
// not reload on `.js` changes. Editing this file does nothing until the
// island is restarted — `pkill -x quickshell; setsid -f ~/.config/hypr/scripts/island.sh`.
//

// The argv for `Quickshell.execDetached`. `text` is passed as an ARGUMENT
// and never interpolated into the script, so a path with a quote, a newline
// or a `$` in it copies as itself.
function argv(text, mime) {
    return ["sh", "-c",
        'if [ -n "${WAYLAND_DISPLAY:-}" ]; then\n'
        + '  if [ -n "$2" ]; then printf %s "$1" | wl-copy --type "$2"\n'
        + '  else printf %s "$1" | wl-copy; fi\n'
        + 'else\n'
        + '  if [ -n "$2" ]; then printf %s "$1" | xclip -selection clipboard -t "$2"\n'
        + '  else printf %s "$1" | xclip -selection clipboard; fi\n'
        + 'fi\n',
        "sh", String(text), mime ? String(mime) : ""];
}
