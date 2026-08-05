import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { AUTHOR, BANNER, EMAIL, ISO, REPO } from "../data";
import { C, MONO, SANS, outCubic, outQuint, range, smooth, textIn } from "../theme";

/**
 * The film opens here. The artwork is the installer's own banner(), so the
 * first thing you see in the video and the first thing you see on a real
 * install are the same six lines. Each row wipes in from the left, the way the
 * banner paints itself into a terminal, then a rule sweeps under it.
 *
 * JetBrainsMono advances 0.6em, so a font-size that is a multiple of 5 lands
 * on a whole pixel — 30px gives 18px cells and the blocks butt up seamlessly
 * with letter-spacing at 0. The docs header's -0.03em is wrong at this size:
 * it drags each glyph's `╔═╗` shadow over the neighbouring solid `█` and the
 * wordmark visibly smears. Do not reintroduce it.
 */
const ROWS = BANNER.split("\n");
const STAGGER = 3;
const ROW_WIPE = 11;

export const Logo: React.FC<{ tail?: boolean }> = ({ tail }) => {
  const f = useCurrentFrame();
  const size = tail ? 20 : 30;
  const done = (ROWS.length - 1) * STAGGER + ROW_WIPE;

  const settle = outQuint(range(f, 0, 22));
  const rule = outCubic(range(f, done - 2, done + 14));
  const glow = smooth(range(f, 3, done)) * (tail ? 0.09 : 0.16);

  return (
    <AbsoluteFill
      style={{ background: C.bg, justifyContent: "center", alignItems: "center" }}
    >
      <div
        style={{
          position: "absolute",
          width: 900,
          height: 320,
          borderRadius: "50%",
          background: C.accent,
          filter: "blur(120px)",
          opacity: glow,
        }}
      />
      <div style={{ transform: `scale(${0.99 + settle * 0.01})` }}>
        {ROWS.map((row, i) => {
          const p = outCubic(range(f, i * STAGGER, i * STAGGER + ROW_WIPE));
          return (
            <div
              key={i}
              style={{
                fontFamily: MONO,
                fontSize: size,
                lineHeight: 1.06,
                letterSpacing: "0em",
                color: C.accent,
                whiteSpace: "pre",
                clipPath: `inset(0 ${(1 - p) * 100}% 0 0)`,
              }}
            >
              {row}
            </div>
          );
        })}
        <div
          style={{
            height: 2,
            marginTop: tail ? 16 : 24,
            background: C.accent,
            opacity: 0.85,
            transform: `scaleX(${rule})`,
            transformOrigin: "left",
          }}
        />
      </div>

      {tail ? (
        <div
          style={{
            marginTop: 38,
            textAlign: "center",
            opacity: textIn(f, done + 8, Infinity, 14),
          }}
        >
          <div style={{ fontFamily: SANS, fontSize: 27, color: C.fg }}>{AUTHOR}</div>
          <div style={{ fontFamily: MONO, fontSize: 21, color: C.accent, marginTop: 8 }}>
            {EMAIL}
          </div>
          <div
            style={{
              fontFamily: MONO,
              fontSize: 19,
              color: C.faint,
              marginTop: 22,
              lineHeight: 1.8,
            }}
          >
            <div>{REPO}</div>
            <div>{ISO}</div>
          </div>
        </div>
      ) : (
        <div
          style={{
            marginTop: 36,
            fontFamily: SANS,
            fontSize: 25,
            letterSpacing: "0.16em",
            color: C.dim,
            opacity: textIn(f, done + 4, Infinity, 14),
            transform: `translateY(${(1 - outCubic(range(f, done + 4, done + 22))) * 10}px)`,
          }}
        >
          Arch + qtile, packaged
        </div>
      )}
    </AbsoluteFill>
  );
};
