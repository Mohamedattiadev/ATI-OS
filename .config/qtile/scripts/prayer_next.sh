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
if (( h > 0 )); then
  printf '󰐰 %s %dh %dm' "$next_name" "$h" "$m"
else
  printf '󰐰 %s %dm' "$next_name" "$m"
fi
