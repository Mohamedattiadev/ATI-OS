#!/usr/bin/env python3
"""Reads whisper-stream's VAD-mode block output on stdin and types only the
new/changed part of each block, instead of blindly re-typing the whole thing.

whisper-stream's --step 0 (VAD sliding-window) mode does NOT emit one clean
block per finished phrase -- examples/stream/stream.cpp never clears its
audio ring buffer in that mode, so every time the VAD notices a brief pause
it re-transcribes the WHOLE accumulated recording from t=0 and prints that
as a new block. Across a single sentence this produces a growing sequence
like:

    So hi, eh
    So hi, my name is Muhammad Atiyah and
    So hi, my name is Muhammad Atiyah and the result is... what the...

Typing each block in full (the original approach) re-typed the entire
growing sentence every time, so the actual on-screen result was every one
of those strings concatenated back to back -- the garbled, duplicated mess.

Fix: track what's currently on screen for the in-progress utterance, and
each time a new block arrives, backspace only the characters that differ
from the tail of what's already typed, then type only the new/changed
suffix. A block whose t1 (the "how much audio was in this pass" timestamp
printed in its START line) drops well below the previous block's t1 means
the ring buffer actually reset -- a real pause long enough to start a new
utterance -- so that boundary is treated as final and typing starts fresh
rather than backspacing into already-settled text.
"""
import subprocess
import sys

RESET_JITTER_MS = 500  # tolerate small timer noise around a buffer reset


def xdotool_type(text):
    if text:
        subprocess.run(["xdotool", "type", "--delay", "4", "--", text], check=False)


def xdotool_backspace(n):
    if n > 0:
        subprocess.run(["xdotool", "key", "--repeat", str(n), "BackSpace"], check=False)


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


def common_prefix_len(a, b):
    n = min(len(a), len(b))
    i = 0
    while i < n and a[i] == b[i]:
        i += 1
    return i


def main():
    prev_text = ""
    prev_t1 = 0
    in_block = False
    lines = []

    for raw in sys.stdin:
        line = raw.rstrip("\n")

        if line.startswith("### Transcription") and "START" in line:
            in_block = True
            lines = []
            # e.g. "### Transcription 12 START | t0 = 0 ms | t1 = 7280 ms"
            t1 = prev_t1
            try:
                t1_field = line.split("t1 =", 1)[1].strip().split(" ")[0]
                t1 = int(t1_field)
            except (IndexError, ValueError):
                pass
            cur_t1 = t1
            continue

        if line.startswith("### Transcription") and "END" in line:
            in_block = False
            text = " ".join(l.strip() for l in lines if l.strip())

            if cur_t1 < prev_t1 - RESET_JITTER_MS:
                # Ring buffer reset: previous utterance is done and already
                # on screen. Separate it from the new one and start fresh.
                if prev_text:
                    xdotool_type(" ")
                prev_text = ""

            cp = common_prefix_len(prev_text, text)
            xdotool_backspace(len(prev_text) - cp)
            xdotool_type(text[cp:])
            if text:
                pill(text)

            prev_text = text
            prev_t1 = cur_t1
            continue

        if in_block:
            lines.append(line)


if __name__ == "__main__":
    main()
