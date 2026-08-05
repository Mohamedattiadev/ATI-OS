import React from "react";
import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import { CLIP } from "../data";
import { C, outCubic, range } from "../theme";
import { Beat } from "../Transition";
import { Caption, Framed, UnderCaption } from "../ui";

/**
 * These four clips are 1366x768, recorded before the nest was rebuilt at
 * 1080p. They are shown at native size in a frame with the caption below,
 * rather than upscaled 1.41x to fill a 1920x1080 canvas, which would blur
 * every character of terminal text in them.
 */

/** The restart nobody sees. Runs at 1x, because it has to read as one movement. */
export const VEIL_DUR = 210;

export const Veil: React.FC = () => (
  <Framed clip={CLIP.veil}>
    <UnderCaption
      at={96}
      title="Reloading qtile without the flash."
      body="Normally every window on every group is destroyed and redrawn in front of you. Here a veil covers the screen, shows a card for each open window and a real progress figure, then lifts. Same session, same windows."
    />
  </Framed>
);

/**
 * Two windows out of one capture, because the middle of it is an empty search
 * box. Sampled off the frames: f0-56 is the "Loading updates…" spinner,
 * f56-150 is the package checklist with the boxes being ticked, f168-215 is an
 * empty search tab, and the results only arrive around f240.
 *
 * An earlier cut ran f46-206 under a caption about the checklist, so for half
 * the beat the caption described something that was not on screen.
 */
const QA = 96;
const QB = 66;
export const QUPDATE_DUR = QA + QB;

export const Qupdate: React.FC = () => (
  <AbsoluteFill>
    <Beat from={0} duration={QA} first>
      <Framed clip={CLIP.qupdate} from={56}>
        <UnderCaption
          at={14}
          title="Updates are a chip in the bar."
          body="Pending pacman and AUR packages sit in one checklist, with a checkbox each. No terminal."
        />
      </Framed>
    </Beat>
    <Beat from={QA} duration={QB} first={false}>
      <Framed clip={CLIP.qupdate} from={214}>
        <UnderCaption
          at={10}
          title="The other tab searches both."
          body="Repos and the AUR in one list, so there is no separate helper to remember."
        />
      </Framed>
    </Beat>
  </AbsoluteFill>
);

/**
 * The palette grid is a composited still 1626x1911. It is the one thing in the
 * film that is scaled, and it is scaled up to full width and panned rather
 * than shrunk to fit, which would make the labels unreadable.
 */
export const THEMES_DUR = 232;

export const Themes: React.FC = () => {
  const f = useCurrentFrame();
  const W = 1920;
  const H = Math.round((1911 / 1626) * W); // 2256
  const y = -outCubic(range(f, 6, THEMES_DUR - 8)) * (H - 1080);
  return (
    <AbsoluteFill style={{ background: C.bg, overflow: "hidden" }}>
      <Img
        src={staticFile("themes.png")}
        style={{ position: "absolute", left: 0, top: y, width: W, height: H }}
      />
      <Caption
        at={10}
        hold={86}
        title="All 22, side by side."
        body="Same window, same content, every palette. Each one recolours the whole desktop, not just one app."
      />
      <Caption
        at={118}
        title="One of the 22 is not a palette at all."
        body="Wallpaper mode builds the colours out of the image on screen. It takes six accents around the main hue and keeps every one readable against the background. 362 wallpapers come precompiled, so it is really 383 themes, not 22."
      />
    </AbsoluteFill>
  );
};

export const KEYS_DUR = 150;

export const Keybindings: React.FC = () => (
  <Framed clip={CLIP.keybindings}>
    <UnderCaption
      at={18}
      title="85 bindings, read straight out of config.py."
      body="The list is built from the config itself, chord prefixes and all. It cannot go stale the way a hand written cheatsheet does."
    />
  </Framed>
);
