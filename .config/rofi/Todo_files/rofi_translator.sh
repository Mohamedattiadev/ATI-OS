#!/usr/bin/env bash
set -euo pipefail

#
# Cursor Select Translator v2
#
# A script to translate a selected word, get synonyms/examples via Gemini,
# get IPA, and perform Text-to-Speech.
#
# Dependencies:
#   - xclip, rofi, translate-shell (trans), espeak-ng, jq, mpv
#   - (Optional) gtts-cli, piper
#

# -------------------------- Configuration --------------------------
TMP_DIR="/tmp/translator"
PIPER_CMD="$HOME/.local/bin/piper"
PIPER_VOICE_DE="$HOME/.config/piper-voices/de_DE-thorsten-high.onnx"

NOTIFY_TIMEOUT=25000 # Milliseconds to show notification

# TTS Settings
TTS_SPEED="0.8"        # Slower mpv playback for better understanding
TTS_LENGTH_SCALE="1.3" # Piper-specific setting for slower voice

# Gemini API Key
API_KEY="${GEMINI_API_KEY:-}"

# -------------------------- Pre-flight Checks --------------------------
for cmd in xclip rofi trans espeak-ng jq mpv; do
	if ! command -v "$cmd" &>/dev/null; then
		notify-send -u critical "Translator Error" "Required command not found: '$cmd'. Please install it."
		exit 1
	fi
done
mkdir -p "$TMP_DIR"

# -------------------------- Check if word is selected --------------------------
WORD=$(xclip -o -selection primary 2>/dev/null | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ -z "$WORD" ]; then
	notify-send -u normal -t 5000 "Translator" "⚠ No word selected! Please highlight a word first."
	exit 0
fi

# -------------------------- Helper Functions --------------------------
call_gemini() {
	local prompt="$1"
	[ -z "$API_KEY" ] && echo "" && return

	local models=("gemini-1.5-flash" "gemini-1.5-flash-8b" "gemini-flash-1.5-8b" "gemini-2.0-flash" "gemini-2.0-flash-latest")
	for model in "${models[@]}"; do
		local json_payload
		json_payload=$(jq -n --arg p "$prompt" '{contents:[{parts:[{text:$p}]}]}')
		local api_url="https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${API_KEY}"
		local response
		response=$(curl -s -H "Content-Type: application/json" -d "$json_payload" "$api_url")
		local text
		text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // ""' 2>/dev/null)
		if [ -n "$text" ]; then
			echo "$text"
			return
		fi
	done

	# If all models fail
	echo ""
}

# -------------------------- Main Script Logic --------------------------
SOURCE_LANG=$(trans -b -id "$WORD")
TARGET_LANG=$(echo -e "en\nde\nar\ntr" | rofi -dmenu -i -p "Translate to ($SOURCE_LANG detected)")
[ -z "$TARGET_LANG" ] && exit 0

BODY=""
TITLE=""

if [ "$SOURCE_LANG" = "$TARGET_LANG" ]; then
	# DEFINITION MODE
	TITLE="📖 Definition → $TARGET_LANG"
	BODY="<b><span color='#FFD700'>Word:</span></b> <span color='#00CED1'>$WORD</span>\n"

	IPA=$(espeak-ng -v "$SOURCE_LANG" --ipa -q "$WORD" 2>/dev/null | tr -d '\n' || echo "")
	[ -n "$IPA" ] && BODY+="<b><span color='#FF69B4'>IPA ($SOURCE_LANG):</span></b> /$IPA/\n"

	SYNONYMS=$(call_gemini "Give me 5 diverse synonyms for '$WORD' in $TARGET_LANG, comma separated.")
	[ -n "$SYNONYMS" ] && BODY+="<b><span color='#ADFF2F'>Synonyms:</span></b> <i>$SYNONYMS</i>\n\n"

	EXAMPLES=$(call_gemini "Write 3 natural example sentences in $TARGET_LANG using '$WORD'. Number them '1. ', '2. ', '3. '.")
	[ -n "$EXAMPLES" ] && BODY+="<b><span color='#87CEEB'>Examples:</span></b>\n$EXAMPLES"

else
	# TRANSLATION MODE
	TITLE="🌐 Translation → $TARGET_LANG"
	TRANSLATION=$(trans -b ":$TARGET_LANG" "$WORD")

	RLM=$'\u200f'
	[ "$TARGET_LANG" = "ar" ] && TRANSLATION="${RLM}${TRANSLATION}"

	IPA_SOURCE=$(espeak-ng -v "$SOURCE_LANG" --ipa -q "$WORD" 2>/dev/null | tr -d '\n' || echo "")
	IPA_TARGET=$(espeak-ng -v "$TARGET_LANG" --ipa -q "$TRANSLATION" 2>/dev/null | tr -d '\n' || echo "")

	SYNONYMS_SOURCE=$(call_gemini "Give me 5 synonyms for '$WORD' in $SOURCE_LANG, comma separated.")
	SYNONYMS_TARGET=$(call_gemini "Give me 5 synonyms for '$TRANSLATION' in $TARGET_LANG, comma separated.")

	EXAMPLE_PROMPT="Write 3 natural example sentences in $TARGET_LANG using the word or phrase '$TRANSLATION'. After each sentence, provide its translation to $SOURCE_LANG in parentheses. Number them '1. ', '2. ', '3. '."
	EXAMPLES=$(call_gemini "$EXAMPLE_PROMPT")

	BODY="<b><span color='#FFD700'>Word:</span></b> <span color='#00CED1'>$WORD</span>\n"
	BODY+="<b><span color='#FFA500'>Translation:</span></b> <span bgcolor='#333333' color='#ffffff'><b>$TRANSLATION</b></span>\n\n"

	[ -n "$SYNONYMS_SOURCE" ] && BODY+="<b><span color='#ADFF2F'>Synonyms ($SOURCE_LANG):</span></b> <i>$SYNONYMS_SOURCE</i>\n"
	[ -n "$SYNONYMS_TARGET" ] && BODY+="<b><span color='#ADFF2F'>Synonyms ($TARGET_LANG):</span></b> <i>$SYNONYMS_TARGET</i>\n"
	[ -n "$IPA_SOURCE" ] && BODY+="<b><span color='#FF69B4'>IPA ($SOURCE_LANG):</span></b> /$IPA_SOURCE/\n"
	[ -n "$IPA_TARGET" ] && BODY+="<b><span color='#FF69B4'>IPA ($TARGET_LANG):</span></b> /$IPA_TARGET/\n"

	[ -n "$EXAMPLES" ] && BODY+="\n<b><span color='#87CEEB'>Examples:</span></b>\n$EXAMPLES"
fi

notify-send -t $NOTIFY_TIMEOUT -u normal "$TITLE" "<span font='13'>$BODY</span>"
echo -e "$BODY" | sed 's/<[^>]*>//g' | xclip -selection clipboard

# -------------------------- TTS Logic --------------------------
OUT_FILE="$TMP_DIR/tts_audio"
TTS_WORD="$WORD"
TTS_LANG="$SOURCE_LANG"

# AR/TR → EN/DE uses translated word
if { [ "$SOURCE_LANG" = "ar" ] || [ "$SOURCE_LANG" = "tr" ]; } && { [ "$TARGET_LANG" = "en" ] || [ "$TARGET_LANG" = "de" ]; }; then
	TTS_WORD="$TRANSLATION"
	TTS_LANG="$TARGET_LANG"
fi

# Skip voice if AR→AR or TR→TR
if { [ "$SOURCE_LANG" = "ar" ] && [ "$TARGET_LANG" = "ar" ]; } || { [ "$SOURCE_LANG" = "tr" ] && [ "$TARGET_LANG" = "tr" ]; }; then
	TTS_WORD=""
fi

if [ -n "$TTS_WORD" ]; then
	case "$TTS_LANG" in
	en)
		if command -v gtts-cli >/dev/null; then
			OUT_FILE="$OUT_FILE.mp3"
			gtts-cli -l en "$TTS_WORD" --output "$OUT_FILE" &>/dev/null
			mpv --speed="$TTS_SPEED" --really-quiet "$OUT_FILE" "$OUT_FILE" &
		fi
		;;
	de)
		if [[ -x "$PIPER_CMD" && -f "$PIPER_VOICE_DE" ]]; then
			OUT_FILE="$OUT_FILE.wav"
			echo "$TTS_WORD" | "$PIPER_CMD" --model "$PIPER_VOICE_DE" --length_scale "$TTS_LENGTH_SCALE" --output_file "$OUT_FILE" &>/dev/null
			mpv --really-quiet "$OUT_FILE" "$OUT_FILE" &
		fi
		;;
	*)
		if command -v espeak-ng >/dev/null; then
			OUT_FILE="$OUT_FILE.wav"
			espeak-ng -v "$TTS_LANG" "$TTS_WORD" -w "$OUT_FILE" &>/dev/null
			mpv --really-quiet "$OUT_FILE" &
		fi
		;;
	esac
fi

exit 0
