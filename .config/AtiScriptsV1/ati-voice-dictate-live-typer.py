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
non-speech tags on quiet or noisy audio, wrapped in either brackets,
parens, or a matched pair of asterisks -- "[BLANK_AUDIO]", "[inaudible]",
"(laughs)", "*singing*" and the like -- which are stripped outright
(they're never actual dictated words), plus a short
list of common unbracketed filler ("thank you", "bye", ...) it
hallucinates on near-silence, filtered only when a block has typed
nothing else yet for the current utterance.
"""
import re
import subprocess
import sys

TIMESTAMP_RE = re.compile(r"^\[\d{2}:\d{2}:\d{2}\.\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}\.\d{3}\]\s*")
BRACKET_TAG_RE = re.compile(r"[\[\(][^\]\)]*[\]\)]")
# Whisper also wraps non-speech annotations in a matched pair of asterisks
# ("*singing*", "*inaudible*") rather than brackets/parens -- same idea,
# different delimiter. Restricted to a single word with no spaces/
# punctuation, deliberately: Whisper self-censors profanity the same way
# ("f*cking"), and a naive "any pair of asterisks" pattern treats THAT
# inner asterisk as a closing tag delimiter paired with some earlier,
# unrelated stray "*" -- observed swallowing a whole real sentence between
# them ("* This is a trash fish of... that's f*cking" all matched as one
# "tag" up to the asterisk inside the censored word). Annotations are
# always a single descriptive word; censored profanity always has letters
# on both sides of its asterisk. Restricting to \w+ with no space tells
# the two apart.
ASTERISK_TAG_RE = re.compile(r"\*\w+\*")
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
    return ASTERISK_TAG_RE.sub(" ", BRACKET_TAG_RE.sub(" ", text))


def is_hallucination(text):
    normalized = PUNCT_RE.sub("", text).strip().lower()
    return normalized in HALLUCINATIONS


def xdotool_type(text):
    if text:
        subprocess.run(["xdotool", "type", "--delay", "4", "--", text], check=False)


def pill(text):
    # Same tag ati-voice-dictate-live's shell wrapper uses, so this replaces the
    # "Listening..." pill in place rather than stacking a new notification.
    subprocess.run(
        [
            "notify-send", "-u", "normal", "-t", "0",
            "-h", "string:x-canonical-private-synchronous:ati-voice-dictate-live",
            "\U0001f399  Listening…", text[-80:],
        ],
        check=False,
    )


def strip_timestamp(line):
    return TIMESTAMP_RE.sub("", line, count=1)


def _norm_word(w):
    return PUNCT_RE.sub("", w).lower()


def longest_common_prefix(prev, new):
    """Largest k such that prev[:k] == new[:k] (both anchored at word 0).

    Handles both pure growth (new is prev plus more) and whisper revising
    a word near the END of prev on the next pass ("The found and fixing."
    -> "The found and fixed issue was...") -- new still starts at the same
    base as prev, it just diverges partway instead of matching all the
    way through prev's length. longest_overlap alone requires the WHOLE
    aligned span to match exactly, so one revised word anywhere in it
    made k=0 and retyped everything from word 0 -- the exact bug this was
    reported against ("The found and fixing." / "The found and fixed
    issue was..." typed as "The found and fixing. The found and fixed
    issue was...").
    """
    n = min(len(prev), len(new))
    i = 0
    while i < n and _norm_word(prev[i]) == _norm_word(new[i]):
        i += 1
    return i


def longest_overlap(prev, new):
    """Largest k such that prev's last k words equal new's first k words.

    Compares normalized (punctuation/case-stripped) forms, not the raw
    words: whisper commonly re-decodes the same audio slightly differently
    pass to pass -- a trailing "system" vs "system," vs "System." at the
    exact same spot in the audio -- and comparing raw strings made that
    look like the overlap didn't exist, so the tail of what was already
    typed got retyped as a near-duplicate instead of recognized as the
    same content.

    This alone only covers the ring buffer actually sliding (new's start
    corresponds to somewhere in the MIDDLE of prev, not word 0) -- see
    longest_common_prefix for the position-0 case, and merge_point below
    for how the two get combined.
    """
    prev_norm = [_norm_word(w) for w in prev]
    new_norm = [_norm_word(w) for w in new]
    max_k = min(len(prev), len(new))
    for k in range(max_k, 0, -1):
        if prev_norm[-k:] == new_norm[:k]:
            return k
    return 0


def merge_point(prev, new):
    """How many words of `new` are already covered by `prev` and should
    not be retyped -- the larger of the two alignments above, since a
    bigger match is never a worse read of what's actually going on."""
    return max(longest_common_prefix(prev, new), longest_overlap(prev, new))


def _min_repeats_for(length):
    # A single word doubled ("no no") is still common enough in real
    # speech to need 3+ consecutive copies before it's treated as a
    # hallucination. Anything 2+ words is a different story: nobody
    # naturally repeats a whole phrase verbatim back to back, so 2
    # consecutive copies is already the loop ("what I did was I tried to
    # upgrade the system" x2, reported directly) -- lowered from a 1-2
    # word / 3+ word split after repeats were still getting through.
    return 3 if length <= 1 else 2


def collapse_repeats(words, max_ngram=12):
    """Collapse a phrase that repeats back-to-back down to one occurrence.

    Safety net for Whisper's decoder repetition-loop failure mode -- a
    well-documented Whisper issue where greedy decoding on longer or messy
    audio gets stuck re-emitting the same phrase. -bs 3 (beam search) is
    the real fix since greedy has no mechanism to escape a loop once
    locked on, but this catches whatever gets through regardless.
    """
    norm = [_norm_word(w) for w in words]
    n = len(words)
    out = []
    i = 0
    while i < n:
        collapsed = False
        # Smallest period first: a phrase repeated 6x also satisfies the
        # repeat check at 2x and 3x its own length (three "AABB"-style
        # double-copies still look like 3 repeats to the check below), so
        # searching largest-first would lock onto one of those multiples
        # and only collapse away part of the loop.
        max_l = min(max_ngram, n - i)
        for length in range(1, max_l + 1):
            min_repeats = _min_repeats_for(length)
            if i + min_repeats * length > n:
                continue
            reps = 1
            while (i + (reps + 1) * length <= n
                   and norm[i + reps * length: i + (reps + 1) * length] == norm[i: i + length]):
                reps += 1
            if reps >= min_repeats:
                out.extend(words[i:i + length])
                i += reps * length
                collapsed = True
                break
        if not collapsed:
            out.append(words[i])
            i += 1
    return out


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
            words = collapse_repeats(text.split())
            text = " ".join(words)

            if not words:
                continue

            if not prev_words and is_hallucination(text):
                # Nothing real typed yet for this utterance and the whole
                # block is a known silence artifact -- skip it.
                continue

            k = merge_point(prev_words, words)
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
