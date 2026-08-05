import React from "react";
import { AbsoluteFill, Sequence, useCurrentFrame } from "remotion";
import { smooth, range } from "./theme";

export const XFADE = 16;

/**
 * Every boundary is a cross-dissolve, and nothing else.
 *
 * The first cut of this film had hard cuts, the second had a panel with an
 * accent edge sweeping across each boundary. Both read as effects rather than
 * as edits. A dissolve is the one transition that disappears: the incoming
 * beat starts XFADE frames early and fades up over the outgoing one, which is
 * still playing underneath.
 */
export const Beat: React.FC<{
  from: number;
  duration: number;
  first: boolean;
  children: React.ReactNode;
}> = ({ from, duration, first, children }) => {
  const lead = first ? 0 : XFADE;
  return (
    <Sequence from={from - lead} durationInFrames={duration + lead} layout="none">
      <FadeUp frames={lead}>{children}</FadeUp>
    </Sequence>
  );
};

const FadeUp: React.FC<{ frames: number; children: React.ReactNode }> = ({
  frames,
  children,
}) => {
  const f = useCurrentFrame();
  const o = frames === 0 ? 1 : smooth(range(f, 0, frames));
  return <AbsoluteFill style={{ opacity: o }}>{children}</AbsoluteFill>;
};

/** A hairline that fills as the film runs. */
export const Progress: React.FC<{ total: number }> = ({ total }) => {
  const f = useCurrentFrame();
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        bottom: 0,
        height: 2,
        width: `${Math.min(1, f / total) * 100}%`,
        background: "#51afef",
        opacity: 0.4,
      }}
    />
  );
};
