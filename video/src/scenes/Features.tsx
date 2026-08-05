import React from "react";
import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import { CLIP } from "../data";
import { C, outCubic, range } from "../theme";
import { Caption, Shot } from "../ui";

/** The restart nobody sees. Runs at 1x, because it has to read as one movement. */
export const VEIL_DUR = 210;

export const Veil: React.FC = () => (
  <AbsoluteFill>
    <Shot clip={CLIP.veil} />
    <Caption
      at={96}
      title="Reloading qtile without the flash."
      body="Normally every window on every group is destroyed and redrawn in front of you. Here a veil covers the screen, shows a card for each open window and a real progress figure, then lifts. Same session, same windows."
    />
  </AbsoluteFill>
);

/** Starts past the "Loading updates…" spinner at the head of the capture. */
export const QUPDATE_DUR = 160;

export const Qupdate: React.FC = () => (
  <AbsoluteFill>
    <Shot clip={CLIP.qupdate} from={58} />
    <Caption
      at={20}
      title="Updates are a chip in the bar."
      body="Pending pacman and AUR packages sit in one checklist. A second tab searches both. No terminal, and no separate AUR helper to remember."
    />
  </AbsoluteFill>
);

/**
 * The palette grid is a composited still 1626x1911 — taller than the frame, so
 * this is the one thing in the film that is scaled. It is shown full width and
 * panned rather than shrunk to fit, which would make the labels unreadable.
 */
export const THEMES_DUR = 232;

export const Themes: React.FC = () => {
  const f = useCurrentFrame();
  const H = Math.round((1911 / 1626) * 1366); // 1605
  const y = -outCubic(range(f, 6, THEMES_DUR - 8)) * (H - 768);
  return (
    <AbsoluteFill style={{ background: C.bg, overflow: "hidden" }}>
      <Img
        src={staticFile("themes.png")}
        style={{ position: "absolute", left: 0, top: y, width: 1366, height: H }}
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
  <AbsoluteFill>
    <Shot clip={CLIP.keybindings} />
    <Caption
      at={18}
      title="85 bindings, read straight out of config.py."
      body="The list is built from the config itself, chord prefixes and all. It cannot go stale the way a hand written cheatsheet does."
    />
  </AbsoluteFill>
);
