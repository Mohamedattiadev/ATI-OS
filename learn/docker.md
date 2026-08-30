# Docker & containers

Not a small virtual machine. A normal process on your kernel, with a lying
view of the filesystem, the network and the process list.

## Why a job asks for it

It is how software is shipped now. You will be handed a Dockerfile that
builds in nine minutes and asked why, or a container that works locally and
dies in CI. Both answers come from understanding layers and the difference
between build time and run time.

## The order to learn it in

1. **Image vs container** — an image is a stack of read-only layers; a
   container is one of those plus a writable layer and a process. "The
   container is gone and so is my data" follows directly from this.
2. **The Dockerfile is a cache** — each instruction is a layer, and a layer
   is reused only if it and everything above it are unchanged. This one fact
   explains almost every slow build.
3. **Build time vs run time** — `RUN` happens once when building, `CMD`
   happens each time you start. `ENV` exists in both; your shell's variables
   exist in neither.
4. **Volumes and networks** — how data outlives a container, and why
   `localhost` inside a container is the container.
5. **Compose** — several containers as one unit. Learn it after one
   container makes sense, not before.

## Milestones — you are done with a step when you can do this

- [ ] Explain why reordering two Dockerfile lines made the build 10x faster
- [ ] Get a shell inside a running container and inspect it
- [ ] Say why a file written in a container disappeared
- [ ] Explain why your app cannot reach a database on `localhost`
- [ ] Cut an image's size roughly in half and say what you removed

## Build these

- **Containerise something of yours.** Anything with one dependency.
- **Then make the build fast.** Put dependency installation ABOVE copying
  your source, so a code change does not reinstall the world. Watching the
  cache work is the moment layers click.
- **Then make the image small.** Multi-stage build: compile in one image,
  copy only the result into a clean one.

## Read

- **Docker's own "best practices for writing Dockerfiles"** — short, and
  mostly about the cache.
- **`docker image history <image>`** — not documentation, a diagnostic. It
  shows you the size of every layer you created, which is the fastest way to
  learn what is making images big.

## Watch

Add the minute marks yourself as you watch — see README.md for why they
ship blank.

- **Any walkthrough that builds a Dockerfile line by line and shows the
  cache hits and misses.** Prefer one that edits a file and rebuilds, so you
  see which layers are reused.
  - `MM:SS` —

## The traps

- **`FROM ubuntu` and installing everything.** Start from the smallest image
  that has your runtime.
- **`COPY . .` at the top.** It invalidates every layer below on any change.
- **Secrets in the image.** A deleted file in a later layer is still in the
  image; anyone can read it out of the earlier layer.
- **Treating a container as a machine.** One process, logs to stdout,
  configuration from the environment. Fighting that is fighting the tooling.
