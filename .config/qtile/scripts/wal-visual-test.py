#!/usr/bin/env python3
"""wal-visual-test — verify hue-concentrated palettes across hue range.

Picks 12 wallpapers, one per 30deg bucket of dominant hue.
For each: checks semantic slot rules from precompile JSON.

Emits .config/qtile/WAL_VISUAL_TEST_REPORT.md.
"""
from __future__ import annotations
import colorsys, json, math
from pathlib import Path

CACHE = Path.home() / ".cache/qtile/palettes"
REPORT = Path.home() / ".dotfiles/.config/qtile/WAL_VISUAL_TEST_REPORT.md"

def hex2rgb(h): return tuple(int(h[i:i+2], 16)/255 for i in (1, 3, 5))
def hls(h): r,g,b = hex2rgb(h); return colorsys.rgb_to_hls(r,g,b)
def hue_deg(h): return hls(h)[0] * 360
def L(h): return hls(h)[1]

def rel_lum(hx):
    r,g,b = hex2rgb(hx)
    def c(v): return v/12.92 if v<=0.03928 else ((v+0.055)/1.055)**2.4
    return 0.2126*c(r)+0.7152*c(g)+0.0722*c(b)
def contrast(a,b):
    la, lb = rel_lum(a), rel_lum(b)
    hi, lo = max(la,lb), min(la,lb)
    return (hi+0.05)/(lo+0.05)

def hue_dist_deg(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)

def bucket_pick(all_palettes, target_deg, tol=15):
    best = None
    best_d = 1e9
    for p in all_palettes:
        d = hue_dist_deg(p["dominant_hue_deg"], target_deg)
        if d < best_d:
            best_d, best = d, p
    return best if best_d <= tol else best  # closest even if outside tol

def check_palette(p):
    issues = []
    a = p["accents"]
    bg = p["bg"]
    dom = p["dominant_hue_deg"]
    # slot 0 urgent — warm hue
    u = hue_deg(a[0])
    if not (u <= 30 or u >= 330):
        issues.append(f"urgent hue {u:.0f} not warm")
    # slot 1 main — matches dominant
    m = hue_deg(a[1])
    if hue_dist_deg(m, dom) > 5:
        issues.append(f"main hue {m:.0f} != dominant {dom:.0f}")
    # slot 5 info — cyan-ish
    i = hue_deg(a[5])
    if not (170 <= i <= 210):
        issues.append(f"info hue {i:.0f} not cyan")
    # all accents contrast >=4.5 vs bg
    for idx, ax in enumerate(a):
        c = contrast(bg, ax)
        if c < 4.5:
            issues.append(f"accent{idx+1} contrast {c:.2f} <4.5")
    # brave: frame darker than toolbar
    b = p["consumers"]["brave_theme"]["theme"]["colors"]
    fr = b["frame"]; tb = b["toolbar"]
    fr_l = 0.2126*fr[0] + 0.7152*fr[1] + 0.0722*fr[2]
    tb_l = 0.2126*tb[0] + 0.7152*tb[1] + 0.0722*tb[2]
    if fr_l >= tb_l:
        issues.append(f"brave frame lum {fr_l:.1f} not darker than toolbar {tb_l:.1f}")
    return issues

def main():
    palettes = []
    for j in sorted(CACHE.glob("*.json")):
        try:
            p = json.loads(j.read_text())
            if "accents" in p and "dominant_hue_deg" in p:
                palettes.append(p)
        except Exception:
            pass
    picks = []
    seen = set()
    for deg in range(0, 360, 30):
        p = bucket_pick(palettes, deg)
        if p and p["wallpaper"] not in seen:
            picks.append((deg, p))
            seen.add(p["wallpaper"])
    lines = [
        "# wal-visual-test report",
        "",
        f"- palettes scanned: {len(palettes)}",
        f"- buckets: {len(picks)}",
        "",
        "## Per-bucket results",
        "",
        "| bucket | wallpaper | dom° | bg | c1 urgent | c2 main | c3 warm | c4 cool | c5 comp | c6 info | issues |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    total_issues = 0
    for deg, p in picks:
        a = p["accents"]
        wp = Path(p["wallpaper"]).name
        iss = check_palette(p)
        total_issues += len(iss)
        cells = " | ".join(f"`{x}`" for x in a)
        lines.append(f"| {deg}° | {wp} | {p['dominant_hue_deg']:.0f} | `{p['bg']}` | {cells} | {'; '.join(iss) if iss else 'OK'} |")
    lines += [
        "",
        f"## Summary",
        f"- total issues across {len(picks)} buckets: **{total_issues}**",
        f"- pass rate: {100*(len(picks)-sum(1 for _,p in picks if check_palette(p)))/len(picks):.0f}%",
    ]
    REPORT.write_text("\n".join(lines))
    print(f"report -> {REPORT}")
    print(f"total issues: {total_issues}")

if __name__ == "__main__":
    main()
