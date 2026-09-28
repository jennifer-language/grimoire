#!/bin/sh
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
#
# Build the interpreter image with git in it, for the jobs that need one.
#
#   scripts/ci-git-image.sh [tag] [base-tag]
#
# The official interpreter image is debian-slim, the interpreter and
# ca-certificates: no git. Two plugins that ship - `grimoire-feed` and
# `grimoire-lastmod` - date a book from its history, so their tests and their
# example books need one, and a suite that skipped them in CI would be testing
# the image rather than the plugins.
#
# The image is built here and never published. `JENNIFER_TAG` names the base, so
# CI pins the interpreter in one place and this follows it.

set -eu

tag=${1:-jennifer-git:test}
base=${2:-${JENNIFER_TAG:-dev}}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/Dockerfile" <<DOCKERFILE
FROM ghcr.io/jennifer-language/jennifer:${base}
USER root
RUN apt-get update && apt-get install -y --no-install-recommends git \\
    && rm -rf /var/lib/apt/lists/*
USER jennifer
DOCKERFILE

docker build --quiet -f "$work/Dockerfile" -t "$tag" "$work" > /dev/null
echo "built $tag from ghcr.io/jennifer-language/jennifer:$base (with git)"
