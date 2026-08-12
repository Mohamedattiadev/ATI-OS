# CRITICAL: Load the autoconfig first.
config.load_autoconfig()


# ---- theme_mode integration ---------------------------------------------
# Retint qb's whole chrome (tabs / statusbar / completion / messages /
# prompts / downloads) from the active palette. Applies to EVERY mode,
# not just "wal": theme-apply dumps ~/.cache/qtile/current_palette.json
# on every preset apply too, so gating this on mode == "wal" left every
# preset (gruvbox, dracula, ...) stuck on doom_one's hardcoded colors
# while the rest of the desktop had already switched.
# `:config-source` (fired by theme-apply) re-runs this.
def _mix(a, b, t=0.5):
    """Blend two hex colours; the 9-slot palette has no dim/muted slot."""
    a, b = a.lstrip("#"), b.lstrip("#")
    return "#%02x%02x%02x" % tuple(
        round(int(a[i:i + 2], 16) * (1 - t) + int(b[i:i + 2], 16) * t)
        for i in (0, 2, 4)
    )


def _apply_palette():
    import json, os
    try:
        # Read the same semantically re-slotted 9-slot palette every other
        # consumer uses (homepage CSS, eww, nvim, qtile popups) instead of
        # raw wal colors.json. theme-apply re-slots wal's raw accents by
        # hue before they reach any consumer -- reading the raw file here
        # meant qb's native chrome (tabs/statusbar) could show a totally
        # different accent than the homepage content it sits right next to.
        with open(os.path.expanduser("~/.cache/qtile/current_palette.json")) as f:
            d = json.load(f)
        bg, bg_alt, fg = d["bg"], d["bg_alt"], d["fg"]
        yellow, cyan = d["yellow"], d["cyan"]
        red, green, purple = d["red"], d["green"], d["purple"]
        # Blue is the slot theme-apply also feeds to the GTK accent and to
        # dunst's frame color, so using it here keeps qb's selected tab in
        # the same hue family as the rest of the desktop instead of
        # picking a second, unrelated accent.
        acc = d["blue"]
        c.colors.completion.category.bg = bg_alt
        c.colors.completion.category.fg = fg
        c.colors.completion.category.border.top    = bg_alt
        c.colors.completion.category.border.bottom = bg_alt
        c.colors.completion.odd.bg  = bg
        c.colors.completion.even.bg = bg_alt
        c.colors.completion.fg = fg
        c.colors.completion.item.selected.bg = acc
        c.colors.completion.item.selected.fg = bg
        c.colors.completion.item.selected.border.top    = acc
        c.colors.completion.item.selected.border.bottom = acc
        c.colors.completion.match.fg = yellow
        c.colors.statusbar.normal.bg  = bg
        c.colors.statusbar.normal.fg  = fg
        c.colors.statusbar.insert.bg  = acc
        c.colors.statusbar.insert.fg  = bg
        c.colors.statusbar.command.bg = bg_alt
        c.colors.statusbar.command.fg = fg
        c.colors.statusbar.url.fg     = fg
        c.colors.statusbar.url.hover.fg = acc
        c.colors.tabs.bar.bg      = bg_alt
        c.colors.tabs.odd.bg      = bg_alt
        c.colors.tabs.even.bg     = bg
        c.colors.tabs.odd.fg      = fg
        c.colors.tabs.even.fg     = fg
        c.colors.tabs.selected.odd.bg  = acc
        c.colors.tabs.selected.even.bg = acc
        c.colors.tabs.selected.odd.fg  = bg
        c.colors.tabs.selected.even.fg = bg
        c.colors.tabs.indicator.start = acc
        c.colors.tabs.indicator.stop  = cyan
        c.colors.webpage.bg = bg
        c.colors.hints.bg = acc
        c.colors.hints.fg = bg
        c.colors.hints.match.fg = red
        c.hints.border = f"2px solid {acc}"
        # Groups doom_one hardcodes and the old wal-only block never
        # touched -- these are what still read "doom one blue/red" over a
        # gruvbox or wal desktop (e.g. the ":adblock-update" info bar).
        c.colors.messages.info.bg = bg_alt
        c.colors.messages.info.fg = fg
        c.colors.messages.info.border = bg_alt
        c.colors.messages.warning.bg = bg_alt
        c.colors.messages.warning.fg = yellow
        c.colors.messages.warning.border = yellow
        c.colors.messages.error.bg = bg_alt
        c.colors.messages.error.fg = red
        c.colors.messages.error.border = red
        c.colors.prompts.bg = bg_alt
        c.colors.prompts.fg = fg
        c.colors.prompts.border = f"1px solid {acc}"
        c.colors.prompts.selected.bg = acc
        c.colors.prompts.selected.fg = bg
        c.colors.downloads.bar.bg = bg
        c.colors.downloads.start.bg = acc
        c.colors.downloads.start.fg = bg
        c.colors.downloads.stop.bg = green
        c.colors.downloads.stop.fg = bg
        c.colors.downloads.error.bg = red
        c.colors.downloads.error.fg = bg
        c.colors.statusbar.caret.bg = purple
        c.colors.statusbar.caret.fg = bg
        c.colors.statusbar.caret.selection.bg = purple
        c.colors.statusbar.caret.selection.fg = bg
        c.colors.statusbar.passthrough.bg = cyan
        c.colors.statusbar.passthrough.fg = bg
        c.colors.statusbar.private.bg = bg_alt
        c.colors.statusbar.private.fg = fg
        c.colors.statusbar.progress.bg = acc
        c.colors.statusbar.url.success.http.fg = green
        c.colors.statusbar.url.success.https.fg = green
        c.colors.statusbar.url.warn.fg = yellow
        c.colors.statusbar.url.error.fg = red
        c.colors.tabs.pinned.odd.bg = bg_alt
        c.colors.tabs.pinned.even.bg = bg
        c.colors.tabs.pinned.odd.fg = fg
        c.colors.tabs.pinned.even.fg = fg
        c.colors.tabs.pinned.selected.odd.bg = acc
        c.colors.tabs.pinned.selected.even.bg = acc
        c.colors.tabs.pinned.selected.odd.fg = bg
        c.colors.tabs.pinned.selected.even.fg = bg
        # Right-click menu is a plain Qt widget: doom_one never touches it
        # and qb leaves it at the Qt default, so it came up as a light-grey
        # menu with dark text on top of every dark palette.
        c.colors.contextmenu.menu.bg = bg_alt
        c.colors.contextmenu.menu.fg = fg
        c.colors.contextmenu.selected.bg = acc
        c.colors.contextmenu.selected.fg = bg
        c.colors.contextmenu.disabled.bg = bg_alt
        # No "dim" slot in the 9-colour palette -- mix fg halfway into the
        # menu bg so disabled entries read as greyed out and not invisible.
        c.colors.contextmenu.disabled.fg = _mix(fg, bg_alt)
        c.colors.keyhint.bg = bg_alt
        c.colors.keyhint.fg = fg
        c.colors.keyhint.suffix.fg = yellow
        # Absorbed from doom_one, which is no longer imported. These were
        # the last nine slots still painted with hardcoded Doom One hexes
        # over every other palette -- exactly what this function exists to
        # stop. The scrollbar and the "private command" bar are surfaces
        # you only notice when they are the wrong colour.
        c.colors.completion.item.selected.match.fg = yellow
        c.colors.completion.scrollbar.bg = bg_alt
        c.colors.completion.scrollbar.fg = _mix(fg, bg_alt)
        c.colors.statusbar.command.private.bg = bg_alt
        c.colors.statusbar.command.private.fg = fg
        c.colors.tabs.indicator.error = red
        # Not carried over: colors.downloads.system.{bg,fg} and
        # colors.tabs.indicator.system. Those are ColorSystem enums (how
        # to interpolate the progress gradient), not colours, and
        # doom_one set all three to "rgb" -- already the qutebrowser
        # default, so setting them here would be pure noise.
    except Exception:
        # Palette dump missing/corrupt -- fall back to the dark_mode block
        # below plus qutebrowser's own defaults, rather than leaving a
        # half-applied palette.
        pass
# Called further down, after the dark_mode fallback block -- that block
# writes four of these same options and would clobber them if
# _apply_palette() ran first.

# -----------------------------------------------------------------------------
# Theme & UI
# -----------------------------------------------------------------------------
config.set("colors.webpage.darkmode.enabled", True)

# Spacing and non-colour chrome, absorbed from doom_one.setup() so the
# vendored theme package (and its 3.2 MB source zip) could be dropped.
# Everything else doom_one set was either a hardcoded Doom One hex that
# _apply_palette() immediately overwrote, or one of the nine it missed --
# those are now palette-driven in _apply_palette() instead.
c.statusbar.padding = {"top": 5, "right": 5, "bottom": 5, "left": 5}
c.tabs.padding = {"top": 5, "right": 5, "bottom": 5, "left": 5}
c.tabs.indicator.width = 3
c.tabs.favicons.scale = 1
# doom_one asked for "bold 11pt 'Fira Mono'", which is not installed --
# hint labels were rendering in the Noto Sans CJK fallback, the same bug
# as the c.fonts.default_family one below.
c.fonts.hints = "bold 11pt 'JetBrainsMono Nerd Font'"

# Fallback hint colours only. _apply_palette() runs *after* this block and
# overwrites all four from the live palette, so these are what you get when
# ~/.cache/qtile/current_palette.json is missing (fresh install, before the
# first theme-apply) -- not the normal path.
dark_mode = True  # Manually switch this or automate later


if dark_mode:
    # DARK MODE — dark background, bright text, stylish accent
    c.colors.hints.bg = "#1e1e2e"  # Deep indigo-gray
    c.colors.hints.fg = "#ffffff"  # Pure white hint text
    c.colors.hints.match.fg = "#f38ba8"  # Soft red-pink for matched chars
    c.hints.border = "2.5px solid #89b4fa"  # Soft blue border for visibility

else:
    # LIGHT MODE — bright background, dark text, elegant accents
    c.colors.hints.bg = "#f4f4f5"  # Gentle off-white background
    c.colors.hints.fg = "#000000"  # Pure black text for clarity
    c.colors.hints.match.fg = "#b91c1c"  # Deep crimson for match
    c.hints.border = "2.5px solid #6366f1"  # Indigo border for structure


# Retint the whole browser UI (hints, statusbar, completion, tabs,
# messages, prompts, downloads, webpage bg) from the active palette --
# must run after the dark_mode block above, or that clobbers it right
# back. Runs for every
# mode (preset or wal). `:config-source` (fired by theme-apply) re-runs
# this whole file, so switching theme or wallpaper re-applies live.
_apply_palette()


c.hints.chars = "asdghjkl"

# Family names must match what fontconfig actually has installed --
# "JetBrains Mono" and "Source Code Pro" are neither installed nor
# aliases here, so every one of these fell through to the Noto Sans CJK
# fallback and the whole chrome rendered in a CJK face. "JetBrainsMono
# Nerd Font" is the name the qtile bar already uses.
c.fonts.default_family = "JetBrainsMono Nerd Font"
c.fonts.default_size = "9pt"
c.fonts.prompts = "default_size sans-serif"
# JetBrains Mono has no Arabic coverage, so Qt falls back glyph-by-glyph and
# breaks the shaping run -- Arabic tab titles come out in isolated forms and
# in reverse. Naming an Arabic face as fallback keeps the run intact.
c.fonts.statusbar = '11pt "JetBrainsMono Nerd Font", "Noto Naskh Arabic"'
c.fonts.tabs.selected = '9pt "JetBrainsMono Nerd Font", "Noto Naskh Arabic"'
c.fonts.tabs.unselected = '9pt "JetBrainsMono Nerd Font", "Noto Naskh Arabic"'

c.content.blocking.method = "auto"
c.keyhint.blacklist = ["*"]
c.messages.timeout = 0
c.scrolling.smooth = True

# -----------------------------------------------------------------------------
# Content
# -----------------------------------------------------------------------------
# qt6-webengine ships pdf.js; without this every PDF link is a download
# instead of rendering in a tab.
c.content.pdfjs = True
# Videos that start themselves fight the mpv hint (M) below, which
# exists precisely to watch things deliberately.
c.content.autoplay = False

# -----------------------------------------------------------------------------
# Tabs, completion, downloads
# -----------------------------------------------------------------------------
# Closing the last tab left an empty window; go back to the homepage.
c.tabs.last_close = "startpage"
c.completion.height = "35%"
# Finished downloads used to sit in the bar until qb was restarted.
c.downloads.remove_finished = 10000
c.downloads.position = "bottom"


# -----------------------------------------------------------------------------
# Startup Pages
# -----------------------------------------------------------------------------
# Hardcoding /home/ati here meant every other machine opened a blank page
# instead of the themed homepage theme-apply generates.
import os as _os

_homepage = "file://" + _os.path.expanduser(
    "~/.config/qutebrowser/html/homepage.html"
)
c.url.default_page = _homepage
c.url.start_pages = [_homepage]

# The homepage already paints itself from the live palette (theme-apply
# rewrites its :root). Running Chromium's dark-mode filter over it too
# means a light preset gets force-inverted back to dark and the start
# page ends up the one surface that ignores the theme.
config.set("colors.webpage.darkmode.enabled", False, _homepage)

# -----------------------------------------------------------------------------
# Editor & Clipboard
# -----------------------------------------------------------------------------
# c.editor.command = ["alacritty", "-e", "nvim", "{}"]
#
# c.editor.command = [
#     "alacritty", "-e", "nvim",
#     "+call cursor({line}, {column})", "{file}"
# ]

c.editor.command = [
    "alacritty",
    "--title",
    "edit-field",
    "-e",
    "nvim",
    "+call cursor({line}, {column})",
    "{file}",
]

c.content.javascript.clipboard = "access"

# -----------------------------------------------------------------------------
# Tabs & Statusbar
# -----------------------------------------------------------------------------
c.tabs.show = "always"

# -----------------------------------------------------------------------------
# Downloads
# -----------------------------------------------------------------------------
c.downloads.location.directory = "~/Downloads"


# -----------------------------------------------------------------------------
# Keybindings - Vim Style
# -----------------------------------------------------------------------------
# unbind
config.unbind("d", mode="normal")
config.unbind("D", mode="normal")
config.unbind("U", mode="normal")
config.unbind("u", mode="normal")
config.unbind("<Ctrl-a>", mode="normal")
config.unbind("<Ctrl-t>", mode="normal")
config.unbind("<Ctrl-q>", mode="normal")
# -----
config.unbind("m", mode="normal")
config.unbind("H", mode="normal")
config.unbind("L", mode="normal")
config.unbind("J", mode="normal")
config.unbind("K", mode="normal")
config.unbind("<Space>", mode="caret")
config.unbind("<Ctrl-v>", mode="normal")
# config.unbind('Sq')
config.unbind("B", mode="normal")
config.unbind("b", mode="normal")
config.unbind("Sb")
config.unbind("gD")
config.unbind("Ss")
config.unbind("<Alt+m>")
config.unbind("q")  # macro-record
config.unbind("@")  # macro-run
config.unbind("<Shift+Tab>", mode="command")
config.unbind("<Ctrl+Tab>", mode="command")
config.unbind("<Ctrl+Shift+Tab>", mode="command")
config.unbind("<Ctrl+d>", mode="command")
config.unbind("<Shift+Del>", mode="command")
config.unbind("<Ctrl+c>", mode="command")
config.unbind("<Ctrl+Shift+c>", mode="command")
config.unbind("<Ctrl+Return>", mode="command")
config.unbind("<Ctrl+b>")
config.unbind("<Ctrl+a>", mode="command")
config.unbind("<Ctrl+e>", mode="command")
config.unbind("<Alt+d>", mode="command")


# Navigation
config.bind("H", "tab-prev")
config.bind("L", "tab-next")
config.bind("<Ctrl-h>", "back")
config.bind("<Ctrl-l>", "forward")

# Prompt navigation
config.bind("<Ctrl-j>", "completion-item-focus --next", mode="prompt")
config.bind("<Ctrl-k>", "completion-item-focus --prev", mode="prompt")

# Hints
config.bind("T", "cmd-set-text -s :tab-select")
config.bind("Y", "hint links yank")
config.bind("M", "hint links spawn mpv {hint-url}")

config.bind(
    "V",
    "hint links spawn --userscript ~/.config/qutebrowser/scripts/download_video {hint-url}",
    mode="normal",
)
config.bind(
    "I",
    "hint images spawn --userscript ~/.config/qutebrowser/scripts/download-indexed-image {hint-url}",
)
config.bind("yI", "hint images yank")  # lowercase y, uppercase I
# Passthrough
config.bind("<Ctrl-p>", 'mode-enter passthrough ;; message-info "Passthrough mode ON"')
config.bind(
    "<Escape>", 'mode-leave ;; message-info "Passthrough mode OFF"', mode="passthrough"
)
config.bind("<Escape>", "clear-messages", mode="normal")

# Custom Commands
config.bind("<space>t", "open -t", mode="normal")
# config.bind('<space>w', 'tab-close')
# config.bind('<space>o', 'tab-only')
config.bind("<space>f", "cmd-set-text :")
config.bind("<space>mgh", "open https://github.com/MohamedattiaDev")
config.bind("<space>ati", "open https://mohamedattiaDev.github.io/AtiDocs")
config.bind("<space>ls", "session-load default")
config.bind("<space>ss", "session-save default")
config.bind("<space>wq", "quit --save")
# config.bind('<space>w', 'session-save default')
config.bind("<space>V", "view-source")
config.bind(",d", "config-cycle colors.webpage.darkmode.enabled")
config.bind("<space><space>", "cmd-set-text -s :open -t")
config.bind("xb", "config-cycle statusbar.show always never")
config.bind("xt", "config-cycle tabs.show always never")
config.bind(
    "xx",
    "config-cycle statusbar.show always never;; config-cycle tabs.show always never",
)
# config.bind('y', 'yank', mode='normal')
# config.bind('y', 'yank selection', mode='caret')
config.bind("<space>iw", "devtools window")
config.bind("<space>I", "devtools ")
# config.bind('V', 'mode-enter caret ;; fake-key V')
# config.bind('Sh', 'open -t  qute://history')
config.bind("Sm", "open -t qute://bookmarks")
config.bind("Uc", "spawn ~/.config/qutebrowser/scripts/reload_and_notify")
config.bind(
    "<space>t",
    "yank selection --sel primary ;; cmd-later 100 open --tab {primary}",
    mode="caret",
)
config.bind("s", "cmd-set-text /", mode="caret")
config.bind("gS", "tab-give")  # go in separate tab
config.bind("<Ctrl-j>", "completion-item-focus next", mode="command")
config.bind("<Ctrl-k>", "completion-item-focus prev", mode="command")
config.bind("<Ctrl-n>", "completion-item-focus next-category", mode="command")
config.bind("<Ctrl-p>", "completion-item-focus prev-category", mode="command")
config.bind("<Ctrl+Shift+d>", "completion-item-del", mode="command")
config.bind("<Ctrl-y>", "completion-item-yank", mode="command")
config.bind("<Ctrl-h>", "rl-backward-char", mode="command")
config.bind("<Ctrl-l>", "rl-forward-char", mode="command")
config.bind("<Ctrl-w>", "rl-forward-word", mode="command")
config.bind("<Ctrl-b>", "rl-backward-word", mode="command")

config.bind("N", "hint inputs", mode="normal")
config.bind("N", "edit-text", mode="insert")


config.bind(
    "Qr", "hint links spawn ~/.config/qutebrowser/scripts/qr {hint-url}", mode="normal"
)

config.bind(
    "Sd",
    "spawn --userscript ~/.config/qutebrowser/scripts/open_download",
    mode="normal",
)

config.bind(
    "Sq", "spawn ~/.config/qutebrowser/scripts/quick_access_rofi", mode="normal"
)

config.bind("Sb", "spawn ~/.config/qutebrowser/scripts/bookmarks_rofi", mode="normal")
# config.bind(
#     'Sb',
#     'open -t qute://bookmarks ;; later 200 hint all',
#     mode='normal'
# )

config.bind("Sh", "spawn ~/.config/qutebrowser/scripts/history_rofi", mode="normal")
config.bind("E", "edit-url", mode="normal")
# Bind 'Z' in normal mode to open a Zen-style floating preview
config.bind("P", "hint --rapid links window", mode="normal")  # preview links


config.bind(
    "K",
    "spawn --userscript ~/.config/qutebrowser/scripts/show_keymaps",
    mode="normal",
)

# for arabic layout
config.bind("ه", "mode-enter insert", mode="normal")

# -----------------------------------------------------------------------------
# Search Engines
# -----------------------------------------------------------------------------
c.url.searchengines = {
    "DEFAULT": "https://duckduckgo.com/?q={}",
    "g": "https://www.google.com/search?q={}",
    "ddg": "https://duckduckgo.com/?q={}",
    "br": "https://search.brave.com/search?q={}",
    "b": "https://www.bing.com/search?q={}",
    "gh": "https://github.com/search?q={}",
    "gl": "https://gitlab.com/search?q={}",
    "so": "https://stackoverflow.com/search?q={}",
    "npm": "https://www.npmjs.com/search?q={}",
    "py": "https://pypi.org/search/?q={}",
    "aur": "https://aur.archlinux.org/packages/?K={}",
    "aw": "https://wiki.archlinux.org/index.php?search={}",
    "yt": "https://www.youtube.com/results?search_query={}",
    "wiki": "https://en.wikipedia.org/w/index.php?search={}",
    "mdn": "https://developer.mozilla.org/en-US/search?q={}",
    "dev": "https://devdocs.io/#q={}",
    "chatgpt": "https://chat.openai.com/?q={}",
    "gemini": "https://gemini.google.com/?q={}",
    "r": "https://www.reddit.com/r/all/search?q={}",
    "hn": "https://hn.algolia.com/?q={}",
    # Localhost shortcuts
    "local": "http://localhost:{}",
    "locals": "https://localhost:{}",
}

# -----------------------------------------------------------------------------
# Aliases
# -----------------------------------------------------------------------------
c.aliases.update(
    {
        # IMPORTANT: u can create ur own setup here with the open-work-tabs script
        "dev": "spawn --userscript ~/.config/qutebrowser/scripts/open-work-tabs",
        "yt": "open https://www.youtube.com",
        # 'gh': 'open https://github.com',
        "mgh": "open https://github.com/MohamedattiaDev",
        "ati": "open https://mohamedattiaDev.github.io/AtiDocs",
        "fa3": "open https://Fa3elKheer.github.io/Fa3elKheer",
        "g": "open https://google.com",
        "gl": "open https://gitlab.com",
        "mail": "open https://mail.google.com",
        "chat": "open https://chat.google.com",
        "devdocs": "open https://devdocs.io",
    }
)


# -----------------------------------------------------------------------------
# Per-domain Settings (Final Corrected Version)
# -----------------------------------------------------------------------------
#
# # ===== Core Privacy/Content Settings =====
# config.set('content.blocking.method', 'auto')  # Works without additional dependencies
# config.set('content.site_specific_quirks.enabled', False)
#
# # ===== Cookie Management =====
# config.set('content.cookies.accept', 'all', 'https://www.youtube.com')
# # config.set('content.cookies.accept', 'no-3rdparty', '*')
#
# # ===== JavaScript Settings =====
# config.set('content.javascript.enabled', True)
# config.set('content.javascript.clipboard', 'access')  # Corrected valid value
#
# # ===== YouTube-Specific Workarounds =====
# c.content.blocking.whitelist = [
#     '*://*.doubleclick.net/*',
#     '*://*.youtube.com/*'
# ]
#
# # Correct JavaScript log settings (proper dictionary format)
# config.set('content.javascript.log', {
#     'unknown': 'none',
#     'info': 'none',
#     'warning': 'none',
#     'error': 'none'  # Show only errors as warnings
# })
#
# # ===== Ad-Blocking =====
# config.set('content.blocking.adblock.lists', [
#     'https://easylist.to/easylist/easylist.txt',
#     'https://easylist.to/easylist/easyprivacy.txt',
#     'https://secure.fanboy.co.nz/fanboy-annoyance.txt',
#     'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt',
#     'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/quick-fixes.txt',
#     'https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_11.txt',
#     'https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_2.txt'
# ])
#
#
# # Fix Google login
# config.set(
#     "content.headers.user_agent",
#     "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
#     "(KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36",
#     "https://accounts.google.com/*"
# )
# config.set("content.cookies.accept", "all", "https://accounts.google.com")
# config.set("content.cookies.accept", "all", "https://*.google.com")
# # ===== Caret Mode Fix =====
# config.set('content.javascript.enabled', True, 'chrome-devtools://*')
# config.set('content.javascript.enabled', True, 'devtools://*')
#
# print("--- Error-Free Config Loaded ---")
