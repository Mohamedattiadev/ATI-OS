import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { C, MARGIN, MONO, SANS, T, outCubic, range, textIn } from "../theme";
import { CardHeader } from "../CardHeader";

/**
 * Credit where it is owed, in the same flat voice as the rest of the film.
 *
 * This config did not start from nothing. A good part of its shape is
 * DistroTube's, and saying so plainly is worth more than a line buried in a
 * README. Deliberately placed AFTER the "not verified" card and before the
 * end card: both are the same kind of honesty, and they belong together.
 */
export const THANKS_DUR = 170;

export const Thanks: React.FC = () => {
  const f = useCurrentFrame();
  const rise = (at: number) => outCubic(range(f, at, at + 22));
  return (
    <AbsoluteFill
      style={{ background: C.bg, justifyContent: "center", padding: `0 ${MARGIN}px` }}
    >
      <div style={{ opacity: textIn(f, 4, Infinity, 16) }}>
        <div
          style={{
            fontFamily: MONO,
            fontSize: 21,
            letterSpacing: "0.28em",
            color: C.accent,
          }}
        >
          WITH THANKS
        </div>
        <div
          style={{
            height: 1,
            background: C.line,
            marginTop: 20,
            transform: `scaleX(${outCubic(range(f, 10, 42))})`,
            transformOrigin: "left",
          }}
        />
      </div>

      <div
        style={{
          opacity: textIn(f, 26, Infinity, 16),
          transform: `translateY(${(1 - rise(26)) * 12}px)`,
          marginTop: 34,
          fontFamily: SANS,
          fontSize: T.display,
        letterSpacing: "-0.015em",
          color: C.fg,
        }}
      >
        DistroTube
      </div>

      <div
        style={{
          opacity: textIn(f, 48, Infinity, 16),
          transform: `translateY(${(1 - rise(48)) * 10}px)`,
          marginTop: 22,
          fontFamily: SANS,
          fontSize: T.body,
          lineHeight: 1.65,
          color: C.dim,
          maxWidth: 1000,
        }}
      >
        About 40% of this config started out as Derek Taylor&rsquo;s work. The rest I
        wrote or worked out myself. He is the reason I got into tiling window
        managers at all.
      </div>

      <div
        style={{
          opacity: textIn(f, 86, Infinity, 16),
          marginTop: 34,
          fontFamily: MONO,
          fontSize: T.mono,
          color: C.accent,
        }}
      >
        youtube.com/@DistroTube
      </div>
    </AbsoluteFill>
  );
};
