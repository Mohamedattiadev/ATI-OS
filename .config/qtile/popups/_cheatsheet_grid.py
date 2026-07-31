"""Card layout shared by the Qtile / Vim / Fish cheatsheet popups.

Three things this owns, all of which used to be copy-pasted (badly) into
each sheet:

**The grid.** All three carried the same fixed 4-column by 3-row grid of
equal `ROW_HEIGHT = 0.25` cells, and every section in every one of them
overflowed its cell -- silently, because **PopupText neither clips nor
wraps to its `height`**. The height only positions the control; text taller
than that keeps drawing downward until the popup *window* edge cuts it off.
The Qtile sheet's biggest column ended 101px below that edge, so its last
four entries had never once been on screen. Cards are now packed into
columns at the height the ones above them actually need, and onto a second
page when a page fills up.

**The font.** These popups asked for `sans`, and on this machine
`fc-match sans` answers *Noto Sans CJK KR* -- the same silent fallback that
was fixed for rofi in 242b8ff and never for these. Everything here is
monospace now (`FONT`), which is both what the rest of the popups use and
what makes the key column line up: every glyph is exactly `char_px` wide,
so a row can be padded to an exact column with spaces.

**The row shape.** A row is `label ......... KEY`, the key hard against the
card's right edge. That only works in a monospace face, and only if the
keys are written compactly -- see `compact()`.

Because the face is monospace and every row is one line at the body size,
the geometry is exact rather than estimated: a card is
`(2 + rows) * line_px` tall and `(2 + cols) * char_px` wide, full stop.
`selftest()` still measures it all with pango, since the day that stops
being true is the day the entries start vanishing again.
"""

from libqtile.log_utils import logger

# The system monospace. Never "sans": see the module docstring.
FONT = "JetBrainsMono Nerd Font"

# PopupRelativeLayout's own default. Control positions are fractions of the
# INNER box (size - 2*margin), which is what these numbers assume.
MARGIN = 5

CARD_RADIUS = 8      # rounded corners on the section cards
PAD_CHARS = 1        # left/right padding inside a card, in characters
PAD_ROWS = 1         # blank rows at the top and bottom of a card

GRID_TOP = 0.13      # under the title block
GRID_BOTTOM = 0.905  # above the footer
FOOTER_Y = 0.93
CARD_GAP_PX = 14     # between cards, both directions


# =============================================================================
# TEXT
# =============================================================================
def esc(text):
    """Escape for pango markup. Vim's keys are full of < and >."""
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


# Written out rather than typed in full, because the row only fits when the
# key does. "Mod + Shift + Enter" is 19 characters and pushes the card past
# a quarter of the screen on its own; "Mod ⇧ ↵" is 7 and says the same
# thing. Order matters -- longest first, so "Shift" is gone before "Sh".
#
# Every glyph here must exist in FONT. A missing one does not error -- it
# falls back to some other family at some other width, and the whole key
# column stops lining up. U+21B5 ↵ was the obvious choice for Enter and is
# NOT in JetBrainsMono; U+23CE ⏎ is. `selftest()` checks the whole set
# against the installed font so the next addition cannot slip through.
KEY_SUBS = (
    ("<leader>", "␣"),      # Vim's leader IS Space; the header says so too
    ("<tab>", "⇥"),
    ("Shift", "⇧"),
    ("Ctrl", "⌃"),
    ("Enter", "⏎"),
    ("Return", "⏎"),
    ("Escape", "Esc"),
    ("Space", "␣"),
    ("Super", "Sup"),
    ("[1–9]", "1-9"),
    ("[1-9]", "1-9"),
    ("H1–H6", "H1-6"),
)


def compact(key):
    """Shorten a key combo so the row fits the card.

    Only touches modifier and named-key spellings. Anything that is not a
    key combo -- Fish lists shell commands in this column -- comes through
    untouched, because there is nothing safe to shorten in `tmux
    kill-server`.
    """
    out = str(key)
    for long, short in KEY_SUBS:
        out = out.replace(long, short)
    # " + " is pure padding once the names are symbols: "Mod ⇧ ↵" reads as
    # well as "Mod + ⇧ + ↵" and is four characters shorter.
    out = out.replace(" + ", " ")
    return " ".join(out.split())


def fit(text, width):
    """Clip to `width` columns, marking the clip."""
    text = str(text)
    return text if len(text) <= width else text[: max(0, width - 1)] + "…"


def card_markup(title, items, *, cols, colors, note=None, danger=()):
    """The markup for one section card.

    `cols` is the card's inner width in characters. A PopupText draws at
    (0, 0) of its own rect and its background IS the card, so there is no
    padding property to set -- the inset has to come from the markup, which
    is why every line starts with PAD_CHARS spaces and the block starts one
    blank row down.

    `danger` is a predicate or a tuple of substrings; matching rows get the
    warm accent instead of the green one.
    """
    pad = " " * PAD_CHARS
    is_danger = danger if callable(danger) else (
        lambda label: any(d in label.lower() for d in danger)
    )

    lines = [""]  # top inset: the card is v_align="top"
    lines.append(
        f'{pad}<span foreground="{colors["purple"]}" weight="bold">'
        f"{esc(fit(title, cols))}</span>"
    )
    if note:
        lines.append(
            f'{pad}<span foreground="{colors["muted"]}" style="italic">'
            f"{esc(fit(note, cols))}</span>"
        )
    lines.append(f'{pad}<span foreground="{colors["line"]}">{"─" * cols}</span>')

    for label, key in items:
        key_text = compact(key)
        # Right-align the key, and give the label whatever is left. One
        # space is the minimum gap; below that the label is clipped rather
        # than allowed to push the key off the card.
        room = cols - len(key_text) - 1
        label_text = fit(label, max(1, room))
        gap = max(1, cols - len(label_text) - len(key_text))
        colour = colors["red"] if is_danger(label) else colors["green"]
        lines.append(
            f'{pad}<span foreground="{colors["fg"]}">{esc(label_text)}</span>'
            f'{" " * gap}'
            f'<span foreground="{colour}" weight="bold">{esc(key_text)}</span>'
        )

    return "\n".join(lines)


def card_rows(items, note=None):
    """How many text rows a card occupies: pad, title, [note], rule, items, pad."""
    return PAD_ROWS + 2 + (1 if note else 0) + len(items) + PAD_ROWS


# =============================================================================
# LAYOUT
# =============================================================================
def pack(sections, *, n_cols, popup_w, popup_h, line_px, char_px,
         has_note=lambda title: None, name="cheatsheet"):
    """Lay every section out as a card, paginating when a page fills up.

    `sections` is an ordered [(title, items), ...]; order is preserved, so
    related sections stay adjacent. `has_note(title)` returns the section's
    note line, or None.

    Returns a list of pages. Each page is a list of
    (title, items, note, cols, pos_x, pos_y, width, height) -- positions as
    fractions of the popup's inner box, `cols` the card's inner width in
    characters, ready to hand to PopupText.
    """
    in_w, in_h = popup_w - 2 * MARGIN, popup_h - 2 * MARGIN

    card_w_px = (in_w - (n_cols - 1) * CARD_GAP_PX) / n_cols
    cols = int(card_w_px / char_px) - 2 * PAD_CHARS

    top_px, bottom_px = GRID_TOP * in_h, GRID_BOTTOM * in_h
    grid_px = bottom_px - top_px

    # First fit, not "fill one column then move on". Strict sequential
    # packing left a card-sized hole under any section that missed the
    # bottom of its column by a few pixels -- Navigation overshot Basics'
    # column by 9px and the whole first column sat half empty. First fit
    # drops each card in the leftmost column that still has room, which
    # keeps reading order left-to-right and closes the holes.
    pages, page, tops = [], [], [top_px] * n_cols

    for title, items in sections:
        note = has_note(title)
        h_px = card_rows(items, note) * line_px

        if h_px > grid_px:
            # One card taller than the whole grid. It will still draw, and
            # it will still run off the bottom -- but now it says so.
            logger.warning(
                "%s: section %r is %d rows, taller than a full column "
                "(%d rows) -- split it.",
                name, title, card_rows(items, note), int(grid_px / line_px),
            )

        col = next(
            (c for c in range(n_cols) if tops[c] + h_px <= bottom_px), None
        )
        if col is None:
            pages.append(page)
            page, tops = [], [top_px] * n_cols
            col = 0

        page.append((
            title, items, note, cols,
            col * (card_w_px + CARD_GAP_PX) / in_w,
            tops[col] / in_h,
            card_w_px / in_w,
            h_px / in_h,
        ))
        tops[col] += h_px + CARD_GAP_PX

    if page:
        pages.append(page)
    return pages


# =============================================================================
# SELFTEST
#
# The original bug was invisible by construction -- nothing errors, the
# entries simply are not drawn -- so it survived until someone counted the
# lines on screen against the source. This measures instead: pango is asked
# for the real extents of every card at its real font size, and the result
# is checked against the popup it has to fit in.
#
#     python3 -m popups._cheatsheet_grid     (from ~/.config/qtile)
#
# Run by validate.sh, so an entry added to any sheet cannot quietly push
# another one off the bottom again.
# =============================================================================
SHEETS = ("QtileCheatsheet", "VimCheatsheet", "FishCheatsheet")

# The reference panel. Every sheet has to fit on the smallest screen this
# config supports, because that is the one it was designed on.
SCREEN_W, SCREEN_H = 1366, 768


def _font_charset(family):
    """The set of codepoint ranges `family` actually covers, via fontconfig."""
    import subprocess

    out = subprocess.run(
        ["fc-list", "--format=%{charset}\n", family],
        capture_output=True, text=True, timeout=10,
    ).stdout
    ranges = set()
    for line in out.split("\n"):
        for part in line.split():
            if "-" in part:
                lo, hi = part.split("-")
                ranges.add((int(lo, 16), int(hi, 16)))
            elif part:
                v = int(part, 16)
                ranges.add((v, v))
    return ranges


def _covered(charset, ch):
    c = ord(ch)
    return any(lo <= c <= hi for lo, hi in charset)


def selftest(sheets=SHEETS, verbose=True):
    """Return a list of failure strings; empty means every sheet fits."""
    import gi
    import re as _re

    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    from gi.repository import Pango, PangoCairo
    import cairo

    ctx = cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1))

    def extents(markup, size):
        lay = PangoCairo.create_layout(ctx)
        lay.set_font_description(Pango.FontDescription(f"{FONT} {size}"))
        lay.set_markup(markup, -1)
        return lay.get_pixel_size()

    failures = []

    # A silently-substituted font would break every width below, and the
    # symptom (CJK glyphs, nothing lines up) is exactly what this file
    # exists to stop. Check the family really resolves.
    import subprocess

    charset = None
    try:
        matched = subprocess.run(
            ["fc-match", "-f", "%{family}", FONT],
            capture_output=True, text=True, timeout=10,
        ).stdout
        if FONT.lower() not in matched.lower():
            failures.append(
                f"font {FONT!r} is not installed -- fc-match answers "
                f"{matched!r}, so every column would be misaligned"
            )
        charset = _font_charset(FONT)
    except Exception as e:  # fc-match missing: not worth failing over
        if verbose:
            print(f"  (could not inspect the font: {e})")

    for name in sheets:
        mod = __import__(f"popups.{name}", fromlist=["x"])
        W, H = mod.POPUP_W, mod.POPUP_H
        in_w, in_h = W - 2 * MARGIN, H - 2 * MARGIN
        footer_top = mod.FOOTER_Y * in_h
        pages = mod.layout_pages()

        if W > SCREEN_W or H > SCREEN_H:
            failures.append(
                f"{name}: popup is {W}x{H}, larger than the {SCREEN_W}x"
                f"{SCREEN_H} reference panel"
            )

        # Every glyph the popup draws must be in FONT. A missing one does
        # not error -- it falls back to another family at another width and
        # un-aligns the key column. Header and footer are checked too: the
        # legend is exactly where a hardcoded U+21B5 ↵ slipped past a
        # cards-only version of this check.
        def glyph_check(markup, where):
            if not charset:
                return
            plain = _re.sub(r"<[^>]*>", "", markup)
            missing = {
                c for c in plain if c not in "\n\t " and not _covered(charset, c)
            }
            if missing:
                names = ", ".join(f"U+{ord(c):04X}" for c in sorted(missing))
                failures.append(
                    f"{where}: {FONT} has no glyph for "
                    f"{''.join(sorted(missing))!r} ({names}) -- it would "
                    f"fall back and break alignment."
                )

        if hasattr(mod, "_header"):
            glyph_check(mod._header(0, pages), f"{name}/header")
        if hasattr(mod, "_footer"):
            glyph_check(mod._footer(pages), f"{name}/footer")

        for pageno, page in enumerate(pages, 1):
            for title, items, note, cols, _px, py, pw, ph in page:
                markup = mod.render_card(title, items, note, cols)
                where = f"{name} p{pageno}/{title}"
                glyph_check(markup, where)

                # A clipped row is a broken entry: "z 'file/folderna…" is
                # not a thing you can type. card_markup() clips rather than
                # letting the key spill off the card, which is the right
                # failure -- but it is still a failure, so say so.
                if len(fit(title, cols)) < len(title):
                    failures.append(f"{where}: title is clipped.")
                for label, key in items:
                    need = len(label) + 1 + len(compact(key))
                    if need > cols:
                        failures.append(
                            f"{where}: {label!r} + {compact(key)!r} needs "
                            f"{need} columns, card holds {cols} -- shorten "
                            f"it or widen the cards."
                        )

                w, h = extents(markup, mod.BODY_SIZE)
                card_w, card_h = pw * in_w, ph * in_h
                bottom = py * in_h + card_h
                where = f"{name} p{pageno}/{title}"

                if w > card_w:
                    failures.append(
                        f"{where}: text is {w:.0f}px wide, card is "
                        f"{card_w:.0f}px -- lower N_COLS or BODY_SIZE."
                    )
                if h > card_h + 2:
                    failures.append(
                        f"{where}: text is {h:.0f}px tall, card is "
                        f"{card_h:.0f}px -- LINE_PX is wrong for "
                        f"{mod.BODY_SIZE}pt."
                    )
                if bottom > footer_top:
                    failures.append(
                        f"{where}: overlaps the footer by "
                        f"{bottom - footer_top:.0f}px."
                    )
                if bottom > in_h:
                    failures.append(
                        f"{where}: {bottom - in_h:.0f}px BELOW the popup "
                        f"edge -- these entries never render."
                    )
        if verbose:
            n = sum(len(p) for p in pages)
            print(
                f"{name}: {W}x{H}, {mod.BODY_SIZE}pt, {mod.N_COLS} columns, "
                f"{n} cards over {len(pages)} page(s)"
            )

    return failures


if __name__ == "__main__":
    import sys

    bad = selftest()
    for line in bad:
        print("FAIL:", line, file=sys.stderr)
    print("cheatsheets: all cards fit" if not bad else f"{len(bad)} failure(s)")
    sys.exit(1 if bad else 0)
