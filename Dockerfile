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
COPY grimoire /opt/grimoire/grimoire

# The base image sets WORKDIR /work and mounts the user's code there; keep that
# contract so `-v "$PWD:/work"` behaves the same as it does for `jennifer`.
WORKDIR /work

# Hand the launcher to the interpreter rather than relying on its shebang: the
# `:static` base is distroless, and there is no guarantee `/usr/bin/env` exists
# to resolve one. `src/main.j` is a module, not a program - the launcher is what
# names the app directory - so it has to be this file that runs.
ENTRYPOINT ["jennifer", "run", "/opt/grimoire/grimoire"]
CMD ["--help"]
