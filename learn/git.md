# Git

A database of snapshots, plus names that point into it. Almost every
confusing thing about git gets simple once you believe that sentence.

## Why a job asks for it

You will not be asked to "know git". You will be asked to open a pull
request, review someone else's, and fix a branch that has gone wrong without
losing work. The third one is what separates people who are comfortable from
people who delete the folder and clone again.

## The order to learn it in

1. **The three places** — working tree, staging area (index), commit. Every
   git command moves something between these three. If you cannot say which
   two a command touches, you do not yet know what it does.
2. **Branches are labels** — a branch is a pointer to one commit, and it
   moves when you commit. It is not a copy of anything, which is why making
   one is instant.
3. **merge vs rebase** — merge keeps history as it happened; rebase rewrites
   it to look as if you had started later. Learn what each does to the
   commit graph before you form an opinion about which is better.
4. **Undo** — `restore`, `reset`, `revert`, `reflog`. Learn `reflog` early:
   it is the reason almost nothing in git is truly lost, and knowing that
   changes how confidently you work.
5. **Remotes and pull requests** — `fetch` vs `pull`, what "tracking" means,
   and why force-pushing a shared branch is rude.

## Milestones — you are done with a step when you can do this

- [ ] Explain what `git reset --hard`, `--soft` and `--mixed` each do, in
      terms of the three places, without looking it up
- [ ] Recover a commit you "lost" using only `git reflog`
- [ ] Take five messy commits and turn them into two clean ones with an
      interactive rebase
- [ ] Resolve a merge conflict by reading it, not by picking a side at random
- [ ] Open a pull request with a description that explains WHY, not what

## Build these

- **Break a repo on purpose.** Make a scratch repo, then reset, rebase,
  amend, force-push and recover. You cannot learn undo on work you are
  afraid to lose.
- **Rewrite your own history.** Take a branch of yours with ugly commits and
  clean it up before merging. This is the single most job-relevant exercise
  here.

## Read

- **The Pro Git book** (git-scm.com/book) — free, and the only reference
  that explains the model rather than listing commands. Chapters 2, 3 and 7.
- **`git help <command>`** — genuinely good, and offline. `git help reset`
  has the table that makes reset click.

## Watch

Add the minute marks yourself as you watch — see README.md for why they
ship blank.

- **Learn Git Branching** (learngitbranching.js.org) — not a video, an
  interactive visualiser. If you only do one thing on this page, do this.
  It draws the commit graph while you type, which is exactly the missing
  picture.
  - `MM:SS` —
- **Any "git internals" talk** — search for one that opens `.git/` and shows
  the objects. Once you have seen that a commit is a file containing a tree
  hash and a parent hash, the model stops being magic.
  - `MM:SS` —

## The traps

- **Memorising commands instead of the model.** The reason git feels random
  is that command names do not map to the three places. Learn the places.
- **`git pull` without knowing it is fetch + merge.** This is where surprise
  merge commits come from. `git fetch` then look, then decide.
- **Being afraid of rebase.** Rebase on a branch only you have is completely
  safe. Rebase on a shared branch is what people are actually warning about.
- **Committing everything with `-am`.** You stop reading your own diffs, and
  reading your diff before committing catches more bugs than most tests.
