# `learn/` — the skills library

TODOS item 18:

> learning will be just a badge of the names of skills and techno and i click
> on it a well organized .md will appear

That is the whole design. **One skill, one markdown file.** The badge is the
file's `# H1`; the page is whatever is in it.

Open it with `ati-docs skills` (or the Skills row in `ati-docs`, or the
Learn entry in `ati-menu`). Pages render read-only in nvim, in the current
theme, on a searchable index of their own headings — the same viewer the
Documentation section uses. Nothing was built to display these.

## Adding one

Copy `_TEMPLATE.md`, give it an H1, save it as `learn/<something>.md`. It
appears immediately. There is nothing to register and nothing to sync.

## What this deliberately does NOT have

The ask opens with *"remove the complexity of unneeded things"*, so:

* no progress tracking, no percentages, no streaks
* no per-skill state file, no dates, no scoring
* no separate app

Those are the features that turn a study list into a second thing to
maintain, and maintaining it is what makes you stop opening it. A skill is a
file. The badge is its name. There is nothing to keep in step.

## The one thing you have to fill in yourself

The template has a **Watch** section that asks for timestamps:

    - `12:40` — why rebase rewrites hashes

Those are left blank on the shipped pages **on purpose**. A timestamp is a
claim about a specific second of a specific video, and the only honest way
to write one is to have watched it. Guessed timestamps are worse than none:
they send you to the wrong minute and you stop trusting the whole page.

So the pages ship with the *videos* named — series and channels that are
easy to verify exist — and the minute marks left for you to add as you
watch. Add them as you go; that is also the best time to notice which parts
were actually worth marking.
