# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
#
# Grimoire on top of the official Jennifer image.
#
# Nothing is compiled here: Grimoire is Jennifer source, and the base image
# already carries the interpreter and the system modules Grimoire imports
# (args, markdown, html, pdf). So this is a copy and an entrypoint.
#
# Build:
#   docker build -t grimoire .
#   docker build --build-arg JENNIFER_TAG=static -t grimoire:static .   # see below
#
# Run (the book is whatever you mount at /work):
#   docker run --rm -v "$PWD:/work" grimoire build
#
# With a plugin, which takes two decisions - the container's and the book's:
#   docker run --rm -e GRIMOIRE_PLUGINS=epub -v "$PWD:/work" grimoire build

# The base image tag. `dev` rather than `latest` because Grimoire's sources
# require Jennifer 0.25.0 and `latest` is still 0.24.0; switch this back to
# `latest` the day 0.25.0 is released.
#
# The distroless `static` variant is unusable until then for the same reason -
# it tracks the release too, so today it is 0.24.0 and there is no `dev-static`
# to stand in for it.
ARG JENNIFER_TAG=dev
FROM ghcr.io/jennifer-language/jennifer:${JENNIFER_TAG}

# The registry shows `description` on the package page, so it says how to run the
# thing rather than only what it is. CI overwrites these from
# `.github/workflows/docker.yml`; they are repeated here so a `docker build .` by
# hand produces the same image, and the two are meant to stay in step.
LABEL org.opencontainers.image.title="Grimoire" \
      org.opencontainers.image.description="Build a documentation website, and a printable PDF, from a directory of Markdown files. Mount a book at /work; everything after the image name is a Grimoire command. Full manual: https://grimoire.jennifer-lang.dev/" \
      org.opencontainers.image.documentation="https://grimoire.jennifer-lang.dev/" \
      org.opencontainers.image.source="https://github.com/jennifer-language/grimoire" \
      org.opencontainers.image.licenses="LGPL-3.0-only"

COPY src /opt/grimoire/src
COPY bin /opt/grimoire/bin
# Beside the launcher, not on PATH: Grimoire looks in its own `plugins/`
# directory first, and a `grimoire-include` in /usr/local/bin would make
# `grimoire<TAB>` ambiguous for anyone working inside the image.
COPY plugins /opt/grimoire/plugins

# Third-party plugins, carried switched off. These are **not** the ones that ship
# with Grimoire - those are in the `plugins/` directory above and are found by
# name like any other install. Nothing here can run until `GRIMOIRE_PLUGINS`
# names it, and even then it runs only because the book's own `grimoire.toml`
# names it too. Enabling somebody else's program is deliberately two decisions,
# one of them the reader's and one of them the book's.
#
# `plugins-src/` is empty in a checkout - see `plugins-src/README.md`. An image
# built without it carries no collection, and `GRIMOIRE_PLUGINS` then says so
# instead of failing later.
COPY plugins-src /opt/grimoire-plugins
COPY packaging/docker-entrypoint.sh /opt/grimoire/bin/docker-entrypoint.sh

# The launcher also at its old path, because other people's Dockerfiles run it
# directly - `RUN ["jennifer", "run", "/opt/grimoire/grimoire", "build"]` - and
# those bypass the entrypoint, so moving the file into `bin/` broke them.
#
# A symlink, and it has to be: the launcher imports `../src/grimoire.j`, and the
# interpreter resolves that against the file's *real* path. A copy at this path
# would look for `/opt/src`; a link resolves to `bin/grimoire` first and finds
# `/opt/grimoire/src` like any other invocation.
#
# `USER root` around it because the base image runs as `jennifer` (uid 10001),
# which cannot write to /opt - `COPY` is done by the builder and does not care,
# but `RUN` is not. The user is put back immediately: an image that ran as root
# would write root-owned files into a reader's bind-mounted book, which is the
# thing `--user "$(id -u):$(id -g)"` exists to avoid.
#
# The `chmod` rides along: `COPY` keeps the mode git recorded, and this is what
# makes a build from an export - a tarball, a context assembled by a tool that
# drops the bit - fail at build time rather than at `docker run` with "permission
# denied" and no entrypoint.
USER root
RUN ln -s bin/grimoire /opt/grimoire/grimoire \
 && chmod +x /opt/grimoire/bin/docker-entrypoint.sh
USER jennifer

# The base image sets WORKDIR /work and mounts the user's code there; keep that
# contract so `-v "$PWD:/work"` behaves the same as it does for `jennifer`.
WORKDIR /work

# A shell script rather than the interpreter directly, because something has to
# read `GRIMOIRE_PLUGINS` before Grimoire starts and link what it names into a
# directory on `PATH`. It ends in
#
#   exec jennifer run /opt/grimoire/bin/grimoire "$@"
#
# so the contract is unchanged: everything after the image name is a Grimoire
# command, and Grimoire is the process the container waits on.
#
# The interpreter is handed the launcher rather than the launcher's shebang
# being relied on: `src/grimoire.j` is a module, not a program - the launcher is
# what names the app directory - so it has to be that file that runs, by its
# real path.
#
# This is the second thing here that needs a shell, and the one that would have
# to be reconsidered for the distroless `:static` base - unusable today anyway,
# since it tracks the release and that is still 0.24.0. Plugins are processes,
# so a distroless image could not run one in any case.
ENTRYPOINT ["/opt/grimoire/bin/docker-entrypoint.sh"]
CMD ["--help"]
