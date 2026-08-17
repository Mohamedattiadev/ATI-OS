#!/usr/bin/env python3
"""Drive qdrop-shake.py's gesture decision with synthetic pointer shapes.

WHY THIS EXISTS
---------------
The shake detector's gates were reported broken — "the drop shelf one when
i select text or scroll up down it appears" — and until now the only way to
exercise them was to shake a real mouse inside a real Hyprland session with
a real drag in flight. That makes the person reporting the bug the only test
harness there is, which is exactly the failure the RULES name: *a control
with no way in from a script is a control whose bugs can only be found by
the user*.

WHAT IT ACTUALLY TESTS, AND WHAT IT CANNOT
------------------------------------------
It calls `Drag.sample()`, which is the whole of the shipped decision — the
loop in qdrop-shake.py calls that and nothing else, so a pass here is a
statement about the code that runs. What it does NOT test is the feed: the
button binds, the socket, and `cursorpos`'s accelerated deltas are all
outside this. Those were measured when they were written and are unchanged.

The shapes below are DESCRIPTIONS OF HAND MOVEMENTS, sampled at the
detector's own 60 Hz, in the screen pixels `cursorpos` reports. They are
what the four gates were chosen against, and each false-positive row names
the report it comes from.

    ./shake-shapes.py            run them all
    ./shake-shapes.py --verbose  show every refusal reason
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DETECTOR = os.path.join(HERE, "..", "qdrop-shake.py")


def load_detector():
    """Import qdrop-shake.py by path — its name is not an identifier.

    Importing it is safe and that is not an accident: everything that needs
    a Hyprland session is inside main(), so module scope does nothing but
    define. If that ever stops being true this import is where it shows up.
    """
    spec = importlib.util.spec_from_file_location("qdrop_shake", DETECTOR)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {DETECTOR}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod._retune_shared()
    return mod


# ---------------------------------------------------------------------------
#  The shapes
# ---------------------------------------------------------------------------
# Each is (name, should_fire, samples), samples being (dx, dy) per 60 Hz
# tick. Written as generators so the arithmetic that makes the shape is
# visible rather than a wall of numbers.


def sweep(dx, dy, ticks):
    return [(dx, dy)] * ticks


def zigzag(amplitude_px, ticks_per_leg, legs, dy_per_tick=0.0):
    """`legs` alternating HORIZONTAL sweeps of `amplitude_px` each."""
    out = []
    step = amplitude_px / ticks_per_leg
    for i in range(legs):
        out += sweep(step if i % 2 == 0 else -step, dy_per_tick, ticks_per_leg)
    return out


def vzigzag(amplitude_px, ticks_per_leg, legs):
    """The same, VERTICAL — a scrollbar, a slider, a scroll gesture."""
    return [(dy, dx) for (dx, dy) in zigzag(amplitude_px, ticks_per_leg, legs)]


# GATE 5's evidence is not a pointer shape, it is the focused window's
# rectangle. A shape may carry a `boxes` function: given the sample index,
# it returns the window box for that tick. Default is a window that never
# moves, which is every case except a resize or a move.
def still(_i):
    return (10, 43, 802, 715)


def resizing(i):
    """A border drag: the width follows the pointer. See GATE 5."""
    return (10, 43, 802 + i * 12, 715)


def moving(i):
    """A window being carried: the position follows the pointer."""
    return (10 + i * 12, 43 + i * 2, 802, 715)


SHAPES = [
    # ---- what must fire -------------------------------------------------
    (
        "a deliberate side-to-side shake, after carrying the file",
        True,
        sweep(14, 2, 20) + zigzag(180, 6, 6),
    ),
    (
        "the same shake, carried further and shaken harder",
        True,
        sweep(20, -3, 18) + zigzag(240, 5, 6),
    ),
    # ---- what must NOT fire ---------------------------------------------
    (
        # "when i select text ... it appears"
        "extending a text selection with small horizontal wiggles",
        False,
        zigzag(30, 4, 10),
    ),
    (
        # "or scroll up down it appears"
        "dragging a scrollbar up and down",
        False,
        sweep(0, 20, 20) + vzigzag(200, 6, 8),
    ),
    (
        "a rubber-band select scribbled in a circle",
        False,
        [(40, 40), (40, 40), (40, 40), (-40, 40), (-40, 40), (-40, 40),
         (-40, -40), (-40, -40), (-40, -40), (40, -40), (40, -40), (40, -40)] * 3,
    ),
    (
        # Gate 4 does NOT reject this, and that is the correct answer rather
        # than a hole. A 180 px-per-leg sweep repeated six times IS the
        # gesture, whatever preceded it; what gate 4 rejects is the first
        # third of a second of any press, and it still does — this fires at
        # sample 19, i.e. 0.32 s in, not on the first flick.
        "a vigorous shake begun immediately after the press",
        True,
        zigzag(180, 6, 6),
    ),
    (
        "a quick jerk right after pressing, and then nothing",
        False,
        zigzag(120, 3, 4),
    ),
    (
        "a long one-way drag with hand tremor in it",
        False,
        sweep(20, 1, 30) + [(20, 1), (-3, 0)] * 15,
    ),
    (
        # "i resize the terrmianl with cursor and opens the dropshef wtf"
        #
        # THE POINTER SHAPE HERE IS A SHAKE. It is horizontal, it is flat,
        # its segments are well past MIN_SEG_PX and it is preceded by
        # plenty of carrying — the same samples as the first row of this
        # table, deliberately, so the ONLY thing telling the two apart is
        # the window box. Gates 1-4 cannot and should not catch this.
        "resizing a window by dragging its border",
        False,
        sweep(14, 2, 20) + zigzag(180, 6, 6),
        resizing,
    ),
    (
        "carrying a window around by a drag",
        False,
        sweep(14, 2, 20) + zigzag(180, 6, 6),
        moving,
    ),
    (
        # The failure direction gate 5 accepts, written down so it is a
        # decision and not a surprise: a window that changes shape for an
        # unrelated reason during a real drag costs you the gesture.
        "a real shake while an unrelated window retiles",
        False,
        sweep(14, 2, 20) + zigzag(180, 6, 6),
        lambda i: (10, 43, 802 if i < 25 else 640, 715),
    ),
]


def run_shape(mod, name, should_fire, samples, boxes, verbose):
    drag = mod.Drag()
    t = 100.0
    drag.start(t, (0, 0), boxes(0))
    fired_at = None
    for i, (dx, dy) in enumerate(samples):
        t += mod.SAMPLE_S
        why = drag.sample(t, float(dx), float(dy), boxes(i))
        if why:
            fired_at = (i, why)
            break
    ok = (fired_at is not None) == should_fire
    verdict = "PASS" if ok else "FAIL"
    want = "fire" if should_fire else "stay quiet"
    if fired_at:
        got = f"fired at sample {fired_at[0]} ({fired_at[1]})"
    elif drag.grabbed:
        got = "quiet — refused as a compositor grab (gate 5)"
    else:
        got = (f"quiet after {len(samples)} samples, "
               f"{drag.travel:.0f}px travelled")
    print(f"  [{verdict}] {name}\n         want {want}; got {got}")
    if verbose and not ok:
        print(f"         gates: carried={drag.carried(t)} "
              f"flat={drag.flat()} grabbed={drag.grabbed}")
    return ok


def main():
    verbose = "--verbose" in sys.argv
    mod = load_detector()
    print(f"shape: seg>={mod.MIN_SEG_PX}px x{mod.REVERSALS_NEEDED} in "
          f"{mod.TIME_WINDOW_S}s, press>={mod.MIN_PRESS_S}s, "
          f"travel>={mod.MIN_TRAVEL_PX}px, x:y>={mod.MIN_AXIS_RATIO}")
    print()
    failures = 0
    for shape in SHAPES:
        name, should_fire, samples = shape[0], shape[1], shape[2]
        boxes = shape[3] if len(shape) > 3 else still
        if not run_shape(mod, name, should_fire, samples, boxes, verbose):
            failures += 1
    print()
    print(f"{len(SHAPES) - failures}/{len(SHAPES)} shapes behave as specified")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
