#!/usr/bin/env python3
"""Selection translator: pick a word, get a browsable dictionary in rofi.

Dictionary source
-----------------
This used to scrape WordReference. That path is dead: the site now answers
this host with HTTP 418 for every request — plain UA, full Chrome UA, with
and without Accept headers, over both http and https, from urllib *and*
curl. It is a hard block, not a header problem, so no amount of patching
the request would have brought it back. Every lookup therefore fell into
the bare `except` at the bottom and silently degraded to a one-word
`trans -b` dump into the clipboard, with no picker at all.

translate-shell's own `-d` output replaces it: part-of-speech tagged
definitions, per-sense synonyms and real usage examples, no scraping and
nothing to get blocked. Gemini is now strictly optional enrichment layered
in afterwards — with no API key present the picker is still fully useful,
which was not true before.

Safety
------
Every shell call here used to be an f-string interpolated into
`shell=True`, so a selected word containing an apostrophe (`don't`,
`l'eau`, `it's`) broke the command outright. All subprocess calls now pass
argument lists. Pango markup is escaped, so `&` and `<` in a selection no
longer corrupt the rofi rows.
"""

import html
import json
import os
import re
import shutil
import subprocess as sp
import sys
import threading
import urllib.request

# ---------------- Configuration ----------------
TMP_DIR = "/tmp/translator"
os.makedirs(TMP_DIR, exist_ok=True)

SECRETS_FILE = os.path.expanduser("~/.config/secrets.env")
GEMINI_LOG = f"{TMP_DIR}/gemini.log"
# Kept in step with GEMINI_MODELS in rofi_common.sh.
GEMINI_MODELS = ("gemini-2.5-flash", "gemini-2.0-flash")

NOTIFY_TIMEOUT = 120000  # 2 min

# Resolved at runtime rather than hardcoded: this pointed at
# ~/.local/bin/piper while piper actually lives in /usr/bin, so German
# TTS never once fired.
PIPER_CMD = shutil.which("piper")
PIPER_VOICE_DE = os.path.expanduser(
    "~/.config/piper-voices/de_DE-thorsten-high.onnx"
)

LANGS = ["en", "de", "tr", "ar", "fr", "it", "es"]

# Colors (doom-one)
COLOR_WORD = "#61afef"      # blue
COLOR_TYPE = "#abb2bf"      # gray
COLOR_TRANS = "#98c379"     # green
COLOR_EXAMPLES = "#87CEEB"  # light blue
COLOR_SYN = "#ADFF2F"       # yellow-green
COLOR_HEAD = "#FFD700"      # gold


# ---------------- Shell helpers ----------------
def run(argv, stdin_text=None, timeout=30):
    """Run argv (a list, never a shell string) and return stripped stdout."""
    try:
        p = sp.run(
            argv,
            input=stdin_text.encode() if stdin_text is not None else None,
            stdout=sp.PIPE,
            stderr=sp.DEVNULL,
            timeout=timeout,
        )
        return p.stdout.decode("utf-8", "replace").strip()
    except (sp.TimeoutExpired, FileNotFoundError, OSError):
        return ""


def run_bg(argv):
    """Fire and forget — used for audio playback."""
    try:
        sp.Popen(argv, stdout=sp.DEVNULL, stderr=sp.DEVNULL)
    except (FileNotFoundError, OSError):
        pass


def notify(title, msg, timeout=NOTIFY_TIMEOUT):
    run_bg(["notify-send", "-t", str(timeout), title, msg])


def esc(text):
    """Escape for pango markup. The old code never did this, so any word
    containing & or < produced malformed rows that rofi rendered raw."""
    return html.escape(text, quote=False)


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
def detect_lang(word):
    got = run(["trans", "-b", "-id", word], timeout=20)
    return got.splitlines()[0].strip() if got else "auto"


def translate(word, target):
    return run(["trans", "-b", f":{target}", word], timeout=25)


def alternatives(word, src, target):
    """Secondary renderings, e.g. house -> Haus, Zuhause."""
    out = run(
        [
            "trans", "-no-ansi",
            "-show-original", "n", "-show-prompt-message", "n",
            "-show-languages", "n", "-show-original-dictionary", "n",
            "-show-dictionary", "n", "-show-alternatives", "y",
            f"{src}:{target}", word,
        ],
        timeout=25,
    )
    alts = []
    for line in out.splitlines():
        if line.startswith(("    ", "\t")):
            for piece in line.strip().split(","):
                piece = piece.strip()
                if piece and piece not in alts:
                    alts.append(piece)
    return alts


def dictionary(word, src, target):
    """Parse `trans -d` into (pos, definition, example, synonyms) records.

    The output is indentation-structured and stable: part of speech at
    column 0, senses at 4, examples and per-sense synonyms at 8.
    """
    out = run(["trans", "-d", "-no-ansi", f"{src}:{target}", word], timeout=30)
    if not out:
        return []

    entries = []
    section = None
    pos = ""
    current = None

    for raw in out.splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        text = line.strip()

        if indent == 0:
            low = text.lower()
            if low.startswith("definitions of"):
                section = "def"
                pos = ""
            elif low == "synonyms":
                section = "syn"
                pos = ""
            elif low == "examples":
                section = "ex"
                pos = ""
            elif text.startswith("["):
                continue
            elif section == "def":
                pos = text  # noun / verb / adjective
            continue

        if section == "def":
            if indent == 4 and text.startswith("Synonyms:"):
                if current:
                    current["syn"] = text[len("Synonyms:"):].strip()
            elif indent == 4:
                current = {"pos": pos, "def": text, "ex": "", "syn": ""}
                entries.append(current)
            elif indent >= 8 and text.startswith("-") and current:
                current["ex"] = text.lstrip("- ").strip().strip('"')

    return entries


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


# ---------------- TTS ----------------
def play_tts(text, lang):
    if not text:
        return
    if lang.startswith("de") and PIPER_CMD and os.path.isfile(PIPER_VOICE_DE):
        wav = f"{TMP_DIR}/tts_de.wav"
        run([PIPER_CMD, "--model", PIPER_VOICE_DE, "-f", wav], stdin_text=text)
        if os.path.isfile(wav):
            run_bg(["mpv", "--really-quiet", wav])
            return
    if shutil.which("gtts-cli"):
        mp3 = f"{TMP_DIR}/tts.mp3"
        run(
            ["gtts-cli", "-l", lang if lang in LANGS else "en", text,
             "-o", mp3],
            timeout=25,
        )
        if os.path.isfile(mp3):
            run_bg(["mpv", "--really-quiet", mp3])
            return
    if shutil.which("espeak-ng"):
        run_bg(["espeak-ng", "-v", lang, text])


# ---------------- Main ----------------
def main():
    load_secrets()

    word = run(["xclip", "-o", "-selection", "primary"]).strip()
    if not word:
        # Nothing highlighted is a normal way to reach this, not an error:
        # you often want to look up a word you are thinking of rather than
        # one already on screen. Ask for it instead of bailing out.
        word = run(
            ["rofi", "-dmenu", "-i", "-p", "Translate", "-mesg",
             "nothing selected — type a word"],
            stdin_text="",
            timeout=300,
        ).strip()
    if not word:
        return 0

    src_lang = detect_lang(word)
    target_lang = run(
        ["rofi", "-dmenu", "-i", "-p", f"Translate {src_lang} →"],
        stdin_text="\n".join(LANGS),
        timeout=300,
    )
    if not target_lang:
        return 0

    translation = translate(word, target_lang)

    # Gemini enrichment runs in the background so the picker is instant.
    # It only ever adds a notification; the picker never waits on it.
    def enrich():
        if not os.environ.get("GEMINI_API_KEY"):
            return
        syn = call_gemini(
            f"Give 5 concise synonyms for '{translation}' in {target_lang}. "
            "Comma separated, no preamble."
        )
        ex = call_gemini(
            f"Write 3 natural example sentences in {target_lang} using "
            f"'{translation}', each followed by its English translation in "
            "parentheses. Number them '1. ', '2. ', '3. '. No preamble."
        )
        if not (syn or ex):
            return
        body = (
            f"<b><span color='{COLOR_HEAD}'>Word:</span></b> "
            f"<span color='{COLOR_WORD}'>{esc(word)}</span>\n"
            f"<b><span color='#FFA500'>Translation:</span></b> "
            f"<span color='{COLOR_TRANS}'>{esc(translation)}</span>\n"
        )
        if syn:
            body += f"\n💡 <b>Synonyms:</b>\n{clean_markup(syn)}\n"
        if ex:
            body += f"\n🗣️ <b>Examples:</b>\n{clean_markup(ex)}"
        notify(f"🌐 {esc(word)} ({target_lang})", f"<span font='11'>{body}</span>")

    threading.Thread(target=enrich, daemon=True).start()

    # ---- Build the picker ----
    rows = []      # pango markup shown in rofi
    payloads = []  # plain text copied when the row is chosen

    def add(markup, payload):
        rows.append(markup)
        payloads.append(payload)

    if translation:
        add(
            f"<span foreground='{COLOR_TRANS}'><b>{esc(translation)}</b></span>"
            f"  <span foreground='{COLOR_TYPE}'>translation</span>",
            translation,
        )
    for alt in alternatives(word, src_lang, target_lang):
        if alt != translation:
            add(
                f"<span foreground='{COLOR_TRANS}'>{esc(alt)}</span>"
                f"  <span foreground='{COLOR_TYPE}'>alt</span>",
                alt,
            )

    for e in dictionary(word, src_lang, target_lang):
        pos = (
            f"<span foreground='{COLOR_TYPE}'>({esc(e['pos'])})</span> "
            if e["pos"] else ""
        )
        add(f"{pos}<span foreground='#ffffff'>{esc(e['def'])}</span>", e["def"])
        if e["syn"]:
            add(
                f"    <span foreground='{COLOR_SYN}'>syn:</span> "
                f"<i>{esc(e['syn'])}</i>",
                e["syn"],
            )
        if e["ex"]:
            add(
                f"    <span foreground='{COLOR_EXAMPLES}'>“{esc(e['ex'])}”</span>",
                e["ex"],
            )

    if not rows:
        # Nothing at all came back — still leave the user with something.
        if translation:
            run(["xclip", "-selection", "clipboard"], stdin_text=translation)
            notify("🌐 Translation", esc(translation), 8000)
        else:
            notify("Translator", f"No results for “{esc(word)}”", 8000)
        return 0

    mesg = (
        f"<b>{esc(word)}</b> · {src_lang}→{target_lang} · "
        "<b>↵</b> copy  ·  <b>Esc</b> cancel"
    )
    chosen = run(
        [
            "rofi", "-dmenu", "-i", "-markup-rows", "-format", "i",
            "-p", f"{src_lang}→{target_lang}", "-mesg", mesg,
        ],
        stdin_text="\n".join(rows),
        timeout=600,
    )

    # -format i returns the index, so no fragile regex un-parsing of the
    # markup is needed to recover what the user actually picked.
    if chosen.isdigit() and 0 <= int(chosen) < len(payloads):
        picked = payloads[int(chosen)]
        run(["xclip", "-selection", "clipboard"], stdin_text=picked)
        notify("📋 Copied", esc(picked), 4000)
        play_tts(translation or word, target_lang)

    return 0


if __name__ == "__main__":
    sys.exit(main())
