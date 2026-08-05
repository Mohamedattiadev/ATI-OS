import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import { C } from "../theme";
import { CLIP } from "../data";
import { Beat } from "../Transition";
import { Framed, UnderCaption } from "../ui";

/**
 * Two moments of one real QEMU install run, then the machine it leaves you
 * with. The numbers are measured, from installScripts/iso.
 *
 * The third shot is deliberately NOT the QEMU desktop: QEMU has no GPU, picom
 * cannot composite and the bar is #11111b00, so in the recording the bar is
 * simply absent and the desktop reads as broken. It is a still from the real
 * machine instead, and the caption says so rather than hiding it.
 */
const A = 96;
const B = 116;
const Cn = 96;
export const INSTALL_DUR = A + B + Cn;

const RD = { w: 1366, h: 768 };

export const Install: React.FC = () => (
  <AbsoluteFill>
    <Beat from={0} duration={A} first>
      <Framed clip={CLIP.installA}>
        <UnderCaption
          at={8}
          title="Seven questions, then it builds itself."
          body="Disk, hostname, user, password, timezone, keyboard, encryption."
        />
      </Framed>
    </Beat>
    <Beat from={A} duration={B} first={false}>
      <Framed clip={CLIP.installB}>
        <UnderCaption
          at={10}
          title="About 22 minutes, not two hours."
          body="The 31 AUR packages ship prebuilt, so nothing has to compile on the new machine. Checked in QEMU: default 16/16, encrypted 19/19, alongside an existing OS 19/19."
        />
      </Framed>
    </Beat>
    <Beat from={A + B} duration={Cn} first={false}>
      <AbsoluteFill style={{ background: C.bg }}>
        <div
          style={{
            position: "absolute",
            left: Math.round((1920 - RD.w) / 2),
            top: 74,
            width: RD.w,
            height: RD.h,
            border: `1px solid ${C.line}`,
            boxShadow: "0 24px 70px rgba(0,0,0,0.5)",
            overflow: "hidden",
          }}
        >
          <Img src={staticFile("real-desktop.png")} style={{ width: RD.w, height: RD.h }} />
        </div>
        <div
          style={{
            position: "absolute",
            left: Math.round((1920 - RD.w) / 2),
            top: 74 + RD.h + 34,
            right: Math.round((1920 - RD.w) / 2),
          }}
        >
          <UnderCaption
            at={8}
            title="The desktop it leaves you with."
            body="This shot is the real machine, not the VM. Under QEMU the bar does not composite at all."
          />
        </div>
      </AbsoluteFill>
    </Beat>
  </AbsoluteFill>
);
