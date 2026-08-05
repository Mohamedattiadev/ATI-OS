import React from "react";
import { AbsoluteFill } from "remotion";
import { CLIP } from "../data";
import { Caption, Shot } from "../ui";

/**
 * 28 seconds of ordinary work, in one take, at 1x.
 *
 * Recorded in the Xephyr nest on :9 against a scrubbed HOME
 * (/tmp/atios-usage/home). The file manager is showing four throwaway folders
 * and three throwaway files, and Brave is on a throwaway profile pointed at
 * the project's own documentation. Nothing personal is on screen and nothing
 * ever reached the real display.
 *
 * Caption times are read off the take, not guessed (24 fps):
 *   f22-120   terminal
 *   f120      Super+3, the group switch
 *   f178-288  reading the docs in Brave
 *   f288-420  Super+Tab cycling the layout
 *   f444-528  Alt+Shift+D, the drop shelf
 *   f540-672  Super+P then C, the theme picker
 */
export const USAGE_DUR = 672;

export const Usage: React.FC = () => (
  <AbsoluteFill>
    <Shot clip={CLIP.usage} />
    <Caption
      at={22}
      hold={82}
      title="A terminal opens where it belongs."
      body="The layout picks the size and the position. You never drag a window here."
    />
    <Caption
      at={128}
      hold={62}
      title="Super+3 switches groups."
      body="Each group keeps its own windows. The bar only lists the groups that have something in them."
    />
    <Caption
      at={212}
      hold={86}
      title="The browser is just another tiled window."
      body="Nothing treats it as a special case. That page is this project's own documentation."
    />
    <Caption
      at={320}
      hold={98}
      title="Super+Tab cycles the layout."
      body="monadtall, then max, then treetab. The windows rearrange themselves."
    />
    <Caption
      at={452}
      hold={82}
      title="Alt+Shift+D opens the drop shelf."
      body="It slides in over whatever you are doing. Drop files, text or links into it and they follow you to any group."
    />
    <Caption
      at={560}
      hold={96}
      title="Super+P then C opens the theme picker."
      body="One pick recolours the bar, the terminal, rofi, GTK and the browser together. Esc cancels and nothing changes."
    />
  </AbsoluteFill>
);
