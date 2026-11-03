#!/bin/sh
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
#
# Build the release tarball: the same runtime tree the `.deb` and the Arch
# package install, laid out so it can be unpacked anywhere and run in place.
#
# Not GitHub's source archive, which carries the tests, the examples, the
# packaging and the CI config: this one holds only what a working install
# needs, and the Arch package is built from it.
#
# Usage:
#   scripts/build-tarball.sh <version> <out-dir> [<tree>]
#
# <tree> is the checkout to package, by default the one this script is in. The
# release pipeline packages a tag with the scripts of the commit it runs, so a
# release made by hand for an older tag still gets today's packaging.
#
# Output:
#   <out-dir>/grimoire-<version>.tar.gz          unpacks to grimoire-<version>/
#   <out-dir>/grimoire-<version>.tar.gz.sha256

set -eu

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "usage: $0 <version> <out-dir> [<tree>]" >&2
    exit 2
fi

VERSION="$1"
OUT="$2"
NAME="grimoire-$VERSION"

HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
ROOT="$(cd "${3:-$HERE}" && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
chmod 755 "$STAGE"

TREE="$STAGE/$NAME"

# `$1` relative to ROOT, into the same place under TREE, with mode `$2` -
# every file under it except the test overlays, which nothing imports at run
# time. Sorted, so the copy order is a property of the tree and not of the
# filesystem.
copyTree() {
    (cd "$ROOT" && find "$1" -type f ! -name '*_test.j' | LC_ALL=C sort) |
        while read -r f; do
            case "$f" in
                plugins/grimoire-*) mode=755 ;;
                *) mode=644 ;;
            esac
            install -Dm"$mode" "$ROOT/$f" "$TREE/$f"
        done
}

# bin/, src/ and plugins/ stay siblings: the launcher looks one directory up
# from its own resolved path for `src/`, and Grimoire finds the plugins it ships
# in `plugins/` beside it before it looks on PATH.
install -Dm755 "$ROOT/bin/grimoire" "$TREE/bin/grimoire"
copyTree src
copyTree plugins
install -Dm644 "$ROOT/deck.toml" "$TREE/deck.toml"
install -Dm644 "$ROOT/README.md" "$TREE/README.md"
install -Dm644 "$ROOT/LICENSE.md" "$TREE/LICENSE.md"

# The manual's Markdown, readable as it is. Its screenshots stay behind: they
# are the bulk of `docs/`, and the built manual is a link away.
(cd "$ROOT" && find docs -type f -name '*.md' | LC_ALL=C sort) |
    while read -r f; do
        install -Dm644 "$ROOT/$f" "$TREE/$f"
    done

mkdir -p "$OUT"
OUT_ABS="$(cd "$OUT" && pwd)"

# Reproducible: a fixed member order, no uid/gid or user names from the build
# host, and one timestamp for every entry, so two builds of one commit give the
# same bytes and checksum.
#
# The timestamp is SOURCE_DATE_EPOCH when set (the release pipeline passes the
# tag's commit date), else the packaged tree's HEAD commit date. Outside git the
# newest staged file decides, which is not reproducible: `install` stamps each
# copy with the time it ran.
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    SOURCE_DATE_EPOCH="$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || true)"
fi
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    SOURCE_DATE_EPOCH="$(
        find "$TREE" -type f -printf '%T@\n' | cut -d. -f1 | sort -n | tail -1
    )"
fi

# --mode pins permissions as well: the staged directories were made under the
# caller's umask, which is a property of the build host.
tar --create --gzip \
    --directory "$STAGE" \
    --sort=name \
    --owner=0 --group=0 --numeric-owner \
    --mode='u+rwX,go+rX,go-w' \
    --mtime="@$SOURCE_DATE_EPOCH" \
    --file "$OUT_ABS/$NAME.tar.gz" \
    "$NAME"

(cd "$OUT_ABS" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256")

echo "built $OUT_ABS/$NAME.tar.gz"
