import colorsys
import json
import os
import random
import re
import threading
import subprocess
from qtile_extras.popup import PopupRelativeLayout, PopupText, PopupImage
from libqtile.log_utils import logger

# =============================================================================
# PIL IMPORT SAFETY
# =============================================================================
try:
    from PIL import Image

    HAS_PIL = True
except ImportError:
    Image = None
    HAS_PIL = False
    logger.warning("PIL not found. Install python-pillow for fast wallpaper previews.")

# =============================================================================
# GLOBAL STATE
# =============================================================================
_WALLPAPER_LAYOUT = None
_IMAGES = []
_INDEX = 0
_COL_OFFSET = 0
_CURRENT_WALL = None
_CLOSING = False  # True while the close fade is in flight
# The Qtile object, captured in show_wallpaper_picker(). fuzzy_search_rofi()
# runs rofi in a worker thread and needs call_soon_threadsafe to get back
# onto the event loop -- it referenced _QTILE without this ever being
# defined, so picking a wallpaper from the `/` search raised NameError in a
# daemon thread (silently) and the selection was discarded.
_QTILE = None

# path -> '1920x1080 · JPG · 1.4 MB', filled lazily by image_meta().
_META_CACHE = {}

# =============================================================================
# CONFIG & STYLING
# =============================================================================
WALLPAPER_DIR = os.path.expanduser("~/Pictures/Wallpapers")
CACHE_WALL = os.path.expanduser("~/.cache/wall")
CACHE_THUMBS = os.path.expanduser("~/.cache/qtile_thumbs")

from popups._scale import s as _s

# --- Geometry -----------------------------------------------------------
# Rows/columns are sized against POPUP_W/POPUP_H below: a row is one line of
# FONT at ROW_SIZE, and a name padded to MAX_NAME_LEN plus the
# icon/indicator/padding columns has to fit inside one card. Nothing clips a
# control's overflow, so text that outgrows its rect spills over its
# neighbours -- change one of these and re-check the others.
POPUP_W = _s(1120)
POPUP_H = _s(680)

FONT = "JetBrainsMono Nerd Font"  # monospace: the padded rows only line up
ROW_SIZE = _s(14)                     # in a fixed-width face
HEAD_SIZE = _s(14)
HINT_SIZE = _s(13)
FOOT_SIZE = _s(14)

# qtile builds these layouts with a *pixel* font size ("<family> <n>px"), so
# these are px, not points: a ROW_SIZE=14 line box is 20px tall and 20 rows
# (400px) sit inside the 429px card with room to breathe.
ROWS_PER_COL = 20
COL_COUNT = 3
MAX_NAME_LEN = 17

# Wal-derived palette — refreshed each open via _load_wal_colors().
# Extends the shared cheatsheet loader with popup-specific slots
# (line, dark, highlight_bg, highlight_fg, surface*).
from popups._wal_colors import load_colors as _load_wal_colors
from popups._wal_colors import fade_in_popup, fade_out_popup
from popups._wal_colors import current_theme_mode
from popups._wal_colors import _mix, ensure_contrast

def _load_colors():
    base = _load_wal_colors()
    # highlight_bg = dominant accent (green slot = wal color10).
    # highlight_fg = bg so selected text pops against accent.
    base["line"] = _mix(base["bg"], base["fg"], 0.22)  # separator / bar trough
    base["dark"] = base["bg"]     # borders
    base["highlight_bg"] = base["green"]  # dominant accent
    base["highlight_fg"] = base["bg"]
    # Card surfaces, blended toward fg so they lift off the popup background
    # in both dark and light palettes (wal presets ship either).
    base["surface"] = _mix(base["bg"], base["fg"], 0.07)
    base["surface_alt"] = _mix(base["bg"], base["fg"], 0.14)

    # Text on those cards needs re-checking: the shared loader derives
    # `muted` against `bg`, and the cards sit 7% closer to `fg`, which is
    # enough to drop muted labels under 3:1 on every preset theme-apply
    # ships. highlight_bg keeps the theme's raw accent -- it is a block
    # fill, not text.
    surface, fg = base["surface"], base["fg"]
    for key in ("muted", "green", "red", "blue", "purple"):
        base[key] = ensure_contrast(base[key], surface, fg, minimum=3.0)

    return base

COLORS = _load_colors()


# =============================================================================
# HELPERS
# =============================================================================
def load_images():
    if not os.path.isdir(WALLPAPER_DIR):
        return []
    os.makedirs(CACHE_THUMBS, exist_ok=True)
    # os.walk, not os.listdir — one directory deep used to be a limit that
    # was never meant as one; it just never had a reason to recurse
    # before. ~/Pictures/Wallpapers/themed/<theme>/*.jpg (500+ theme-fit-
    # curated images, see manifest.json there) and the per-theme
    # themed/<theme>.jpg covers were invisible to this scan and therefore
    # unreachable by search no matter how they were named — the same gap
    # the island's own WallpaperPickerLayer.qml had and was already fixed
    # for (its own comment names PROMPT-NEXT.md item 12). Sorted by
    # BASENAME, not full path, so the ordering the flat pool always had is
    # unchanged for every file that was already flat.
    exts = (".png", ".jpg", ".jpeg", ".webp")
    found = []
    for dirpath, _dirnames, filenames in os.walk(WALLPAPER_DIR):
        for fname in filenames:
            if fname.lower().endswith(exts):
                found.append(os.path.join(dirpath, fname))
    return sorted(found, key=lambda p: os.path.basename(p).lower())


def load_current_wallpaper():
    """Absolute path of the applied wallpaper, or None.

    apply_wallpaper() normally makes ~/.cache/wall a *symlink* to the image
    and only falls back to writing the path as text when symlinking fails,
    so the link has to be resolved first: reading a symlinked JPEG as text
    raises UnicodeDecodeError, which is why this used to always come back
    None and neither the check mark nor the opening position ever worked.
    """
    if not os.path.lexists(CACHE_WALL):
        return None

    if os.path.islink(CACHE_WALL):
        try:
            return os.path.realpath(CACHE_WALL)
        except OSError:
            return None

    try:
        with open(CACHE_WALL) as f:
            return f.read().strip() or None
    except Exception:
        return None


def get_thumbnail_path(original_path):
    if not HAS_PIL:
        return original_path

    filename = os.path.basename(original_path)
    thumb_path = os.path.join(CACHE_THUMBS, filename)

    if os.path.exists(thumb_path):
        return thumb_path
    return original_path


def generate_thumbnails_background():
    if not HAS_PIL or Image is None:
        return
    for img_path in _IMAGES:
        filename = os.path.basename(img_path)
        thumb_path = os.path.join(CACHE_THUMBS, filename)
        if not os.path.exists(thumb_path):
            try:
                with Image.open(img_path) as img:
                    img.thumbnail((600, 600))
                    img.save(thumb_path)
            except Exception:
                pass


def esc(name: str) -> str:
    """Escape a filename for Pango markup.

    A wallpaper called "black & white.jpg" makes the whole line malformed
    markup, and pango then drops the entire row (or footer) rather than the
    one bad character. Escaping happens after padding so the escapes don't
    count toward the column width.
    """
    return name.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def truncate(name: str) -> str:
    # Ensure name fills the space for the background color to look like a bar
    if len(name) > MAX_NAME_LEN:
        name = name[: MAX_NAME_LEN - 1] + "…"
    return f"{name:<{MAX_NAME_LEN}}"


def index_to_pos(i):
    return i % ROWS_PER_COL, i // ROWS_PER_COL


def pos_to_index(row, col):
    idx = col * ROWS_PER_COL + row
    return idx if 0 <= idx < len(_IMAGES) else None


def render_column(visible_col):
    """One card's worth of rows, always ROWS_PER_COL lines tall.

    Short columns are padded with blank lines rather than cut short: the
    column controls are v_align="middle", so a ragged last column would
    float its rows in the vertical centre of the card instead of sitting
    flush with its neighbours.
    """
    lines = []
    actual_col = visible_col + _COL_OFFSET

    for row in range(ROWS_PER_COL):
        idx = pos_to_index(row, actual_col)

        if idx is None:
            lines.append("")
            continue

        path = _IMAGES[idx]
        filename = os.path.basename(path)
        display_name = esc(truncate(filename))

        is_selected = idx == _INDEX
        is_current = path == _CURRENT_WALL

        # Every row is the same character count, so the selected row's block
        # lands exactly where the unselected rows' text does: one space of
        # padding OUTSIDE the span (the block is inset from the card edge
        # rather than sitting flush against it), then space + icon + space +
        # padded name + space inside it.
        pad = f'<span foreground="{COLORS["surface"]}"> </span>'

        if is_selected:
            icon = "" if is_current else ""
            body = f" {icon} {display_name} "
            text = (
                f"{pad}"
                f'<span background="{COLORS["highlight_bg"]}" '
                f'foreground="{COLORS["highlight_fg"]}" weight="bold">{body}</span>'
            )
        elif is_current:
            # Applied wallpaper: accent text + check, no block.
            text = (
                f"{pad}"
                f'<span foreground="{COLORS["green"]}" weight="bold">'
                f"  {display_name} </span>"
            )
        else:
            text = (
                f"{pad}"
                f'<span foreground="{COLORS["line"]}">  </span>'
                f'<span foreground="{COLORS["fg"]}">{display_name} </span>'
            )

        lines.append(text)

    return "\n".join(lines)


def render_footer():
    """Returns the markup for the footer status bar."""
    if not _IMAGES:
        return ""

    filename = esc(os.path.basename(_IMAGES[_INDEX]))
    total = len(_IMAGES)
    position = _INDEX + 1
    percent = int((position / total) * 100)

    # Scroll bar: filled portion in the accent, trough in the divider tone.
    bar_len = 20
    filled = max(1, round(bar_len * position / total))
    bar = (
        f'<span foreground="{COLORS["highlight_bg"]}">{"━" * filled}</span>'
        f'<span foreground="{COLORS["line"]}">{"━" * (bar_len - filled)}</span>'
    )

    sep = f'<span foreground="{COLORS["line"]}">   ·   </span>'

    return (
        f'<span foreground="{COLORS["highlight_bg"]}">  </span>'
        f'<span foreground="{COLORS["fg"]}" weight="bold">{filename}</span>'
        f"{sep}{bar}{sep}"
        f'<span foreground="{COLORS["purple"]}" weight="bold">{position}</span>'
        f'<span foreground="{COLORS["muted"]}"> / {total}   ({percent}%)</span>'
    )


def image_meta(path):
    """'1920x1080  ·  JPG  ·  1.4 MB' for the preview strip.

    Cached per path: this runs on the qtile event loop on every cursor
    move, and PIL only reads the header, but a dict lookup beats even that
    when you hold down `j`. Any failure degrades to a shorter string.
    """
    meta = _META_CACHE.get(path)
    if meta is not None:
        return meta

    parts = []
    if HAS_PIL and Image is not None:
        try:
            with Image.open(path) as im:
                parts.append(f"{im.width}\u00d7{im.height}")
        except Exception:
            pass
    ext = os.path.splitext(path)[1].lstrip(".").upper()
    if ext:
        parts.append(ext)
    try:
        size = os.path.getsize(path)
        parts.append(
            f"{size / 1048576:.1f} MB" if size >= 1048576 else f"{size // 1024} KB"
        )
    except OSError:
        pass

    meta = "  \u00b7  ".join(parts)
    _META_CACHE[path] = meta
    return meta


def render_meta():
    """Caption strip under the preview."""
    if not _IMAGES:
        return ""
    return (
        f'<span foreground="{COLORS["muted"]}">{image_meta(_IMAGES[_INDEX])}</span>'
    )


def render_header_badge():
    """Right-hand header chip: what a pick will do to the palette."""
    mode = esc(current_theme_mode() or "unknown")
    follows = "palette follows wallpaper" if mode == "wal" else "palette pinned"
    return (
        f'<span foreground="{COLORS["muted"]}">{follows}  </span>'
        f'<span background="{COLORS["surface_alt"]}" foreground="{COLORS["blue"]}" '
        f'weight="bold"> 󰏘 {mode} </span>'
    )


def _key(label):
    """A keycap chip for the hint bar."""
    return (
        f'<span background="{COLORS["surface_alt"]}" foreground="{COLORS["fg"]}" '
        f'weight="bold"> {label} </span>'
    )


def render_hints():
    gap = f'<span foreground="{COLORS["line"]}">     </span>'
    pairs = [
        ("hjkl", "move"),
        ("/", "search"),
        ("R", "random"),
        ("↵", "apply"),
        ("Esc", "close"),
    ]
    return gap.join(
        f'{_key(k)}<span foreground="{COLORS["muted"]}"> {desc}</span>'
        for k, desc in pairs
    )


# =============================================================================
# WALLPAPER ACTION
# =============================================================================
def apply_wallpaper():
    global _CURRENT_WALL, _WALLPAPER_LAYOUT, _CLOSING
    path = _IMAGES[_INDEX]
    mode = current_theme_mode()

    # ~/.cache/wall (CACHE_WALL) is deliberately NOT written here for a
    # preset theme any more — see the note in _bg() below for why doing so
    # unconditionally used to make the wallpaper never actually change on
    # screen. `_CURRENT_WALL` (the in-memory selection, read at line ~221
    # for the picker's own "is this the current one" highlight) is still
    # set unconditionally and immediately, so the UI still reacts the
    # instant you pick — only the FILE write moved.
    if mode == "wal":
        os.makedirs(os.path.dirname(CACHE_WALL), exist_ok=True)
        try:
            if os.path.lexists(CACHE_WALL):
                os.remove(CACHE_WALL)
            os.symlink(path, CACHE_WALL)
        except OSError:
            with open(CACHE_WALL, "w") as f:
                f.write(path)
    _CURRENT_WALL = path

    # Close popup first so subsequent qtile restart (from theme-apply) doesn't
    # rebuild widgets mid-render and freeze the compositor. Killed outright
    # rather than faded: the fade would still be running when theme-apply
    # restarts qtile out from under it.
    try:
        if _WALLPAPER_LAYOUT is not None:
            _WALLPAPER_LAYOUT.kill()
    except Exception:
        pass
    # Clear the handle, else the next toggle sees a dead layout as "open"
    # and the first keypress is swallowed re-closing nothing.
    _WALLPAPER_LAYOUT = None
    _CLOSING = False

    # Run xwallpaper + theme-apply off the qtile main thread. xwallpaper --stretch
    # on 4K images blocks 1-3s; qtile freezes for that duration if run sync.
    def _bg():
        try:
            mode = current_theme_mode()
            if mode == "wal":
                # wal is defined as "follow the wallpaper", so a new
                # wallpaper has to re-derive the palette — theme-animate
                # wal does both, already animated (see the wal-mode note
                # this replaced, kept in git history).
                subprocess.run(
                    ["xwallpaper", "--stretch", path],
                    check=False,
                    timeout=10,
                )
                subprocess.Popen(
                    ["theme-animate", "wal"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
                return
            # ---- A PRESET THEME (gruvbox, doomone, ...): NOW ALSO
            #      ANIMATED, without re-deriving the palette ----
            #
            # Reported: "the animation of the wallpaper changing also
            # needed" — a preset-mode wallpaper pick used to run bare
            # `xwallpaper --stretch` with nothing covering the cut, since
            # the palette is fixed on a preset and there was never a
            # reason to call theme-apply for it at all.
            #
            # Rather than invent a second overlay path, this reuses the
            # one theme-animate already drives correctly (fixed earlier
            # this session — see apply_palette_live() and the
            # THEME_APPLY_COVERED wait loop in theme-apply): `bind` records
            # this image as MODE's wallpaper, then `theme-animate MODE`
            # re-applies the SAME theme behind the circular-reveal overlay.
            # theme-apply already runs `theme-wallpaper apply "$MODE"
            # instant` unconditionally for every non-wal mode (ask #5) — it
            # picks up the just-bound image and displays it from there, so
            # nothing new has to reach into the overlay's own QML at all.
            #
            # And because every palette slot maps to ITSELF (old hex == new
            # hex, same theme), apply_palette_live() no-ops on colour and
            # no qtile restart happens either — the freeze only has to
            # cover the wallpaper swap, which is fast, so this should feel
            # closer to Hyprland's own timing than a theme change does.
            #
            # This marker is what actually makes it fast, not just
            # restart-free: reported again as "it is slow make it faster
            # like hyper" even after the above. theme-apply's own biggest
            # cost is unconditionally repacking + killing/relaunching
            # brave/chrome (~2s of its own documented ~3.3s run) and
            # regenerating kitty/GTK/rofi/dunst — all of it byte-identical
            # output for a wallpaper-only pick, since the theme did not
            # change. This one file tells theme-apply to skip that whole
            # pipeline and go straight to the wallpaper + the marker; see
            # its own header for why a file and not a second IPC argument.
            try:
                open(
                    os.path.expanduser("~/.cache/qtile/.wallpaper_only_pending"),
                    "w",
                ).close()
            except OSError:
                pass
            subprocess.run(
                ["theme-wallpaper", "bind", mode, path],
                check=False,
                timeout=10,
            )
            subprocess.Popen(
                ["theme-animate", mode],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception as e:
            logger.warning("apply_wallpaper bg failed: %s", e)

    threading.Thread(target=_bg, daemon=True).start()


# =============================================================================
# SEARCH & RANDOM FUNCTIONS
# =============================================================================
def jump_to_random():
    global _INDEX
    if not _IMAGES:
        return

    # Pick random index
    new_idx = random.randint(0, len(_IMAGES) - 1)

    # Update state and ensure visibility
    _INDEX = new_idx
    ensure_visible()
    update_ui()


# =============================================================================
# SEARCH BY THEME FIT
# =============================================================================
# Reported: "the wallpaper of the theme fitting not appering in the popup
# qtile wallpaper picker fix i should if i wrote 'gruvbox' shows me all
# fiting ones". Filenames are plain numbers (0176.jpg), so a bare fuzzy
# match on basenames — the only search this popup had — can never surface
# a theme name typed into it; PROMPT-NEXT.md's item 12 already named this
# gap and proposed fixing it by renaming files into the wallpaper repo
# itself, which is real work in a repo with a remote and was never done.
#
# This does not touch a single file in that repo. ati-wal-precompile already
# computes a `dominant_hue_deg` for every wallpaper it has been run
# against (~/.cache/qtile/palettes/<stem>.json, 362 of them present at
# the time this was written) — the exact signal needed to answer "which
# wallpapers look like this theme", entirely from data that already
# exists. accent_of_mode's own 21-colour table (theme-apply, kept in sync
# with it deliberately — a copy, not an import, since sourcing a bash
# script's function table from Python is not a thing) gives the other
# half: each theme's signature hue.
THEME_ACCENTS = {
    "doomone": "#51afef", "dracula": "#bd93f9", "nord": "#88c0d0",
    "gruvbox": "#fabd2f", "tokyonight": "#7aa2f7", "catppuccin": "#cba6f7",
    "monokai": "#66d9ef", "everforest": "#7fbbb3", "rose-pine": "#c4a7e7",
    "kanagawa": "#7e9cd8", "oxocarbon": "#33b1ff", "cyberpunk-neon": "#00fff9",
    "synthwave": "#36f9f6", "matrix": "#00ff9f", "mono-dark": "#b0b0b0",
    "mono-light": "#1a5fd0", "nightowl": "#82aaff", "onedark": "#61afef",
    "palenight": "#82b1ff", "github-dark": "#58a6ff", "ayu-mirage": "#5ccfe6",
}

WALLPAPER_PALETTES_DIR = os.path.expanduser("~/.cache/qtile/palettes")

# mono-dark's accent (#b0b0b0) and any near-grey wallpaper both have a
# technically-defined but numerically UNSTABLE hue — a 1-unit RGB
# difference can swing it 90 degrees, because saturation is near zero and
# hue is barely meaningful there. Matching by hue alone would make
# "mono-dark" match almost nothing, or almost anything, depending on
# rounding. Not solved here — mono-dark/mono-light are genuinely a
# different kind of question ("is this image LOW-SATURATION", not "what
# hue is it") — documented rather than silently wrong: they are excluded
# from hue matching and simply never show tags.
_HUE_UNSTABLE_THEMES = {"mono-dark"}


def _hex_to_hue_deg(hexcolor):
    h = hexcolor.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    hue, _sat, _val = colorsys.rgb_to_hsv(r, g, b)
    return hue * 360.0


_THEME_HUES = {
    name: _hex_to_hue_deg(hexval)
    for name, hexval in THEME_ACCENTS.items()
    if name not in _HUE_UNSTABLE_THEMES
}

# path -> dominant_hue_deg (float) or None (no precompiled palette yet).
# Filled lazily; a picker session touches at most a few hundred files
# once, not per-keystroke.
_WALLPAPER_HUE_CACHE = {}


def _wallpaper_dominant_hue(path):
    if path in _WALLPAPER_HUE_CACHE:
        return _WALLPAPER_HUE_CACHE[path]
    stem = os.path.splitext(os.path.basename(path))[0]
    hue = None
    try:
        with open(os.path.join(WALLPAPER_PALETTES_DIR, stem + ".json")) as f:
            data = json.load(f)
        raw = data.get("dominant_hue_deg")
        if isinstance(raw, (int, float)):
            hue = float(raw)
    except Exception:
        hue = None
    _WALLPAPER_HUE_CACHE[path] = hue
    return hue


def _hue_distance_deg(a, b):
    d = abs(a - b) % 360.0
    return min(d, 360.0 - d)


# Wide enough that a theme's own "family" (e.g. onedark/doomone, both
# blue-accented) tends to share matches, which is a feature here: typing
# either name is meant to turn up wallpapers that suit the general mood,
# not just the one exact hex. Narrow enough that e.g. matrix (green,
# ~140deg) and gruvbox (yellow/orange, ~42deg) do not bleed together.
_HUE_MATCH_THRESHOLD_DEG = 28.0


_THEMED_DIR_RE = re.compile(r"[/\\]themed[/\\]([^/\\]+)[/\\]")


def theme_names_for_wallpaper(path):
    """Every theme this wallpaper fits, closest/most-authoritative first.

    A wallpaper living under themed/<theme>/ was CURATED for that theme —
    see the note beside load_images()'s own os.walk fix, PROMPT-NEXT.md
    item 12: 500+ images individually scored against every theme's
    palette (manifest.json), not just hue-adjacent. That answer is
    returned alone and is authoritative when it exists; hue matching
    (theme_names_for_wallpaper's original approach, still the only
    signal for the flat, uncurated pool of ~362 originals) is the
    fallback, not a second vote — mixing "this was curated for X" with
    "this happens to be roughly X-hued" as equals would bury the
    curated, actually-correct answer under whatever coincidentally
    scores closest.
    """
    m = _THEMED_DIR_RE.search(path)
    if m:
        return [m.group(1)]
    hue = _wallpaper_dominant_hue(path)
    if hue is None:
        return []
    scored = sorted(
        ((_hue_distance_deg(hue, thue), name) for name, thue in _THEME_HUES.items()),
        key=lambda t: t[0],
    )
    return [name for dist, name in scored if dist <= _HUE_MATCH_THRESHOLD_DEG]


# Separator between a filename and its theme tags in the rofi list.
# Filenames in this repo are plain numbers (0176.jpg), so any printable
# separator is safe; " · " is used nowhere else the fuzzy filter would
# confuse it with, and reads as a label rather than part of the name.
_THEME_TAG_SEP = " · "


def fuzzy_search_rofi():
    global _INDEX
    if not _IMAGES:
        return

    # Each line is "<filename>" for a wallpaper with no confident theme
    # match, or "<filename> · theme1, theme2" for one that has some — so
    # typing a theme name (rofi's own -i fuzzy filter, unchanged) surfaces
    # every wallpaper tagged with it, and typing a filename still works
    # exactly as before since the filename is always the line's own
    # prefix. See theme_names_for_wallpaper()'s own header for where the
    # tags come from and why this needed no file renames.
    lines = []
    for p in _IMAGES:
        base = os.path.basename(p)
        tags = theme_names_for_wallpaper(p)
        if tags:
            lines.append(base + _THEME_TAG_SEP + ", ".join(tags))
        else:
            lines.append(base)
    names = "\n".join(lines)

    def _run_rofi():
        try:
            result = subprocess.run(
                [
                    "rofi",
                    "-dmenu",
                    "-p",
                    "Search Wallpaper",
                    "-i",
                    "-theme-str",
                    "window {width: 50%;}",
                ],
                input=names.encode(),
                stdout=subprocess.PIPE,
                check=False,
                timeout=120,
            )
            selected_name = result.stdout.decode().strip()
            # Strip the " · theme1, theme2" tag suffix a theme-fit match
            # added to the line — the filename is always what precedes it,
            # never part of it (filenames here are plain numbers).
            selected_name = selected_name.split(_THEME_TAG_SEP, 1)[0].strip()
        except subprocess.TimeoutExpired:
            return
        except Exception as e:
            logger.warning("fuzzy_search_rofi failed: %s", e)
            return

        if not selected_name:
            return

        def _apply():
            global _INDEX
            for idx, path in enumerate(_IMAGES):
                if os.path.basename(path) == selected_name:
                    _INDEX = idx
                    ensure_visible()
                    update_ui()
                    return

        if _QTILE is not None:
            _QTILE.call_soon_threadsafe(_apply)

    threading.Thread(target=_run_rofi, daemon=True).start()


# =============================================================================
# POPUP CONTROL
# =============================================================================
def show_wallpaper_picker(qtile):
    global _WALLPAPER_LAYOUT, _IMAGES, _INDEX, _COL_OFFSET, _CURRENT_WALL, _QTILE

    # Captured before the early-return: fuzzy_search_rofi() needs it, and
    # the picker may already be open when the search is invoked.
    _QTILE = qtile

    # _CLOSING as well as the handle. close_wallpaper_picker() clears
    # _WALLPAPER_LAYOUT up front but the window lives on for the length of the
    # fade (~140ms), so for that stretch the handle says "nothing is open"
    # while a popup is very much still on screen. Reopening inside that window
    # built a SECOND popup, and the first one's _teardown then set the handle
    # back to None -- clobbering the handle to the new one and stranding it:
    # visible, unreferenced, and unclosable, because every later close() takes
    # the `not _WALLPAPER_LAYOUT` early return. That is the orphan.
    if _WALLPAPER_LAYOUT or _CLOSING:
        return

    # Refresh from wal cache so popup retints after wallpaper switch
    # without qtile restart (same pattern as cheatsheet popups).
    COLORS.update(_load_colors())
    _IMAGES = load_images()
    if not _IMAGES:
        return

    _COL_OFFSET = 0
    _CURRENT_WALL = load_current_wallpaper()

    # Open on the wallpaper that's actually applied, not on the first file in
    # the directory: the preview then shows what you're already looking at,
    # and paging starts from where you are. Falls back to the top when the
    # applied wallpaper isn't in the directory any more (or none is set).
    _INDEX = 0
    if _CURRENT_WALL in _IMAGES:
        _INDEX = _IMAGES.index(_CURRENT_WALL)
        ensure_visible()

    threading.Thread(target=generate_thumbnails_background, daemon=True).start()

    controls = []

    # ---- Vertical rhythm (fractions of POPUP_H, kept as px comments) ----
    head_y, head_h = 28 / POPUP_H, 54 / POPUP_H     # title block
    hint_y, hint_h = 92 / POPUP_H, 30 / POPUP_H     # keycap bar
    body_y, body_h = 138 / POPUP_H, 436 / POPUP_H   # list + preview cards
    foot_y, foot_h = 588 / POPUP_H, 62 / POPUP_H    # status bar

    # ---------------- HEADER ----------------
    controls.append(
        PopupText(
            text=(
                f'<span size="x-large" weight="bold" foreground="{COLORS["fg"]}">'
                f"\U000f0e09  Wallpapers</span>\n"
                f'<span size="small" foreground="{COLORS["muted"]}">'
                f"~/Pictures/Wallpapers  ·  {len(_IMAGES)} images</span>"
            ),
            markup=True,
            font=FONT,
            fontsize=HEAD_SIZE,
            pos_x=0.035,
            pos_y=head_y,
            width=0.45,
            height=head_h,
            h_align="left",
            v_align="middle",
        )
    )

    # Right-hand chip: whether applying a wallpaper will retheme the desktop.
    controls.append(
        PopupText(
            text=render_header_badge(),
            markup=True,
            font=FONT,
            fontsize=HINT_SIZE,
            pos_x=0.52,
            pos_y=head_y,
            width=0.445,
            height=head_h,
            h_align="right",
            v_align="middle",
        )
    )

    # ---------------- KEY HINTS ----------------
    controls.append(
        PopupText(
            text=render_hints(),
            markup=True,
            font=FONT,
            fontsize=HINT_SIZE,
            background=COLORS["surface"],
            highlight_radius=8,
            pos_x=0.035,
            pos_y=hint_y,
            width=0.93,
            height=hint_h,
            h_align="center",
            v_align="middle",
        )
    )

    # ---------------- COLUMNS ----------------
    # Three cards side by side. Each control paints its own rounded surface,
    # so the gaps between them are the popup background showing through --
    # no separate panel control (which the columns would overpaint).
    start_x = 0.035
    col_width = 0.166  # 184px: one row's 176px of text + 8px of padding
    gap = 0.009

    for c in range(COL_COUNT):
        controls.append(
            PopupText(
                text=render_column(c),
                markup=True,
                font=FONT,
                fontsize=ROW_SIZE,
                background=COLORS["surface"],
                highlight_radius=10,
                pos_x=start_x + c * (col_width + gap),
                pos_y=body_y,
                width=col_width,
                height=body_h,
                h_align="left",
                v_align="middle",
                name=f"col{c}",
            )
        )

    # ---------------- PREVIEW IMAGE ----------------
    # The card colour doubles as the letterbox for images whose aspect ratio
    # doesn't match the frame, so the preview always reads as a framed panel.
    preview_img = get_thumbnail_path(_IMAGES[_INDEX])
    controls.append(
        PopupImage(
            filename=preview_img,
            background=COLORS["surface"],
            highlight_radius=10,
            pos_x=0.565,
            pos_y=body_y,
            width=0.3995,  # right edge lines up with the hint/footer cards
            height=380 / POPUP_H,
            preserve_aspect=True,
            name="preview",
        )
    )

    # ---------------- PREVIEW META ----------------
    # Sits in the gap left under the preview card; bottom edge is flush with
    # the list cards.
    controls.append(
        PopupText(
            text=render_meta(),
            markup=True,
            font=FONT,
            fontsize=HINT_SIZE,
            background=COLORS["surface"],
            highlight_radius=10,
            pos_x=0.565,
            pos_y=526 / POPUP_H,
            width=0.3995,
            height=48 / POPUP_H,
            h_align="center",
            v_align="middle",
            name="meta",
        )
    )

    # ---------------- FOOTER ----------------
    controls.append(
        PopupText(
            text=render_footer(),
            markup=True,
            font=FONT,
            fontsize=FOOT_SIZE,
            background=COLORS["surface"],
            highlight_radius=10,
            pos_x=0.035,
            pos_y=foot_y,
            width=0.93,
            height=foot_h,
            h_align="center",
            v_align="middle",
            name="footer",
        )
    )

    _WALLPAPER_LAYOUT = PopupRelativeLayout(
        qtile,
        width=POPUP_W,
        height=POPUP_H,
        background=COLORS["bg"] + "F2",  # F2 = High opacity but not 100%
        border=COLORS["surface_alt"],
        border_width=2,
        close_on_click=False,
        controls=controls,
    )

    _WALLPAPER_LAYOUT.show(centered=True)
    # Longer/eased than the shared default: this popup is POPUP_W x POPUP_H,
    # and a fade that reads fine on a small cheatsheet is over before the eye
    # tracks it on a panel this large.
    fade_in_popup(_WALLPAPER_LAYOUT, duration=0.28, steps=18)



def close_wallpaper_picker():
    global _WALLPAPER_LAYOUT, _CLOSING
    if not _WALLPAPER_LAYOUT or _CLOSING:
        return
    layout = _WALLPAPER_LAYOUT
    _CLOSING = True

    def _teardown():
        global _WALLPAPER_LAYOUT, _CLOSING
        try:
            # kill(), not hide() -- same reason apply_wallpaper() already
            # kills: hide() leaves the window, its cairo drawer and every
            # control's pango layout allocated, and show_wallpaper_picker()
            # builds a brand new layout on the next open. At 1120x680 that
            # is ~3MB of ARGB surface abandoned per Escape.
            layout.kill()
        except Exception:
            pass
        # Only clear the handle if it still refers to the layout THIS teardown
        # was started for. Belt-and-braces next to the _CLOSING guard in
        # show_wallpaper_picker(): an unconditional `= None` here is what turned
        # a second popup into an unreachable one.
        if _WALLPAPER_LAYOUT is layout:
            _WALLPAPER_LAYOUT = None
        _CLOSING = False

    # Clear the module handle up front so a keypress during the fade
    # can't drive navigation on a popup that is already on its way out.
    _WALLPAPER_LAYOUT = None
    fade_out_popup(layout, _teardown)


def toggle_wallpaper_picker(qtile):
    # _CLOSING guards the window between "fade started" and "hide() ran":
    # without it a fast re-toggle would open a second picker on top of
    # the one still fading, and the teardown would then blank the new one.
    if _CLOSING:
        return
    if _WALLPAPER_LAYOUT:
        close_wallpaper_picker()
    else:
        show_wallpaper_picker(qtile)


# =============================================================================
# NAVIGATION LOGIC
# =============================================================================
def ensure_visible():
    """Calculates _COL_OFFSET to make sure _INDEX is visible."""
    global _COL_OFFSET

    # Calculate which column the current index is in (globally)
    row, col = index_to_pos(_INDEX)

    # If the column is to the left of our view
    if col < _COL_OFFSET:
        _COL_OFFSET = col
    # If the column is to the right of our view
    elif col >= _COL_OFFSET + COL_COUNT:
        _COL_OFFSET = col - COL_COUNT + 1


def update_ui():
    """Redraws the UI components efficiently."""
    if _WALLPAPER_LAYOUT is None:
        return

    updates = {}
    updates["preview"] = get_thumbnail_path(_IMAGES[_INDEX])
    updates["footer"] = render_footer()
    updates["meta"] = render_meta()

    for c in range(COL_COUNT):
        updates[f"col{c}"] = render_column(c)

    _WALLPAPER_LAYOUT.update_controls(**updates)


def move(drow=0, dcol=0):
    global _INDEX

    if _WALLPAPER_LAYOUT is None:
        return

    row, col = index_to_pos(_INDEX)
    new_row = row + drow
    new_col = col + dcol
    idx = pos_to_index(new_row, new_col)

    # Wrap logic for right movement at end of list
    if idx is None and dcol != 0:
        max_cols = (len(_IMAGES) // ROWS_PER_COL) + 1
        if 0 <= new_col < max_cols:
            idx = len(_IMAGES) - 1
        else:
            return

    if idx is None:
        return

    _INDEX = idx
    ensure_visible()
    update_ui()


def apply(qtile):
    apply_wallpaper()
    close_wallpaper_picker()
    qtile.ungrab_chord()
