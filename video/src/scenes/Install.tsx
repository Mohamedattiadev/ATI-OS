import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import { CLIP } from "../data";
import { Beat } from "../Transition";
import { Caption, Shot } from "../ui";

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

export const Install: React.FC = () => (
  <AbsoluteFill>
    <Beat from={0} duration={A} first>
      <Shot clip={CLIP.installA} />
      <Caption
        at={8}
        title="Seven questions, then it builds itself."
        body="Disk, hostname, user, password, timezone, keyboard, encryption."
      />
    </Beat>
    <Beat from={A} duration={B} first={false}>
      <Shot clip={CLIP.installB} />
      <Caption
        at={10}
        title="About 22 minutes, not two hours."
        body="The 31 AUR packages ship prebuilt, so nothing has to compile on the new machine. Checked in QEMU: default 16/16, encrypted 19/19, alongside an existing OS 19/19."
      />
    </Beat>
    <Beat from={A + B} duration={Cn} first={false}>
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
        <Img src={staticFile("real-desktop.png")} style={{ width: 1366, height: 768 }} />
      </AbsoluteFill>
      <Caption
        at={8}
        title="The desktop it leaves you with."
        body="This shot is the real machine, not the VM. Under QEMU the bar does not composite at all."
      />
    </Beat>
  </AbsoluteFill>
);
