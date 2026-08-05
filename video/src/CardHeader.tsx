import React from "react";
import { useCurrentFrame } from "remotion";
import { C, MONO, T, outCubic, range, textIn } from "./theme";

/**
 * The eyebrow-and-rule that every full-screen card opens with. Having one
 * component rather than three copies is what keeps the cards feeling like
 * pages of the same document.
 */
export const CardHeader: React.FC<{ label: string }> = ({ label }) => {
  const f = useCurrentFrame();
  return (
    <div style={{ opacity: textIn(f, 4, Infinity, 16) }}>
      <div
        style={{
          fontFamily: MONO,
          fontSize: T.eyebrow,
          letterSpacing: "0.28em",
          color: C.accent,
        }}
      >
        {label}
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
  );
};
