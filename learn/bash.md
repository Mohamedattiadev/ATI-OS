# Bash & the shell

The language you already use every day without having learned it.

## Why a job asks for it

Almost nothing is written in bash on purpose any more, and almost everything
has some bash in it: CI pipelines, Dockerfiles, install scripts, the glue
between two tools. You will spend more time reading someone else's shell
than writing your own, and the failure mode of not knowing it is quiet — a
script that silently does the wrong thing rather than crashing.

## The order to learn it in

1. **Quoting** — the single biggest source of shell bugs. `"$var"` versus
   `$var` is not style, it is the difference between one argument and
   however many words happen to be in it.
2. **Exit codes and `set -euo pipefail`** — how failure works, and why by
   default a script keeps going after an error as if nothing happened.
3. **Pipes and redirection** — stdin/stdout/stderr as three separate
   streams, `2>&1`, and why `cmd > file 2>&1` and `cmd 2>&1 > file` differ.
4. **The text tools** — `grep`, `sed`, `awk`, `cut`, `sort`, `uniq`, `xargs`.
   You do not need to master awk; you need to recognise which tool a problem
   belongs to.
5. **Real scripts** — functions, `case`, arrays, `trap` for cleanup, and
   `"$@"` (which is not the same as `$*`).

## Milestones — you are done with a step when you can do this

- [ ] Explain why `rm $file` is dangerous and `rm "$file"` is not
- [ ] Say what `set -e` does NOT catch (it is more than you would think)
- [ ] Write a script that cleans up its temp files even when it is killed
- [ ] Read a 200-line script you did not write and say what it does
- [ ] Fix a script that works in bash and breaks in `sh`

## Build these

- **Rewrite something you do by hand.** Anything you have typed three times
  this week. This is how every useful script in this repo started.
- **A script with a `--dry-run` flag.** It forces you to separate deciding
  from doing, which is the structure that makes scripts safe to re-run.
- **Run `shellcheck` on it.** Then fix every warning and read WHY each one
  exists. This is the fastest shell education available.

## Read

- **`man bash`** — enormous, but the sections on Parameter Expansion and
  Conditional Expressions are the two you will come back to forever.
- **ShellCheck's wiki** — every warning code has a page explaining the bug
  it prevents, with an example. Better than most tutorials.
- **Google's Shell Style Guide** — short, opinionated, and its main rule is
  worth internalising: if it is over ~100 lines or needs data structures,
  stop and use python.

## Watch

Add the minute marks yourself as you watch — see README.md for why they
ship blank.

- **MIT's "The Missing Semester of Your CS Education"** — the shell, shell
  tools and data wrangling lectures. Free, on YouTube and on their site.
  This is the best single resource here.
  - `MM:SS` —

## The traps

- **Parsing `ls`.** Use globs or `find -print0`. Filenames can contain
  spaces and newlines, and `ls` output cannot be parsed safely.
- **`set -e` as a safety net.** It does not fire inside `if`, `&&`, or a
  pipeline's non-final command. Check exit codes where they matter.
- **Writing bash past the point where it stops fitting.** When you reach
  nested data or arithmetic beyond counters, the answer is python.
