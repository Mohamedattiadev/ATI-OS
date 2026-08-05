// The page has to disappear behind the footage, not sit around it. #11111b is
// the config's own bar/desktop background, so a clip that does not fill the
// frame letterboxes into the same colour it was recorded on.
export const C = {
  bg: "#11111b",
  fg: "#d7dae0",
  dim: "#8d95a3",
  faint: "#5B6268",
  accent: "#51afef",
  accentDim: "#2f6f97",
  line: "#2a2e39",
};

// Verified with fc-match on this machine — each resolves to itself, not to a
// fallback. Do not swap a family in without re-running it.
export const SANS = '"Adwaita Sans", "Noto Sans", sans-serif';
export const MONO = '"JetBrainsMono Nerd Font", "Adwaita Mono", monospace';

/**
 * One left rail and one type scale for the whole film. Every card and every
 * caption aligns to MARGIN, and every size comes from T — that shared grid is
 * most of what separates "designed" from "assembled".
 */
export const MARGIN = 130;

export const T = {
  eyebrow: 25,
  display: 74,
  headline: 46,
  captionTitle: 35,
  body: 31,
  bodySm: 27,
  mono: 26,
  monoSm: 22,
};

export const clamp = (x: number) => Math.max(0, Math.min(1, x));

/** 0..1 progress between two frames */
export const range = (frame: number, s: number, e: number) =>
  clamp((frame - s) / (e - s));

/** smoothstep — no overshoot, no bounce */
export const smooth = (t: number) => {
  const x = clamp(t);
  return x * x * (3 - 2 * x);
};

/** fast out, settles — what most of the motion here uses */
export const outCubic = (t: number) => 1 - Math.pow(1 - clamp(t), 3);
export const outQuint = (t: number) => 1 - Math.pow(1 - clamp(t), 5);

/** accelerate then decelerate, harder than smoothstep */
export const inOutQuart = (t: number) => {
  const x = clamp(t);
  return x < 0.5 ? 8 * x * x * x * x : 1 - Math.pow(-2 * x + 2, 4) / 2;
};

/**
 * Text fades. `hold` is how long it stays up before it leaves; pass Infinity
 * to leave it up for the rest of the scene.
 */
export const textIn = (frame: number, at: number, hold: number, f = 8) =>
  smooth(range(frame, at, at + f)) *
  (hold === Infinity ? 1 : 1 - smooth(range(frame, at + hold, at + hold + f)));
