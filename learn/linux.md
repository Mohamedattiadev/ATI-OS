# Linux

Files, processes, and permissions. Everything else is detail on top of those
three.

## Why a job asks for it

The thing your code runs on. When something breaks in production you will be
on a machine with no desktop, no editor you like, and a shell — and the
question will be "why is it slow" or "why did it stop", answered with the
tools that are already there.

## The order to learn it in

1. **The filesystem is one tree** — no drive letters. `/etc` is config,
   `/var` changes, `/usr` is the system's, `/home` is yours. Mounting puts a
   device *into* the tree at a point you choose.
2. **Everything is a file** — including devices and, through `/proc`, the
   kernel's own view of running processes. `/proc/<pid>/environ` and
   `/proc/<pid>/fd` will answer questions nothing else will.
3. **Processes** — PID, parent, exit status, signals. What `SIGTERM` versus
   `SIGKILL` means, and why a process ignoring the first one is a bug worth
   understanding rather than escalating past.
4. **Permissions** — user/group/other, what the execute bit means on a
   *directory*, and why `sudo` is not a synonym for "make it work".
5. **systemd** — units, `systemctl status/start/enable`, and `journalctl`.
   `enable` and `start` are different verbs and confusing them is the most
   common "it works until I reboot" bug.
6. **Diagnosis** — `ps`, `top`/`htop`, `df`, `du`, `ss`, `lsof`, `strace`,
   `dmesg`. You do not need them memorised; you need to know which one
   answers which question.

## Milestones — you are done with a step when you can do this

- [ ] Find what is filling a disk, from a shell, in under a minute
- [ ] Find which process is holding port 8080
- [ ] Explain the difference between `systemctl start` and `enable`
- [ ] Read a unit's logs since the last boot and find the failure
- [ ] Say why a script works when you run it and fails from a service

## Build these

- **A systemd user service** for something of yours. `Restart=`, an
  `EnvironmentFile`, and reading its logs with `journalctl --user -u`. The
  gap between "runs in my terminal" and "runs as a service" is where most of
  the learning is, and almost all of it is environment.
- **Break something on purpose in a VM.** Fill the disk, kill PID 1's
  children, remove a permission. Recovering is the skill.

## Read

- **The Arch Wiki** — the best Linux documentation that exists, and it
  applies far beyond Arch. Read the systemd and the fstab pages properly.
- **`man 7 signal`, `man 5 proc`** — dense, and the real answers.

## Watch

Add the minute marks yourself as you watch — see README.md for why they
ship blank.

- **MIT's "The Missing Semester of Your CS Education"** — the shell tools
  and debugging lectures cover the diagnosis tooling above.
  - `MM:SS` —

## The traps

- **Reaching for `sudo` when something fails.** Ask what permission is
  missing first; the answer is usually a group, not root.
- **Editing config with no idea what reads it.** `systemctl cat`, `man 5
  <thing>`, or find the process that opens it. Guessing produces files that
  are never read.
- **Learning distro trivia instead of the model.** Package managers differ;
  processes, permissions and the filesystem do not.
