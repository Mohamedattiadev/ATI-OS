#!/usr/bin/env python3
"""Reads whisper-stream's VAD-mode block output on stdin and types only the
new words of each block, appended onto what's already typed.

whisper-stream's --step 0 (VAD sliding-window) mode does NOT emit one clean
block per finished phrase -- examples/stream/stream.cpp never clears its
audio ring buffer in that mode, so every time the VAD notices a brief pause
it re-transcribes the WHOLE accumulated recording from t=0 and prints that
as a new block. Across a single sentence this produces a growing sequence
like:

    So hi, eh
    So hi, my name is Muhammad Atiyah and
    So hi, my name is Muhammad Atiyah and the result is... what the...

Each line whisper-stream prints is also prefixed with a timestamp bracket
("[00:00:00.000 --> 00:00:13.360]  ...") -- this example forces timestamps
on whenever VAD mode is active (stream.cpp: `params.no_timestamps =
!use_vad`) and exposes no flag to turn them back off, so it has to be
stripped here rather than at the source.

Typing every block in full (the first version of this script) re-typed the
whole growing sentence each time -- duplicated, garbled output. A second
version backspaced to the point where two blocks diverged and retyped from
there -- correct, but felt like the words being typed kept getting deleted
and rewritten. What actually reads as live speech is simpler: never
delete anything already typed. Track the last block's words, and each new
block only contributes whatever new words follow the longest matching
prefix -- so text only ever grows, word by word, connected with spaces,
even on the passes where whisper revises an earlier word (that revision is
just never reflected on screen -- trading perfect accuracy for a typing
experience with no visible flicker, which is the actual ask).
"""
import re
import subprocess
import sys

RESET_JITTER_MS = 500  # tolerate small timer noise around a buffer reset
TIMESTAMP_RE = re.compile(r"^\[\d{2}:\d{2}:\d{2}\.\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}\.\d{3}\]\s*")
PUNCT_RE = re.compile(r"[^\w\s]")

# Whisper's well-known hallucinations on silence/near-silent audio -- greedy
# decoding on noise reliably lands on one of these rather than staying
# empty. Filtered only when a block's ENTIRE text matches one of these
# verbatim (normalized) AND nothing real has been typed for this utterance
# yet, so genuine speech that happens to contain these words elsewhere in
# a longer sentence is never touched.
HALLUCINATIONS = {
    "you", "thank you", "thank you very much", "thanks for watching",
    "thank you for watching", "please subscribe", "subscribe",
    "bye", "bye bye", "the end", "yeah", "im sorry", "sorry",
    "blank audio", "silence", "laughs", "laughing", "laughter",
    "music", "applause",
}


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


def common_prefix_words(a, b):
    n = min(len(a), len(b))
    i = 0
    while i < n and a[i] == b[i]:
        i += 1
    return i


def main():
    prev_words = []
    prev_t1 = 0
    started = False
    in_block = False
    lines = []
    cur_t1 = 0

    for raw in sys.stdin:
        line = raw.rstrip("\n")

        if line.startswith("### Transcription") and "START" in line:
            in_block = True
            lines = []
            cur_t1 = prev_t1
            try:
                t1_field = line.split("t1 =", 1)[1].strip().split(" ")[0]
                cur_t1 = int(t1_field)
            except (IndexError, ValueError):
                pass
            continue

        if line.startswith("### Transcription") and "END" in line:
            in_block = False
            text = " ".join(strip_timestamp(l).strip() for l in lines if l.strip())
            words = text.split()

            if cur_t1 < prev_t1 - RESET_JITTER_MS:
                # Ring buffer reset: previous utterance is done and already
                # on screen. Separate it from the new one and start fresh.
                if prev_words:
                    xdotool_type(" ")
                prev_words = []
                started = False

            if not prev_words and is_hallucination(text):
                # Nothing real typed yet for this utterance and the whole
                # block is a known silence artifact -- skip it rather than
                # type junk, but don't touch prev_t1/prev_words so the vad
                # reset check above still works correctly next block.
                continue

            cp = common_prefix_words(prev_words, words)
            new_words = words[cp:]
            if new_words:
                prefix = " " if started else ""
                xdotool_type(prefix + " ".join(new_words))
                started = True
            if text:
                pill(text)

            prev_words = words
            prev_t1 = cur_t1
            continue

        if in_block:
            lines.append(line)


if __name__ == "__main__":
    main()
