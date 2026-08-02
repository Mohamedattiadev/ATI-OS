#!/usr/bin/env python3
"""Selection translator: type or select text, get a browsable result in rofi.

Speed
-----
This used to shell out to translate-shell four times in a row — `trans -id`
to detect the language, `trans -b` to translate, `trans` again for
alternatives and `trans -d` for the dictionary — each one a fresh awk
interpreter plus its own network round trip. Four sequential trips is why
the picker took several seconds to appear.

All of it now comes from a single request to the endpoint translate-shell
itself uses (`translate_a/single` with `dj=1`, which returns real JSON
instead of the positional-array format). One call returns the detected
source language, the sentence-by-sentence translation, the bilingual
dictionary, definitions, per-sense examples and synonyms — typically in
under 300 ms. `trans -b` remains as a fallback for when that call fails.

Two further tricks keep it feeling instant: results are cached on disk
(translations don't change), and the translation into the last-used target
language is prefetched in the background while the language picker is still
open, so the common case is already finished before you choose.

Input
-----
The primary selection only *prefills* the prompt now; previously a
non-empty selection was used silently and there was no way to look up a
word you were merely thinking of unless nothing was highlighted. The box is
always shown and always editable, and whole sentences are accepted — they
come back translated sentence by sentence.

Layout
------
Results are a three-column table — tag │ content │ note — drawn in a
monospace span so the separators actually line up under rofi's
proportional UI font. The content column is sized to the widest row it
has to hold, capped, so a one-word lookup gets a tight table and a
paragraph is not squeezed into a sliver.

Bidi
----
Arabic (and Hebrew/Persian/Urdu) rows used to come out mangled: pango takes
the paragraph direction from the first strong character, so one Arabic word
flipped the entire row and threw the latin labels to the wrong side. Every
piece of user text is now wrapped in FSI…PDI isolates, which lets each
fragment render in its own direction without disturbing the row.

Safety
------
Every shell call here used to be an f-string interpolated into
`shell=True`, so a selected word containing an apostrophe (`don't`,
`l'eau`, `it's`) broke the command outright. All subprocess calls pass
argument lists. Pango markup is escaped, so `&` and `<` in a selection no
longer corrupt the rofi rows.
"""

import hashlib
import html
import json
import os
import re
import subprocess as sp
import sys
import threading
import unicodedata
import urllib.parse
import urllib.request

# ---------------- Configuration ----------------
# Per-user, matching AtiScriptsV1/rofi_translator. A fixed /tmp path is
# owned by whichever account ran first; every other account's write to
# gemini.log below then fails with EACCES.
TMP_DIR = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/rofi-{os.getuid()}", "translator"
)
os.makedirs(TMP_DIR, exist_ok=True)

CACHE_DIR = os.path.expanduser("~/.cache/rofi_translator")
os.makedirs(CACHE_DIR, exist_ok=True)
LAST_LANG_FILE = os.path.join(CACHE_DIR, "last_lang")

SECRETS_FILE = os.path.expanduser("~/.config/secrets.env")
GEMINI_LOG = f"{TMP_DIR}/gemini.log"
# Kept in step with GEMINI_MODELS in rofi_common.sh.
GEMINI_MODELS = ("gemini-2.5-flash", "gemini-2.0-flash")

NOTIFY_TIMEOUT = 120000  # 2 min

LANG_NAMES = {
    "en": "English",
    "de": "German",
    "tr": "Turkish",
    "ar": "Arabic",
    "fr": "French",
    "it": "Italian",
    "es": "Spanish",
}
LANGS = list(LANG_NAMES)

# Scripts written right to left. Their rows need bidi isolation, and their
# transliteration is worth showing.
RTL_LANGS = {"ar", "he", "fa", "ur"}

# Unicode bidi isolates: text inside them keeps its own direction without
# setting the direction of the line it sits on.
FSI, PDI = "⁨", "⁩"

API_URL = "https://translate.googleapis.com/translate_a/single"

# Second opinion on "did you mean …?" — see spell_suggestion().
LT_API = "https://api.languagetool.org/v2/check"
LT_TIMEOUT = 6
SPELL_MAX_WORDS = 40
# LanguageTool wants a variant for some languages and a bare code for
# others; keys are what Google's detector returns.
LT_LANG = {
    "en": "en-US", "de": "de-DE", "pt": "pt-PT", "ca": "ca-ES",
    "fr": "fr", "es": "es", "it": "it", "nl": "nl", "ar": "ar",
    "tr": "tr", "ru": "ru", "pl": "pl", "uk": "uk", "sv": "sv",
    "da": "da", "el": "el", "fa": "fa", "ga": "ga", "ro": "ro",
    "sk": "sk", "sl": "sl", "ta": "ta", "ja": "ja", "zh": "zh-CN",
}
API_UA = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/122.0 Safari/537.36"
)
API_TIMEOUT = 8

# Colours follow whichever palette theme-apply has symlinked as
# themes/current-palette.rasi. They used to be doom-one literals, so
# switching theme recoloured the rofi frame and left the table blue and
# green regardless — pango markup cannot reference rofi theme variables,
# so every colour has to be resolved here instead.
sys.path.insert(0, os.path.expanduser("~/.config/AtiScriptsV1"))
try:
    from rofi_palette import load as load_palette
    PALETTE = load_palette()
except Exception:  # noqa: BLE001 — a missing helper must not stop a lookup
    PALETTE = {
        "text": "#bbc2cf", "head": "#61afef", "good": "#98c379",
        "bad": "#e06c75", "accent": "#e06c75", "muted": "#9298a4",
        "dim": "#727782", "example": "#8ab8e1", "syn": "#a8c3a0",
    }

COLOR_WORD = PALETTE["accent"]      # pronunciation, notification headings
COLOR_TYPE = PALETTE["muted"]       # the original half of a sentence pair
COLOR_TRANS = PALETTE["good"]       # translations
COLOR_EXAMPLES = PALETTE["example"]
COLOR_SYN = PALETTE["syn"]
COLOR_BAD = PALETTE["bad"]          # the "did you mean" correction
COLOR_HEAD = PALETTE["head"]        # section rules
COLOR_DIM = PALETTE["dim"]          # gutter tags, separators, notes
COLOR_TEXT = PALETTE["text"]        # definitions

# Table geometry. The tag column is fixed; the content column is sized to
# what it actually has to hold, between these bounds. Rows wider than
# COL_MAX are *not* cut off — they simply overflow past the note column,
# because hiding half a definition behind an ellipsis was worse than one
# row whose third column starts late.
COL_TAG = 6
COL_MIN = 24
COL_MAX = 96
SEP = "│"

# Wider than the 45% the shared theme uses, because the table needs the
# room, but no wider than rofi/themes/kill-large.rasi — a near-full-screen
# window for a word lookup was overwhelming.
WIDE_WINDOW = "window {width: 75%;}"

# Rofi exit codes for -kb-custom-N, N = code - 9.
#
# Ctrl first, Alt as an alias: this machine's Alt key is dead in hardware
# and only exists as an xmodmap remap of Caps Lock (see the comment on
# `mod2` in qtile's config.py), so an Alt-only binding is one xmodmap
# hiccup away from doing nothing at all. Ctrl+n/Ctrl+l are taken by
# row-down and mode-complete, hence t (text) and o (other language).
ROFI_NEW_TEXT = 10   # Ctrl+t / Alt+n
ROFI_NEW_LANG = 11   # Ctrl+o / Alt+l
CUSTOM_KEYS = [
    "-kb-custom-1", "Control+t,Alt+n",
    "-kb-custom-2", "Control+o,Alt+l",
]

# Ctrl+u/Ctrl+w wipe the whole input line. rofi ships Ctrl+w as
# clear-line and Ctrl+u as remove-to-start-of-line; binding both to
# clear-line means unbinding remove-to-sol first, or rofi refuses to
# start on the duplicate.
CLEAR_KEYS = [
    "-kb-clear-line", "Control+u,Control+w",
    "-kb-remove-to-sol", "",
]

# Part-of-speech abbreviations, so the gutter stays one narrow column
# instead of "adjective" pushing the content across the row.
POS_SHORT = {
    "noun": "n.", "verb": "v.", "adjective": "adj.", "adverb": "adv.",
    "pronoun": "pron.", "preposition": "prep.", "conjunction": "conj.",
    "interjection": "int.", "exclamation": "int.", "abbreviation": "abbr.",
}

# ---------------- Shell helpers ----------------
def run_full(argv, stdin_text=None, timeout=30):
    """Run argv (a list, never a shell string) → (exit code, stdout)."""
    try:
        p = sp.run(
            argv,
            input=stdin_text.encode() if stdin_text is not None else None,
            stdout=sp.PIPE,
            stderr=sp.DEVNULL,
            timeout=timeout,
        )
        return p.returncode, p.stdout.decode("utf-8", "replace").strip()
    except (sp.TimeoutExpired, FileNotFoundError, OSError):
        return -1, ""


def run(argv, stdin_text=None, timeout=30):
    """As run_full, for the callers that only care about the output."""
    return run_full(argv, stdin_text, timeout)[1]


def run_bg(argv):
    """Fire and forget — used for audio playback."""
    try:
        sp.Popen(argv, stdout=sp.DEVNULL, stderr=sp.DEVNULL)
    except (FileNotFoundError, OSError):
        pass


def notify(title, msg, timeout=NOTIFY_TIMEOUT):
    run_bg(["notify-send", "-t", str(timeout), title, msg])


def set_clipboard(text):
    """Copy without hanging.

    xclip forks a daemon that stays alive to serve the selection, and it
    inherits whatever pipes it was given. Running it through the normal
    helper captured its stdout, so the parent waited for an EOF that
    only arrives when some *other* application takes the clipboard —
    minutes later, or never.

    Nobody noticed while copying was the last thing the script did, but
    Ctrl+t and Ctrl+o copy the highlighted row and then carry on: the
    picker closed, the copy blocked, and the next screen never opened.
    It looked exactly like a dead keybinding. No pipe, no wait.
    """
    try:
        p = sp.Popen(
            ["xclip", "-selection", "clipboard"],
            stdin=sp.PIPE, stdout=sp.DEVNULL, stderr=sp.DEVNULL,
        )
        p.stdin.write(text.encode())
        p.stdin.close()
    except (FileNotFoundError, OSError, BrokenPipeError):
        pass


def esc(text):
    """Escape for pango markup. The old code never did this, so any word
    containing & or < produced malformed rows that rofi rendered raw."""
    return html.escape(text, quote=False)


def iso(text):
    """Isolate a text run so its direction can't flip the whole row."""
    return FSI + text + PDI


def strip_bidi(text):
    """Isolates are display-only — they must never reach the clipboard."""
    return text.replace(FSI, "").replace(PDI, "")


def load_secrets():
    """Mirror of rofi_common.sh's load_secrets for the Python side."""
    if not os.path.isfile(SECRETS_FILE):
        return
    try:
        with open(SECRETS_FILE, encoding="utf-8") as f:
            for line in f:
                key, sep, val = line.partition("=")
                key = key.strip()
                if not sep or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
                    continue
                os.environ.setdefault(key, val.strip().strip("\"'"))
    except OSError:
        pass


# ---------------- Translation backend ----------------
def cache_path(text, target):
    key = hashlib.sha1(f"{target}\0{text}".encode()).hexdigest()
    return os.path.join(CACHE_DIR, f"{key}.json")


def api_lookup(text, target):
    """One request for everything: translation, dictionary, definitions,
    examples, synonyms and the detected source language."""
    params = [
        ("client", "gtx"),
        ("sl", "auto"),
        ("tl", target),
        ("dj", "1"),          # JSON objects instead of positional arrays
        ("dt", "t"),          # sentence translation
        ("dt", "bd"),         # bilingual dictionary
        ("dt", "md"),         # definitions
        ("dt", "ex"),         # examples
        ("dt", "ss"),         # synonyms
        ("dt", "rm"),         # transliteration
        ("dt", "qc"),         # spelling correction of the query itself
        ("q", text),
    ]
    url = f"{API_URL}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": API_UA})
    with urllib.request.urlopen(req, timeout=API_TIMEOUT) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def lookup(text, target):
    """Cached API lookup, degrading to `trans -b` when the call fails.

    Translations of a fixed string don't change, so the cache never
    expires; a repeat of a word you looked up before renders with no
    network at all.
    """
    path = cache_path(text, target)
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        pass

    try:
        data = api_lookup(text, target)
    except Exception:  # noqa: BLE001 — any failure falls back to trans
        plain = run(["trans", "-b", f":{target}", text], timeout=20)
        if not plain:
            return {}
        return {"sentences": [{"trans": plain, "orig": text}], "src": "auto"}

    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
    except OSError:
        pass
    return data


def sentence_pairs(data):
    """(original, translation) per sentence, skipping the transliteration
    pseudo-sentence the API appends when dt=rm is requested."""
    pairs = []
    for s in data.get("sentences", []):
        tr = (s.get("trans") or "").strip()
        orig = (s.get("orig") or "").strip()
        if tr:
            pairs.append((orig, tr))
    return pairs


def translit(data):
    for s in data.get("sentences", []):
        if s.get("translit"):
            return s["translit"].strip()
    return ""


def spell_suggestion(text, data):
    """"Did you mean …?" for the text you typed.

    Two sources, because neither alone is good enough. Google returns a
    correction in the same response as the translation (free, no extra
    request) but only sometimes: `recieve` and `hous` come back
    corrected, `beatiful` does not — that one it decides is Haitian
    Creole and translates as-is. LanguageTool catches what Google misses,
    at the cost of one short request, so it is only asked when Google had
    nothing to say.

    Only misspellings are applied. LanguageTool also reports style and
    agreement issues, and silently rewriting someone's grammar under a
    "did you mean" label is not what was asked for — that is what
    dm-spellcheck is for.
    """
    google = (data.get("spell") or {}).get("spell_res", "").strip()
    if google and google.lower() != text.lower():
        return google

    if len(text.split()) > SPELL_MAX_WORDS:
        return ""

    src = data.get("src", "")
    # LanguageTool's own detection is wild on short input (it calls
    # `gelest` Dutch), so the language Google already detected is passed
    # in explicitly. An unknown one means no check rather than a guess.
    language = LT_LANG.get(src, "")
    if not language and text.isascii():
        # A typo throws the detector off precisely when the check is most
        # needed — `beatiful` comes back as Haitian Creole, which
        # LanguageTool does not support, so the word would go unchecked.
        # Plain ASCII is overwhelmingly English here; assume so rather
        # than give up.
        language = "en-US"
    if not language:
        return ""

    path = cache_path(text, f"{language}#spell")
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        pass

    payload = urllib.parse.urlencode(
        {"text": text, "language": language}
    ).encode()
    try:
        req = urllib.request.Request(
            LT_API,
            data=payload,
            headers={"User-Agent": API_UA,
                     "Content-Type": "application/x-www-form-urlencoded"},
        )
        with urllib.request.urlopen(req, timeout=LT_TIMEOUT) as r:
            matches = json.loads(
                r.read().decode("utf-8", "replace")
            ).get("matches", [])
    except Exception:  # noqa: BLE001 — no suggestion is a fine outcome
        return ""

    fixed = text
    # Back to front, so each offset is still valid when its turn comes.
    for m in sorted(matches, key=lambda m: m["offset"], reverse=True):
        if m.get("rule", {}).get("issueType") != "misspelling":
            continue
        reps = [r.get("value", "") for r in m.get("replacements", []) if r]
        if reps:
            off, length = m["offset"], m["length"]
            fixed = fixed[:off] + reps[0] + fixed[off + length:]

    result = fixed if fixed != text else ""
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False)
    except OSError:
        pass
    return result


def translate_lines(lines, src, target):
    """Translate several short strings in one request.

    Repeating the `q` parameter looks like it should work but the endpoint
    silently answers only the first one, so the lines are joined with
    newlines instead — the API preserves them, and splitting the result
    back apart recovers the 1:1 mapping. Used for the usage examples,
    which are otherwise English-only and half useless when you are
    learning the target language.
    """
    lines = [l for l in lines if l]
    if not lines:
        return {}

    joined = "\n".join(lines)
    path = cache_path(joined, f"{target}#ex")
    try:
        with open(path, encoding="utf-8") as f:
            out = json.load(f)
        return dict(zip(lines, out))
    except (OSError, ValueError):
        pass

    params = [
        ("client", "gtx"), ("sl", src or "auto"), ("tl", target),
        ("dj", "1"), ("dt", "t"), ("q", joined),
    ]
    url = f"{API_URL}?{urllib.parse.urlencode(params)}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": API_UA})
        with urllib.request.urlopen(req, timeout=API_TIMEOUT) as r:
            data = json.loads(r.read().decode("utf-8", "replace"))
    except Exception:  # noqa: BLE001 — examples stay monolingual, no worse
        return {}

    whole = "".join(s.get("trans") or "" for s in data.get("sentences", []))
    out = [part.strip() for part in whole.split("\n")]
    if len(out) != len(lines):
        # A line the API decided was two sentences would desync the
        # mapping; better no translations than wrong ones.
        return {}

    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False)
    except OSError:
        pass
    return dict(zip(lines, out))


# ---------------- Gemini (optional enrichment) ----------------
def call_gemini(prompt):
    key = os.environ.get("GEMINI_API_KEY", "")
    if not key:
        return ""
    payload = json.dumps({"contents": [{"parts": [{"text": prompt}]}]}).encode()
    for model in GEMINI_MODELS:
        url = (
            "https://generativelanguage.googleapis.com/v1beta/models/"
            f"{model}:generateContent"
        )
        req = urllib.request.Request(
            url,
            data=payload,
            headers={
                "Content-Type": "application/json",
                # Header rather than ?key= so the key stays out of `ps`.
                "x-goog-api-key": key,
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=25) as r:
                data = json.loads(r.read().decode())
            text = data["candidates"][0]["content"]["parts"][0]["text"]
            if text:
                return text
        except Exception as e:  # noqa: BLE001 — log the reason, try next model
            try:
                with open(GEMINI_LOG, "a", encoding="utf-8") as f:
                    f.write(f"{model}: {e}\n")
            except OSError:
                pass
    return ""


def clean_markup(text):
    text = re.sub(r"<[^>]+>", "", text)
    text = esc(text)
    text = re.sub(r"\*\*(.*?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<!\w)_(.*?)_(?!\w)", r"<i>\1</i>", text)
    text = re.sub(r"`(.*?)`", r"‘\1’", text)
    text = text.replace("•", "▪")
    return re.sub(r"\n{3,}", "\n\n", text).strip()


# ---------------- Rofi steps ----------------
def ask_text(prefill=None):
    """Always show the box; the selection is a prefill, not a decision.

    `prefill` is what to start with — the X selection on the first pass,
    and whatever was looked up last when coming back round for another
    word, so Ctrl+u wipes it and you type over the top.
    """
    if prefill is None:
        prefill = strip_bidi(
            run(["xclip", "-o", "-selection", "primary"])
        ).strip()
    return run(
        ["rofi", "-dmenu", "-i", "-p", "Translate",
         "-filter", prefill, *CLEAR_KEYS,
         "-mesg", "word or sentence · <b>Ctrl+u</b> clear · <b>↵</b> translate"],
        stdin_text="",
        timeout=300,
    ).strip()


def read_last_lang():
    try:
        with open(LAST_LANG_FILE, encoding="utf-8") as f:
            lang = f.read().strip()
        return lang if lang in LANGS else ""
    except OSError:
        return ""


def write_last_lang(lang):
    try:
        with open(LAST_LANG_FILE, "w", encoding="utf-8") as f:
            f.write(lang)
    except OSError:
        pass


def ask_lang(last):
    """Language picker, most recent target first so ↵ repeats it."""
    order = ([last] if last else []) + [l for l in LANGS if l != last]
    rows = [f"{code}  —  {LANG_NAMES[code]}" for code in order]
    picked = run(
        ["rofi", "-dmenu", "-i", "-format", "i", "-p", "Into"],
        stdin_text="\n".join(rows),
        timeout=300,
    )
    return order[int(picked)] if picked.isdigit() and int(picked) < len(order) else ""


# ---------------- Table rendering ----------------
def width_of(text):
    """Display width: wide CJK counts double, combining marks (Arabic
    vowel points, for one) count zero. Plain len() would misalign both."""
    total = 0
    for ch in text:
        if unicodedata.combining(ch) or ch in (FSI, PDI):
            continue
        total += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return total




def render_table(cells):
    """Turn collected cells into aligned pango rows plus their payloads.

    The content column is measured rather than fixed: sized to the widest
    row it has to carry, clamped to [COL_MIN, COL_MAX]. A one-word lookup
    therefore gets a compact table instead of acres of padding, and a
    paragraph is not crushed into a narrow strip. Nothing is ever cut
    short — a row past COL_MAX keeps its full text and pushes its own
    note column right; only that row loses the alignment, and no content
    disappears behind an ellipsis.

    Everything is wrapped in <tt>. Rofi's UI font is proportional, so
    without a monospace span the separators wander by several pixels a
    row and the table stops reading as one.
    """
    content = [c for c in cells if "head" not in c]
    natural = max((width_of(c["main"]) for c in content), default=COL_MIN)
    width = max(COL_MIN, min(COL_MAX, natural))
    notes = max((width_of(c["note"]) for c in content), default=0)
    # Section rules run the full width of the table, note column included,
    # so they read as rules and not as stubs over the first two columns.
    span = COL_TAG + 3 + width + (3 + min(notes, 40) if notes else 0)

    rows, payloads = [], []
    for c in cells:
        if "head" in c:
            title = f" {c['head']} "
            fill = max(0, span - width_of(title) - 2)
            rows.append(
                f"<tt><span foreground='{COLOR_HEAD}'><b>──{esc(title)}"
                f"{'─' * fill}</b></span></tt>"
            )
            payloads.append(c["head"])
            continue

        main = c["main"]
        pad = " " * max(0, width - width_of(main))
        style_open = "".join(f"<{s}>" for s in c["style"])
        style_close = "".join(f"</{s}>" for s in reversed(c["style"]))
        line = (
            f"<span foreground='{COLOR_DIM}'>{esc(c['tag'].ljust(COL_TAG))}"
            f"{SEP} </span>"
            f"<span foreground='{c['color']}'>{style_open}"
            f"{iso(esc(main))}{style_close}</span>{pad}"
        )
        if c["note"]:
            line += (
                f"<span foreground='{COLOR_DIM}'> {SEP} "
                f"{iso(esc(c['note']))}</span>"
            )
        rows.append(f"<tt>{line}</tt>")
        payloads.append(strip_bidi(c["payload"]))

    return rows, payloads


# ---------------- Row building ----------------
def build_rows(text, data, target, suggestion=""):
    """Collect the result as table cells: tag │ content │ note.

    The picker used to be one flat run of rows in which a translation, a
    definition and an example all looked much alike. Each row now says
    what it is in the tag column, and the columns line up down the list.

    Returns (rows, payloads, suggest_index) — the index of the "did you
    mean" row, or -1, so the caller can tell "re-translate this instead"
    apart from an ordinary copy.
    """
    cells = []

    def add(tag, main, note="", color=COLOR_TEXT, style=(), payload=None):
        if not main:
            return
        cells.append({
            "tag": tag, "main": main, "note": note,
            "color": color, "style": style,
            "payload": payload if payload is not None else main,
        })

    def section(title):
        cells.append({"head": title})

    pairs = sentence_pairs(data)
    full = " ".join(tr for _, tr in pairs).strip()
    src = data.get("src", "auto")
    rom = translit(data)

    # Typing rubbish ("asesd") is not an error the API reports: it hands
    # back the input untouched, which the table then presented in
    # confident green as though it were an answer. A word it actually
    # knows comes with a dictionary or definitions even when the spelling
    # matches across languages ("Hotel", "taxi"), so requiring all three
    # to be empty keeps real words out of this branch.
    unchanged = (
        bool(full)
        and full.strip().lower() == text.strip().lower()
        and not data.get("dict")
        and not data.get("definitions")
    )

    # ---- Did you mean …? ----
    # First, before the translation of what was actually typed, because a
    # typo makes everything under it suspect.
    suggest_index = -1
    if suggestion:
        section("Did you mean?")
        add("✎", suggestion, "↵ translate this instead", COLOR_BAD, ("b",))
        suggest_index = len(cells) - 1

    # ---- Translation ----
    if full:
        section(f"{LANG_NAMES.get(src, src)} → {LANG_NAMES.get(target, target)}")
        if unchanged:
            add(
                target, full,
                "came back unchanged — not a word?", COLOR_BAD, ("b",),
            )
            if not suggestion:
                # No translation and nothing to suggest: say so plainly
                # rather than leave a single ambiguous row on screen.
                add(
                    "!", f"no result for “{text}”",
                    "Ctrl+t to type it again", COLOR_DIM, (), text,
                )
        else:
            add(target, full, "translation", COLOR_TRANS, ("b",))
        if rom and target in RTL_LANGS:
            add("say", rom, "pronunciation", COLOR_WORD, ("i",))

    # Sentence-by-sentence, each shown in both languages, so a paragraph
    # is usable line by line and not just as one blob.
    if len(pairs) > 1:
        section("Sentences")
        for i, (orig, tr) in enumerate(pairs, 1):
            add(f"{i}. {src}", orig, "", COLOR_TYPE)
            add(f"   {target}", tr, "", COLOR_TRANS)

    # ---- Other renderings, grouped by part of speech ----
    dict_blocks = [b for b in data.get("dict", []) if b.get("entry")]
    if dict_blocks:
        section("Other renderings")
    for block in dict_blocks:
        pos = block.get("pos", "")
        shown = 0
        for entry in block.get("entry", []):
            word = entry.get("word", "")
            if not word or word == full or shown >= 6:
                continue
            shown += 1
            add(
                POS_SHORT.get(pos, pos[:4]) if pos else "",
                word,
                ", ".join(entry.get("reverse_translation", [])[:4]),
                COLOR_TRANS,
            )

    # ---- Definitions, with their synonyms and bilingual examples ----
    syn_by_def = {}
    for block in data.get("synsets", []):
        for entry in block.get("entry", []):
            did = entry.get("definition_id")
            if did:
                syn_by_def.setdefault(did, []).extend(entry.get("synonym", []))

    ex_by_def = {}
    for ex in data.get("examples", {}).get("example", []):
        did = ex.get("definition_id")
        clean = re.sub(r"<[^>]+>", "", ex.get("text", "")).strip()
        if did and clean and clean not in ex_by_def.get(did, []):
            ex_by_def.setdefault(did, []).append(clean)

    # Collect every example first so all of them are translated in a
    # single extra request rather than one request per sense.
    senses = []
    for block in data.get("definitions", [])[:4]:
        pos = block.get("pos", "")
        for entry in block.get("entry", [])[:6]:
            gloss = entry.get("gloss", "").strip()
            if not gloss:
                continue
            did = entry.get("definition_id")
            samples = []
            if entry.get("example"):
                samples.append(entry["example"].strip())
            samples += [e for e in ex_by_def.get(did, []) if e not in samples]
            senses.append((pos, gloss, syn_by_def.get(did, [])[:6], samples[:2]))

    loose = []
    seen_ex = {s for _, _, _, samples in senses for s in samples}
    for ex in data.get("examples", {}).get("example", []):
        clean = re.sub(r"<[^>]+>", "", ex.get("text", "")).strip()
        if clean and clean not in seen_ex:
            seen_ex.add(clean)
            loose.append(clean)
    loose = loose[:6]

    translated = translate_lines(
        [s for _, _, _, samples in senses for s in samples] + loose,
        src, target,
    )

    def example_rows(sample):
        add(f"  {src}", f"“{sample}”", "", COLOR_EXAMPLES, payload=sample)
        other = translated.get(sample, "")
        if other:
            add(f"  {target}", f"“{other}”", "", COLOR_TRANS, payload=other)

    if senses:
        section("Definitions")
    for i, (pos, gloss, syns, samples) in enumerate(senses, 1):
        add(f"{i}.", gloss, POS_SHORT.get(pos, pos))
        if syns:
            add("  syn", ", ".join(syns), "", COLOR_SYN, ("i",))
        for sample in samples:
            example_rows(sample)

    if loose:
        section("More examples")
        for sample in loose:
            example_rows(sample)

    rows, payloads = render_table(cells)
    return rows, payloads, suggest_index


# ---------------- Main ----------------
def show(text, target):
    """Look a text up and show the picker. Returns what to do next:
    ("quit", None), ("text", prefill) for another word, ("lang", text) to
    translate the same thing into a different language, or ("retry",
    corrected) when the "did you mean" row was taken."""
    data = lookup(text, target)
    suggestion = spell_suggestion(text, data)
    pairs = sentence_pairs(data)
    full = " ".join(tr for _, tr in pairs).strip()
    src_lang = data.get("src", "auto")

    # Gemini enrichment runs in the background so the picker is instant.
    # It only ever adds a notification; the picker never waits on it.
    def enrich():
        if not (full and os.environ.get("GEMINI_API_KEY")):
            return
        syn = call_gemini(
            f"Give 5 concise synonyms for '{full}' in {target}. "
            "Comma separated, no preamble."
        )
        ex = call_gemini(
            f"Write 3 natural example sentences in {target} using "
            f"'{full}', each followed by its English translation in "
            "parentheses. Number them '1. ', '2. ', '3. '. No preamble."
        )
        if not (syn or ex):
            return
        body = (
            f"<b><span color='{COLOR_HEAD}'>Text:</span></b> "
            f"<span color='{COLOR_WORD}'>{iso(esc(text))}</span>\n"
            f"<b><span color='{COLOR_TRANS}'>Translation:</span></b> "
            f"<span color='{COLOR_TRANS}'>{iso(esc(full))}</span>\n"
        )
        if syn:
            body += f"\n💡 <b>Synonyms:</b>\n{iso(clean_markup(syn))}\n"
        if ex:
            body += f"\n🗣️ <b>Examples:</b>\n{iso(clean_markup(ex))}"
        notify(f"🌐 {esc(text)} ({target})", f"<span font='11'>{body}</span>")

    threading.Thread(target=enrich, daemon=True).start()

    rows, payloads, suggest_index = build_rows(text, data, target, suggestion)

    if not rows:
        notify("Translator", f"No results for “{esc(text)}”", 8000)
        return "text", text

    short = text if len(text) <= 60 else text[:57] + "…"
    mesg = (
        f"<b>{iso(esc(short))}</b> · {src_lang}→{target} · "
        "<b>↵</b> copy · <b>Ctrl+t</b> new text · <b>Ctrl+o</b> language · "
        "<b>Esc</b> quit"
    )
    code, chosen = run_full(
        [
            "rofi", "-dmenu", "-i", "-markup-rows", "-format", "i",
            "-p", f"{src_lang}→{target}", "-mesg", mesg,
            "-theme-str", WIDE_WINDOW, *CUSTOM_KEYS,
        ],
        stdin_text="\n".join(rows),
        timeout=600,
    )

    # -format i returns the index, so no fragile regex un-parsing of the
    # markup is needed to recover what the user actually picked.
    if chosen.isdigit() and 0 <= int(chosen) < len(payloads):
        index = int(chosen)
        if index == suggest_index and code == 0:
            # "Did you mean" is an instruction, not something to copy.
            return "retry", suggestion
        picked = payloads[index]
        set_clipboard(picked)
        notify("📋 Copied", esc(picked), 4000)

    if code == ROFI_NEW_TEXT:
        return "text", text
    if code == ROFI_NEW_LANG:
        return "lang", text
    return "quit", None


def main():
    load_secrets()

    text = ask_text()
    if not text:
        return 0

    target = None
    while True:
        # Start the likely lookup before the language is even chosen — by
        # the time the picker closes on the usual target, it is in hand.
        last = read_last_lang()
        warmer = None
        if last:
            warmer = threading.Thread(
                target=lookup, args=(text, last), daemon=True
            )
            warmer.start()

        if target is None:
            target = ask_lang(last)
            if not target:
                return 0
            write_last_lang(target)

        # The warm-up writes to the disk cache, which show() then reads;
        # joining it first keeps the two from firing the same request
        # twice when the picker was closed quickly.
        if target == last and warmer:
            warmer.join(timeout=API_TIMEOUT + 2)

        action, payload = show(text, target)
        if action == "quit":
            return 0
        if action == "lang":
            # Same text, different language: re-ask on the next pass.
            target = None
            continue
        if action == "retry":
            # Corrected spelling, same language, straight back in.
            text = payload
            continue
        # Another word, same language, prefilled with the last one so
        # Ctrl+u wipes it and you type straight over the top.
        text = ask_text(payload)
        if not text:
            return 0


if __name__ == "__main__":
    sys.exit(main())
