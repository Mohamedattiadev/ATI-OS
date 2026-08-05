// Real recordings, transcoded by make-assets.sh. Remotion cannot animate a
// .gif (an <Img> freezes on frame 1), so everything is h264 at 30 fps.
//
// `w`/`h` are the true pixel dimensions and the clip is drawn at exactly those
// — never scaled. `frames` is what ffprobe counted; keep it in step with the
// table make-assets.sh prints, or a clip will run out and freeze.
export type Clip = { src: string; w: number; h: number; frames: number };

export const CLIP = {
  // 30 s of ordinary work at 1920x1080, recorded in a second Xephyr nest
  usage: { src: "usage.mp4", w: 1920, h: 1080, frames: 732 },
  // desktop captures, 1:1 with the 1366x768 composition
  veil: { src: "veil.mp4", w: 1366, h: 768, frames: 220 },
  overview: { src: "overview.mp4", w: 1366, h: 768, frames: 703 },
  qupdate: { src: "qupdate.mp4", w: 1366, h: 768, frames: 280 },
  themePicker: { src: "theme-picker.mp4", w: 1366, h: 768, frames: 208 },
  keybindings: { src: "keybindings.mp4", w: 1366, h: 768, frames: 242 },
  // the QEMU window from one real install run
  installA: { src: "install-a.mp4", w: 900, h: 562, frames: 303 },
  installB: { src: "install-b.mp4", w: 900, h: 562, frames: 497 },
} satisfies Record<string, Clip>;

export const AUTHOR = "Mohamed Attia";
export const EMAIL = "mohamedattia.dev@gmail.com";
export const REPO = "github.com/Mohamedattiadev/ATI-OS";
export const ISO = "archive.org/details/ati-os-2026.08.04-x86_64";

// Character-for-character from banner() in
// installScripts/iso/profile/airootfs/usr/local/bin/ati-os-install.
// Six rows, 43 columns. Do not retype it by hand.
export const BANNER = String.raw`   █████╗ ████████╗██╗       ██████╗ ███████╗
  ██╔══██╗╚══██╔══╝██║      ██╔═══██╗██╔════╝
  ███████║   ██║   ██║█████╗██║   ██║███████╗
  ██╔══██║   ██║   ██║╚════╝██║   ██║╚════██║
  ██║  ██║   ██║   ██║      ╚██████╔╝███████║
  ╚═╝  ╚═╝   ╚═╝   ╚═╝       ╚═════╝ ╚══════╝`;
