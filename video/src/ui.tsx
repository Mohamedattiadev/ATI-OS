import React from "react";
import { AbsoluteFill, OffthreadVideo, staticFile, useCurrentFrame } from "remotion";
import { C, MARGIN, MONO, SANS, T, outCubic, range, textIn } from "./theme";
import type { Clip } from "./data";

/**
 * A clip, drawn at its own pixel size and centred — never scaled, never
 * cropped, never framed in a card, and never sped up. An earlier cut used
 * playbackRate to shorten beats; against a 10-14 fps GIF source that produces
 * visible judder. Beats are short now because they are cut short.
 */
export const Shot: React.FC<{ clip: Clip; from?: number }> = ({ clip, from = 0 }) => (
  <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
    <OffthreadVideo
      src={staticFile(clip.src)}
      trimBefore={from}
      style={{ width: clip.w, height: clip.h }}
    />
  </AbsoluteFill>
);

/**
 * The caption. A short title line, then an explanation under it — the earlier
 * cut had one cryptic line that came and went too fast to read.
 *
 * Timings are generous on purpose: 14 frames to fade in, 14 to leave, and a
 * hold long enough to read the second line twice at a comfortable pace.
 */
export const Caption: React.FC<{
  at: number;
  hold?: number;
  title: string;
  body?: string;
}> = ({ at, hold = Infinity, title, body }) => {
  const f = useCurrentFrame();
  const o = textIn(f, at, hold, 14);
  if (o <= 0.001) return null;
  const rise = outCubic(range(f, at, at + 20));
  return (
    <AbsoluteFill style={{ justifyContent: "flex-end", alignItems: "flex-start" }}>
      <div
        style={{
          opacity: o,
          margin: `0 0 54px ${MARGIN}px`,
          maxWidth: 980,
          display: "flex",
          transform: `translateY(${(1 - rise) * 10}px)`,
        }}
      >
        <div
          style={{
            width: 3,
            marginRight: 20,
            background: C.accent,
            transform: `scaleY(${rise})`,
            transformOrigin: "top",
          }}
        />
        <div
          style={{
            // A real panel, not a glow. An earlier version leaned on a large
            // box-shadow to darken the background, which works for one line
            // and falls apart for four — the text overhangs the shadow and
            // the busy footage shows through mid-sentence.
            background: "rgba(13,13,20,0.90)",
            padding: "16px 26px 18px 22px",
            boxShadow: "0 10px 40px rgba(0,0,0,0.35)",
          }}
        >
          <div
            style={{
              fontFamily: MONO,
              fontSize: T.captionTitle,
              lineHeight: 1.4,
              letterSpacing: "-0.005em",
              color: C.fg,
              whiteSpace: "pre",
            }}
          >
            {title}
          </div>
          {body ? (
            <div
              style={{
                marginTop: 6,
                fontFamily: SANS,
                fontSize: T.bodySm,
                lineHeight: 1.5,
                color: C.dim,
                maxWidth: 900,
              }}
            >
              {body}
            </div>
          ) : null}
        </div>
      </div>
    </AbsoluteFill>
  );
};

/**
 * The usage take was re-recorded at 1920x1080 and fills the frame. The older
 * feature clips are 1366x768 and would have to be upscaled by 1.41 to match,
 * which blurs terminal text badly.
 *
 * So they are not upscaled. They sit at native size in a framed panel with the
 * caption in the band underneath, which turns the leftover space into layout
 * instead of letterboxing. The frame's left edge becomes the left rail for
 * that beat, so the caption still lines up with something.
 */
export const Framed: React.FC<{ clip: Clip; from?: number; children?: React.ReactNode }> = ({
  clip,
  from = 0,
  children,
}) => {
  const left = Math.round((1920 - clip.w) / 2);
  return (
    <AbsoluteFill style={{ background: C.bg }}>
      <div
        style={{
          position: "absolute",
          left,
          top: 74,
          width: clip.w,
          height: clip.h,
          border: `1px solid ${C.line}`,
          boxShadow: "0 24px 70px rgba(0,0,0,0.5)",
          overflow: "hidden",
        }}
      >
        <OffthreadVideo
          src={staticFile(clip.src)}
          trimBefore={from}
          style={{ width: clip.w, height: clip.h }}
        />
      </div>
      <div style={{ position: "absolute", left, top: 74 + clip.h + 34, right: left }}>
        {children}
      </div>
    </AbsoluteFill>
  );
};

/** The caption body used underneath a framed clip, on its own line. */
export const UnderCaption: React.FC<{ at: number; title: string; body?: string }> = ({
  at,
  title,
  body,
}) => {
  const f = useCurrentFrame();
  const o = textIn(f, at, Infinity, 14);
  if (o <= 0.001) return null;
  const rise = outCubic(range(f, at, at + 20));
  return (
    <div style={{ opacity: o, transform: `translateY(${(1 - rise) * 10}px)` }}>
      <div
        style={{
          fontFamily: MONO,
          fontSize: T.captionTitle,
          lineHeight: 1.35,
          letterSpacing: "-0.005em",
          color: C.fg,
        }}
      >
        {title}
      </div>
      {body ? (
        <div
          style={{
            marginTop: 8,
            fontFamily: SANS,
            fontSize: T.bodySm,
            lineHeight: 1.5,
            color: C.dim,
          }}
        >
          {body}
        </div>
      ) : null}
    </div>
  );
};
