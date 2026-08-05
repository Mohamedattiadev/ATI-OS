import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { C, MARGIN, MONO, SANS, T, outCubic, range, textIn } from "../theme";
import { CardHeader } from "../CardHeader";

/**
 * The card that stops this being an advert. Every line is what the repo
 * already says about itself in README.md and plan_found-but-not-fixed.md.
 *
 * The first version of this card was three unstyled sentences stacked on a
 * flat background and it looked like a plain-text file. This one is a table:
 * a labelled header, a rule, one row per untested thing with the claim on the
 * left and the reason on the right, and a footer. Rows arrive one at a time.
 */
const ROWS: [string, string][] = [
  ["AMD and NVIDIA graphics", "the code handles them, nobody has run it"],
  ["A HiDPI panel", "the maths is there, nobody has looked"],
  ["Booting from a physical USB stick", "only ever booted in QEMU"],
];

export const RECEIPTS_DUR = 200;

export const Receipts: React.FC = () => {
  const f = useCurrentFrame();
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
          NOT VERIFIED
        </div>
        <div
          style={{
            height: 1,
            background: C.line,
            marginTop: 20,
            transform: `scaleX(${outCubic(range(f, 10, 40))})`,
            transformOrigin: "left",
          }}
        />
      </div>

      {ROWS.map(([label, why], i) => {
        const at = 30 + i * 18;
        const o = textIn(f, at, Infinity, 14);
        const rise = outCubic(range(f, at, at + 20));
        return (
          <div
            key={label}
            style={{
              opacity: o,
              transform: `translateY(${(1 - rise) * 10}px)`,
              display: "flex",
              alignItems: "baseline",
              justifyContent: "space-between",
              gap: 40,
              padding: "22px 0",
              borderBottom: `1px solid ${C.line}`,
            }}
          >
            <div style={{ fontFamily: SANS, fontSize: T.headline, letterSpacing: "-0.01em", color: C.fg }}>{label}</div>
            <div
              style={{
                fontFamily: MONO,
                fontSize: T.monoSm,
                color: C.faint,
                textAlign: "right",
                whiteSpace: "nowrap",
              }}
            >
              {why}
            </div>
          </div>
        );
      })}

      <div
        style={{
          opacity: textIn(f, 96, Infinity, 16),
          marginTop: 34,
          fontFamily: SANS,
          fontSize: T.body,
          color: C.dim,
        }}
      >
        The README says the same thing, in the same words.
      </div>
    </AbsoluteFill>
  );
};
