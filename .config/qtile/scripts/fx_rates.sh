#!/usr/bin/env bash
# fx_rates — USD/EUR quoted in TRY and EGP, one base per line:
#
#   $ 1 = 47.55 TL · 51.12 EGP
#   € 1 = 54.75 TL · 58.86 EGP
#
# Env: FX_BASES (default "USD EUR"), FX_QUOTES (default "TRY EGP"),
#      FX_TTL seconds (default 21600 = 6h).
# Deps: curl, jq. Cache: ~/.cache/qtile_fx.json.
#
# One request covers every pair: open.er-api.com returns the whole table
# against a single base (USD here), so EUR->TRY is just TRY/EUR. The
# upstream itself only recomputes once a day, so a 6h TTL is already
# finer-grained than the data.
set -u

BASES="${FX_BASES:-USD EUR}"
QUOTES="${FX_QUOTES:-TRY EGP}"
TTL="${FX_TTL:-21600}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/qtile_fx.json"

now="$(date +%s)"

refresh=1
if [[ -f "$CACHE" ]]; then
  fetched="$(jq -r '.fetched // 0' "$CACHE" 2>/dev/null || echo 0)"
  (( now - fetched < TTL )) && refresh=0
fi

if (( refresh )); then
  if raw="$(curl -fsSL --max-time 6 'https://open.er-api.com/v6/latest/USD' 2>/dev/null)"; then
    rates="$(echo "$raw" | jq -c 'select(.result == "success") | .rates // empty')"
    if [[ -n "$rates" && "$rates" != "null" ]]; then
      jq -n --argjson f "$now" --argjson r "$rates" '{fetched:$f, rates:$r}' > "$CACHE"
    fi
  fi
fi

# A failed refresh is not a failed run: a stale table still beats a blank
# tooltip, so fall through to whatever the cache holds.
[[ -f "$CACHE" ]] || exit 0

# Symbols only for what we actually quote; anything else prints its code.
# No ₺ (U+20BA) on purpose: the bar font is Ubuntu Bold, which doesn't
# carry it, and pango would silently fall back to some other family for
# that one glyph. "TL" is what people write anyway.
sym() {
  case "$1" in
    USD) printf '$'  ;;
    EUR) printf '€'  ;;
    GBP) printf '£'  ;;
    TRY) printf 'TL' ;;
    *)   printf '%s' "$1" ;;
  esac
}

out=""
for base in $BASES; do
  b="$(jq -r --arg c "$base" '.rates[$c] // empty' "$CACHE")"
  [[ -z "$b" || "$b" == "null" ]] && continue

  pairs=""
  for quote in $QUOTES; do
    q="$(jq -r --arg c "$quote" '.rates[$c] // empty' "$CACHE")"
    [[ -z "$q" || "$q" == "null" ]] && continue
    v="$(jq -rn --argjson q "$q" --argjson b "$b" '($q / $b * 100 | round / 100)')"
    [[ -n "$pairs" ]] && pairs="$pairs · "
    pairs="$pairs$(printf '%.2f %s' "$v" "$(sym "$quote")")"
  done
  [[ -z "$pairs" ]] && continue

  [[ -n "$out" ]] && out="$out"$'\n'
  out="$out$(sym "$base") 1 = $pairs"
done

[[ -n "$out" ]] || exit 0
printf '%s' "$out"
