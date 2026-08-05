import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { AUTHOR, BANNER, EMAIL, ISO, REPO } from "../data";
import { C, MONO, SANS, outCubic, outQuint, range, smooth, textIn } from "../theme";

/**
 * The artwork is the installer's own banner(), set as text so the `╔═╗ ║ ╚═╝`
 * drop shadow comes through exactly as it does in a terminal. Each row wipes
 * in from the left, the way the banner paints itself on a real install.
 *
 * An earlier pass redrew this as SVG rectangles to chase the hairline seams
 * between block cells. It removed the seams and ruined the mark: the outline
 * shadow cannot be reproduced with rects, and a solid offset shadow reads as
 * a completely different logo. The seams are the lesser problem. Leave it as
 * text.
 */
const ROWS = BANNER.split("\n");
const STAGGER = 3;
const ROW_WIPE = 11;

export const Logo: React.FC<{ tail?: boolean }> = ({ tail }) => {
  const f = useCurrentFrame();
  // Sized for a 1920x1080 frame. The end card is the last thing on screen and
  // carries the contact details, so it runs bigger than it used to.
  const size = tail ? 34 : 45;
  const done = (ROWS.length - 1) * STAGGER + ROW_WIPE;

  const settle = outQuint(range(f, 0, 22));
  const rule = outCubic(range(f, done - 2, done + 14));
  const glow = smooth(range(f, 3, done)) * (tail ? 0.1 : 0.16);

  return (
    <AbsoluteFill
      style={{ background: C.bg, justifyContent: "center", alignItems: "center" }}
    >
      <div
        style={{
          position: "absolute",
          width: 1200,
          height: 420,
          borderRadius: "50%",
          background: C.accent,
          filter: "blur(150px)",
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
            marginTop: tail ? 22 : 30,
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
            marginTop: 54,
            textAlign: "center",
            opacity: textIn(f, done + 8, Infinity, 14),
          }}
        >
          <div
            style={{ fontFamily: SANS, fontSize: 46, letterSpacing: "-0.015em", color: C.fg }}
          >
            {AUTHOR}
          </div>
          <div style={{ fontFamily: MONO, fontSize: 29, color: C.accent, marginTop: 14 }}>
            {EMAIL}
          </div>
          <div style={{ width: 130, height: 1, background: C.line, margin: "34px auto 0" }} />
          <div
            style={{
              fontFamily: MONO,
              fontSize: 25,
              color: C.faint,
              marginTop: 28,
              lineHeight: 1.95,
            }}
          >
            <div>{REPO}</div>
            <div>{ISO}</div>
          </div>
        </div>
      ) : (
        <div
          style={{
            marginTop: 46,
            fontFamily: SANS,
            fontSize: 32,
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
