#!/usr/bin/env python3
"""Reads whisper-stream's VAD-mode block output on stdin and types only the
new words of each block, appended onto what's already typed.

whisper-stream's --step 0 (VAD sliding-window) mode does NOT emit one clean
block per finished phrase -- examples/stream/stream.cpp never clears its
audio ring buffer in that mode, so every time the VAD notices a brief pause
it re-transcribes the last --length ms (a fixed-size ring buffer) and
prints that as a new block. Two distinct effects fall out of this:

1. While the conversation is still shorter than --length, the buffer holds
   everything since the start, so blocks grow purely by appending:

       So hi, eh
       So hi, my name is Muhammad Atiyah and
       So hi, my name is Muhammad Atiyah and the result is... what the...

2. Once you've been talking longer than --length (with pauses shorter than
   a full VAD reset), the ring buffer starts sliding: old audio ages out
   the front while new audio keeps landing at the back. The block's t1
   (wall-clock ms since the tool started, printed in its START line) keeps
   growing either way, but the WORDS no longer purely append -- the
   window's start point has moved forward too. Comparing against just the
   previous block's word list by prefix broke here: the new block's first
   words no longer matched what was typed before (because the window
   shifted), so the whole thing looked "new" and got retyped -- which is
   exactly the repeated phrases ("Oh, can you hear me?" three times) this
   was built to fix.

Fix for (2): don't require the match to start at word 0. Find the longest
run where some suffix of what's already typed matches a prefix of the new
block (the actual overlapping region, wherever it falls), and only type
what comes after that overlap. This handles pure growth (the overlap is
the whole previous block) and window sliding (the overlap is just the
tail of the previous block) the same way.

Each line whisper-stream prints is also prefixed with a timestamp bracket
("[00:00:00.000 --> 00:00:13.360]  ...") -- this example forces timestamps
on whenever VAD mode is active (stream.cpp: `params.no_timestamps =
!use_vad`) and exposes no flag to turn them back off, so it has to be
stripped here rather than at the source. Whisper also emits its own
bracketed/parenthesized non-speech tags on quiet or noisy audio --
"[BLANK_AUDIO]", "[inaudible]", "(laughs)" and the like -- which are
stripped outright (they're never actual dictated words), plus a short
list of common unbracketed filler ("thank you", "bye", ...) it
hallucinates on near-silence, filtered only when a block has typed
nothing else yet for the current utterance.
"""
import re
import subprocess
import sys

TIMESTAMP_RE = re.compile(r"^\[\d{2}:\d{2}:\d{2}\.\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}\.\d{3}\]\s*")
BRACKET_TAG_RE = re.compile(r"[\[\(][^\]\)]*[\]\)]")
PUNCT_RE = re.compile(r"[^\w\s]")

# Common unbracketed filler Whisper hallucinates on near-silent audio.
# Filtered only when a block's ENTIRE (post bracket-stripping) text
# matches one of these verbatim, AND nothing real has been typed for this
# utterance yet -- so genuine speech containing these words elsewhere in
# a longer sentence is never touched.
HALLUCINATIONS = {
    "you", "thank you", "thank you very much", "thanks for watching",
    "thank you for watching", "please subscribe", "subscribe",
    "bye", "bye bye", "the end", "yeah", "im sorry", "sorry",
    "silence", "laughs", "laughing", "laughter", "music", "applause",
    "inaudible",
}


def strip_bracket_tags(text):
    return BRACKET_TAG_RE.sub(" ", text)


def is_hallucination(text):
    normalized = PUNCT_RE.sub("", text).strip().lower()
    return normalized in HALLUCINATIONS


def xdotool_type(text):
    if text:
        subprocess.run(["xdotool", "type", "--delay", "4", "--", text], check=False)


def pill(text):
    # Same tag voice_dictate_live's shell wrapper uses, so this replaces the
    # "Listening..." pill in place rather than stacking a new notification.
    subprocess.run(
        [
            "notify-send", "-u", "normal", "-t", "0",
            "-h", "string:x-canonical-private-synchronous:voice_dictate_live",
            "\U0001f399  Listening…", text[-80:],
        ],
        check=False,
    )


def strip_timestamp(line):
    return TIMESTAMP_RE.sub("", line, count=1)


def longest_overlap(prev, new):
    """Largest k such that prev's last k words equal new's first k words."""
    max_k = min(len(prev), len(new))
    for k in range(max_k, 0, -1):
        if prev[-k:] == new[:k]:
            return k
    return 0


def main():
    prev_words = []
    started = False
    in_block = False
    lines = []

    for raw in sys.stdin:
        line = raw.rstrip("\n")

        if line.startswith("### Transcription") and "START" in line:
            in_block = True
            lines = []
            continue

        if line.startswith("### Transcription") and "END" in line:
            in_block = False
            raw_text = " ".join(strip_timestamp(l).strip() for l in lines if l.strip())
            text = strip_bracket_tags(raw_text).strip()
            words = text.split()

            if not words:
                continue

            if not prev_words and is_hallucination(text):
                # Nothing real typed yet for this utterance and the whole
                # block is a known silence artifact -- skip it.
                continue

            k = longest_overlap(prev_words, words)
            new_words = words[k:]
            if new_words:
                prefix = " " if started else ""
                xdotool_type(prefix + " ".join(new_words))
                started = True
            pill(text)

            prev_words = words
            continue

        if in_block:
            lines.append(line)


if __name__ == "__main__":
    main()
