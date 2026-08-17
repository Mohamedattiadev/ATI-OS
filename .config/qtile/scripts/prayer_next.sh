#!/usr/bin/env bash
# prayer_next — next prayer + countdown for qtile chip.
# Env: PRAYER_CITY, PRAYER_COUNTRY, PRAYER_METHOD (default: Cairo / Egypt / 5).
# Deps: curl, jq. Cache: ~/.cache/qtile_prayer.json (refresh once/day).
set -u

CITY="${PRAYER_CITY:-Cairo}"
COUNTRY="${PRAYER_COUNTRY:-Egypt}"
METHOD="${PRAYER_METHOD:-5}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/qtile_prayer.json"

today="$(date +%Y-%m-%d)"

refresh=1
if [[ -f "$CACHE" ]]; then
  cached_date="$(jq -r '.date // empty' "$CACHE" 2>/dev/null || true)"
  [[ "$cached_date" == "$today" ]] && refresh=0
fi

if (( refresh )); then
  ts="$(date +%s)"
  url="https://api.aladhan.com/v1/timingsByCity/${ts}?city=${CITY// /%20}&country=${COUNTRY// /%20}&method=${METHOD}"
  if raw="$(curl -fsSL --max-time 6 "$url" 2>/dev/null)"; then
    timings="$(echo "$raw" | jq -c '.data.timings // empty')"
    if [[ -n "$timings" && "$timings" != "null" ]]; then
      jq -n --arg date "$today" --argjson t "$timings" '{date:$date, timings:$t}' > "$CACHE"
    fi
  fi
fi

[[ -f "$CACHE" ]] || exit 0

now_min=$(( $(date +%H) * 60 + $(date +%M) ))
next_name=""
next_min=99999

for name in Fajr Dhuhr Asr Maghrib Isha; do
  t="$(jq -r --arg n "$name" '.timings[$n] // empty' "$CACHE")"
  [[ -z "$t" ]] && continue
  hh="${t%%:*}"; mm="${t##*:}"
  mm="${mm%% *}"
  pm=$(( 10#$hh * 60 + 10#$mm ))
  if (( pm > now_min && pm < next_min )); then
    next_min=$pm; next_name=$name
  fi
done

if [[ -z "$next_name" ]]; then
  t="$(jq -r '.timings.Fajr // empty' "$CACHE")"
  [[ -z "$t" ]] && exit 0
  hh="${t%%:*}"; mm="${t##*:}"; mm="${mm%% *}"
  next_min=$(( 10#$hh * 60 + 10#$mm + 24*60 ))
  next_name="Fajr"
fi

diff=$(( next_min - now_min ))
h=$(( diff / 60 ))
m=$(( diff % 60 ))

# ---- THE GLYPH WAS A HEARTBEAT ----------------------------------------------
#
# This read U+F0430 for years, which is `nf-md-pulse` -- an ECG waveform. It
# was reported once the island started drawing this string in a tooltip big
# enough to see it, and the first guess was a font fallback, because the
# tooltip renders in Inter and Inter has no Nerd Font glyphs. It is not:
# rendered at 48 px in BOTH faces, side by side, U+F0430 is the same little
# heartbeat in each --
#
#     pango-view --font="JetBrainsMono Nerd Font 48" -t $'\U000F0430'
#     pango-view --font="Inter Medium 48"            -t $'\U000F0430'
#
# -- so every bar was drawing the codepoint it was given, correctly, and the
# codepoint was simply wrong. U+F1827 is `nf-md-mosque`, confirmed the same
# way (U+F0979 is the star-and-crescent, if that is ever preferred).
#
# BY CODEPOINT, not as a literal, per the RULES: "private-use characters do
# not survive into what the model reads back -- dump bytes, and write glyphs
# by codepoint". The old literal is exactly how a wrong glyph survived this
# long unread. bash's printf takes \U with eight hex digits.
GLYPH="$(printf '\U000F1827')"

if (( h > 0 )); then
  printf '%s %s %dh %dm' "$GLYPH" "$next_name" "$h" "$m"
else
  printf '%s %s %dm' "$GLYPH" "$next_name" "$m"
fi
