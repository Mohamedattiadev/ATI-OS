# rofi translator

Type a word or sentence — or highlight one first — hit the keybinding,
and get a browsable dictionary in rofi. Bound to **Mod+p → e** in
`qtile/config.py`.

## What it does

1. Opens an input box prefilled with the X primary selection. Type,
   edit, or replace it; whole sentences are fine.
2. Asks which language to translate into, most recently used first.
3. Opens a rofi picker laid out as a three-column table — tag │ content
   │ note — under section rules: translation, sentences, other
   renderings, definitions, more examples.

   ```
   ── English → Arabic ──────────────────────────────
   ar    │ جميل                    │ translation
   say   │ jamil                   │ pronunciation
   ── Definitions ───────────────────────────────────
   1.    │ pleasing the senses…    │ adj.
     syn │ beauteous, comely, fair │
     en  │ “beautiful poetry”      │
     ar  │ “شعر جميل”              │
   ```

4. Every sentence and every usage example is shown twice: once in the
   source language, once in the target. The dictionary only ships the
   source-language side, so the translations come from one extra
   batched request (all examples in a single call, not one per sense).
5. Enter copies the highlighted row to the clipboard.

## Keys

| Where | Key | Does |
| --- | --- | --- |
| input box | `Ctrl+u` / `Ctrl+w` | clear the whole field |
| results | `Enter` | copy the row |
| results | `Ctrl+t` (or `Alt+n`) | look up another word, same language |
| results | `Ctrl+o` (or `Alt+l`) | same text, different language |
| results | `Esc` | quit |

Ctrl is the primary binding and Alt only an alias, because this machine's
Alt key is dead in hardware and exists only as an xmodmap remap of Caps
Lock — see the `mod2` comment in qtile's `config.py`. `Ctrl+n` and
`Ctrl+l` were unavailable (row-down and mode-complete), hence `t` for
text and `o` for other language.

`Ctrl+t` reopens the input box prefilled with what you just looked up, so
`Ctrl+u` and type replaces it — the script loops instead of exiting after
one lookup. Rofi ships `Ctrl+u` as remove-to-start-of-line and `Ctrl+w`
as clear-line; both now clear the line, which meant unbinding
remove-to-sol first or rofi refuses to start on the duplicate binding.

## Speed

One HTTP request to `translate_a/single` returns everything — detected
source language, translation, dictionary, definitions, examples,
synonyms — in roughly 200 ms. Results are cached under
`~/.cache/rofi_translator`, and the lookup for the last-used target
language starts in the background while the language picker is still
open, so the usual case is already finished by the time you choose.

## Did you mean …?

A typo in what you typed puts a red `✎` row at the very top of the
table, above the translation of what you actually wrote; Enter on it
re-translates the corrected text instead of copying anything.

Two sources feed it, because neither is enough alone. Google returns a
correction inside the translation response (free, no extra request) but
only sometimes — `recieve` and `hous` come back corrected, `beatiful`
does not. LanguageTool covers the rest and is only asked when Google had
nothing, so the extra request happens on typos, not on every lookup, and
its answer is cached like everything else.

Only misspellings are applied. LanguageTool also flags style and
agreement, and quietly rewriting grammar under a "did you mean" label is
not the same offer — that is what `dm-spellcheck` (**Mod+p → s**) is for.

Rubbish input is called out rather than dressed up. Typing `asesd` is
not an error the API reports — it hands the text back untouched, which
the table used to present in confident green as a translation. When the
result equals the input *and* carries no dictionary and no definitions,
the row turns red and says "came back unchanged — not a word?", plus a
"no result" line when there is not even a suggestion to offer. Words
that legitimately match across languages (`Hotel`, `taxi`) still come
with dictionary entries, so they never land in that branch.

The language sent to LanguageTool is the one Google detected, not
LanguageTool's own guess, which is wild on short input. When a typo
throws the detector off entirely — `beatiful` comes back as Haitian
Creole — plain ASCII input falls back to en-US rather than going
unchecked.

## The table

Rows are drawn inside a `<tt>` span. Rofi's UI font is proportional, so
without it the separators wander by a few pixels a row and the table
stops reading as one. Column widths are measured, not fixed: the content
column is sized to the widest row it has to hold and clamped, so a
one-word lookup gets a compact table rather than acres of padding.

Nothing is ever cut short. A row wider than the column cap keeps its
full text and pushes its own note column to the right — only that row
loses the alignment, which beats hiding half a definition behind an
ellipsis. The picker window is widened to 75% — the same as
`rofi/themes/kill-large.rasi` — so the table has room without taking
over the screen.

## Colours

The table follows whichever palette `theme-apply` has symlinked as
`rofi/themes/current-palette.rasi`. They were doom-one literals before,
so switching theme recoloured the rofi frame and left the table
stubbornly blue and green — pango markup cannot reference rofi theme
variables, so every colour has to be resolved in Python instead.

`AtiScriptsV1/lib/ati_palette.py` does that for both this and
`dm-spellcheck`, mapping the palette's seven keys onto roles (head,
good, bad, accent, text) so neither script has to care whether a palette
calls its red `urgent` or `selectedone`. `dim`, `muted`, `example` and
`syn` are blends of foreground and background, because a palette has no
"comment gray" and the obvious candidate — `background-alt` — is the
colour of the background the text sits on. Falls back to
`~/.cache/wal/colors.json`, then to doom-one.

## Right-to-left targets

Arabic, Hebrew, Persian and Urdu rows are wrapped in Unicode FSI…PDI
isolates. Without them pango takes the paragraph direction from the
first strong character, which flips the whole row and throws the latin
labels to the wrong side. The isolates are stripped before anything
reaches the clipboard.

## Requirements

  + Rofi
  + Python 3
  + `xclip` — reads the selection, writes the clipboard
  + `translate-shell` (the `trans` command) — fallback only, used when
    the API call fails

Optional:

  + A Gemini API key in `~/.config/secrets.env` — adds AI-generated
    synonyms and example sentences as a follow-up notification

There is no text to speech any more. The piper/gtts/espeak chain spoke
the translation on every copy, needed three optional dependencies
between them, and was not worth keeping.

## Note on WordReference

This started life as a WordReference scraper, which is where the file
name comes from. That source is gone: wordreference.com now answers this
host with HTTP 418 for every request regardless of user-agent, headers,
scheme, or HTTP client, so the scrape failed on every single lookup and
silently degraded to dumping a one-word translation into the clipboard.

`trans -d` replaced it, and the Google endpoint `trans` itself talks to
replaced that in turn — same data, one request instead of four shellouts,
and no awk interpreter in the path. BeautifulSoup is no longer a
dependency.
