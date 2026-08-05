import React from "react";
import { AbsoluteFill, Composition, useCurrentFrame } from "remotion";
import { C, range, smooth } from "./theme";
import { CLIP } from "./data";
import { Beat, Progress } from "./Transition";
import { Logo } from "./scenes/Logo";
import { Usage, USAGE_DUR } from "./scenes/Usage";
import {
  Veil, VEIL_DUR,
  Qupdate, QUPDATE_DUR,
  Themes, THEMES_DUR,
  Keybindings, KEYS_DUR,
} from "./scenes/Features";
import { Install, INSTALL_DUR } from "./scenes/Install";
import { Receipts, RECEIPTS_DUR } from "./scenes/Receipts";
import { Thanks, THANKS_DUR } from "./scenes/Thanks";

// 24 fps because that is what the captures are; see make-assets.sh. 1366x768
// because that is the resolution the desktop was recorded at, so every clip
// plays 1:1 and no resampling ever touches the terminal text.
const FPS = 24;
const W = 1366;
const H = 768;

/**
 * The logo opens. Then 28 seconds of real work in one take, and only after
 * that the individual pieces — so nothing is explained before you have seen
 * the thing it belongs to.
 */
const SCENES: { dur: number; el: React.ReactNode }[] = [
  { dur: 96, el: <Logo /> },
  { dur: USAGE_DUR, el: <Usage /> },
  { dur: VEIL_DUR, el: <Veil /> },
  { dur: QUPDATE_DUR, el: <Qupdate /> },
  { dur: THEMES_DUR, el: <Themes /> },
  { dur: KEYS_DUR, el: <Keybindings /> },
  { dur: INSTALL_DUR, el: <Install /> },
  { dur: RECEIPTS_DUR, el: <Receipts /> },
  { dur: THANKS_DUR, el: <Thanks /> },
  { dur: 170, el: <Logo tail /> },
];

const TOTAL = SCENES.reduce((a, s) => a + s.dur, 0);
const FADE_OUT = 20;

export const Explainer: React.FC = () => {
  const f = useCurrentFrame();
  let at = 0;
  return (
    <AbsoluteFill style={{ background: C.bg }}>
      {SCENES.map((s, i) => {
        const from = at;
        at += s.dur;
        return (
          <Beat key={i} from={from} duration={s.dur} first={i === 0}>
            {s.el}
          </Beat>
        );
      })}
      <Progress total={TOTAL} />
      <AbsoluteFill
        style={{
          background: "#000",
          opacity: smooth(range(f, TOTAL - FADE_OUT, TOTAL)),
          pointerEvents: "none",
        }}
      />
    </AbsoluteFill>
  );
};

export const Root: React.FC = () => (
  <Composition
    id="explainer"
    component={Explainer}
    durationInFrames={TOTAL}
    fps={FPS}
    width={W}
    height={H}
  />
);

// Catch a beat outrunning its clip here, rather than discovering a frozen last
// frame halfway through a render.
if (USAGE_DUR > CLIP.usage.frames) throw new Error("Usage beat runs past usage.mp4");
if (VEIL_DUR > CLIP.veil.frames) throw new Error("Veil beat runs past veil.mp4");
