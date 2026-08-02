# rofi translator

Select any text on screen, hit the keybinding, and get a browsable
dictionary in rofi. Bound to **Mod+p → e** in `qtile/config.py`.

## What it does

1. Reads the current X primary selection (whatever you highlighted).
2. Detects the source language and asks which language to translate to.
3. Opens a rofi picker containing the translation, alternative
   renderings, and part-of-speech tagged definitions with their
   synonyms and usage examples.
4. Enter copies the highlighted row to the clipboard and speaks the
   translation.

## Requirements

  + Rofi
  + Python 3
  + `translate-shell` (the `trans` command) — the dictionary source
  + `xclip` — reads the selection, writes the clipboard

Optional, each adding one feature rather than being required:

  + `gtts-cli` / `piper` / `espeak-ng` — text to speech
  + `mpv` — plays what the above generate
  + A Gemini API key in `~/.config/secrets.env` — adds AI-generated
    synonyms and example sentences as a follow-up notification

## Note on WordReference

This started life as a WordReference scraper, which is where the file
name comes from. That source is gone: wordreference.com now answers this
host with HTTP 418 for every request regardless of user-agent, headers,
scheme, or HTTP client, so the scrape failed on every single lookup and
silently degraded to dumping a one-word translation into the clipboard.

`trans -d` replaced it. It needs no scraping, cannot be blocked, and
returns richer data — definitions grouped by part of speech, per-sense
synonyms, and real usage examples. BeautifulSoup is no longer a
dependency.
