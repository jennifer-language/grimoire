#!/bin/sh
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
#
# Run every unit test in src/.
#
# `jennifer test` takes one file, so this is the loop around it. Each
# `src/NAME_test.j` is a white-box overlay on `src/NAME.j`: it sees that
# module's private names unqualified and shares its imports, which is why the
# test files import nothing themselves.
#
#   scripts/test.sh              # everything
#   scripts/test.sh config util  # just these modules
#
# Requires a Jennifer interpreter. `JENNIFER` overrides how it is invoked, and is
# split on whitespace rather than treated as one word, so it can carry a whole
# command - which is how CI runs these inside the official image without
# installing an interpreter on the runner:
#
#   JENNIFER="docker run --rm -v $PWD:/work ghcr.io/jennifer-language/jennifer:dev" \
#       scripts/test.sh

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

JENNIFER=${JENNIFER:-jennifer}

if [ "$#" -gt 0 ]; then
    files=""
    for name in "$@"; do
        file="src/${name%_test}_test.j"
        [ -f "$file" ] || file="src/themes/${name%_test}_test.j"
        [ -f "$file" ] || { echo "no such test: $file" >&2; exit 2; }
        files="$files $file"
    done
else
    files=$(ls src/*_test.j src/themes/*_test.j)
fi

# A module with no test file is the thing this is most likely to miss, so say so
# rather than reporting a clean run over whatever happens to exist.
# The themes are modules too, and the publish gate counts them.
untested=""
for src in src/*.j src/themes/*.j; do
    case "$src" in *_test.j) continue;; esac
    [ -f "${src%.j}_test.j" ] || untested="$untested $(basename "$src")"
done

total=0
failed=0
failing=""

for file in $files; do
    # Unquoted on purpose: see the JENNIFER note in the header.
    # shellcheck disable=SC2086
    out=$($JENNIFER test "$file" 2>&1) || true
    line=$(printf '%s\n' "$out" | grep -E '^[0-9]+ passed' || true)
    if [ -z "$line" ]; then
        printf '%-16s ERROR\n' "$(basename "$file")"
        printf '%s\n' "$out" | sed 's/^/    /'
        failed=$((failed + 1))
        failing="$failing $(basename "$file")"
        continue
    fi
    n=$(printf '%s' "$line" | sed 's/ passed.*//')
    bad=$(printf '%s' "$line" | sed 's/.*passed, //;s/ failed.*//')
    total=$((total + n))
    if [ "$bad" -eq 0 ]; then
        printf '%-16s %3d ok\n' "$(basename "$file")" "$n"
    else
        printf '%-16s %3d ok, %d FAILED\n' "$(basename "$file")" "$n" "$bad"
        printf '%s\n' "$out" | grep -v '^PASS' | sed 's/^/    /'
        failed=$((failed + bad))
        failing="$failing $(basename "$file")"
    fi
done

echo
if [ -n "$untested" ]; then
    echo "no test file for:$untested"
fi

if [ "$failed" -eq 0 ]; then
    echo "$total assertions passed"
    exit 0
fi

echo "$total passed, $failed failed in:$failing"
exit 1
