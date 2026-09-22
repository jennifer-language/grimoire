#!/bin/sh
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
#
# The punctuation rule, as a check: no em dash, no en dash, no curly quote, no
# typographic ellipsis, no non-breaking space, and none of the symbols that have
# an ASCII reading - arrows, box drawing, check marks, emoji. In source, in
# comments, in docblocks, in Markdown, in commit messages, anywhere.
#
# Letters are not checked. An umlaut in a German test fixture, a Cyrillic stop
# word, a Polish translation: each is the character as data, and none of them is
# what the rule is about. The rule is about characters that arrive invisibly - a
# curly quote is indistinguishable from an apostrophe in most editors and in
# every diff - and those are the ones named below. Banning every non-ASCII
# character instead costs an exception, in three places, for each file that
# legitimately holds letters.
#
#   scripts/check-style.sh
#
# Prints every offending line and exits 1, or prints nothing and exits 0.

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

# The ranges, in the order they appear in Unicode:
#   00A0  no-break space            00AD  soft hyphen (invisible)
#   2000-206F general punctuation   - every dash, quote, and ellipsis
#   2190-22FF arrows and operators  - `->`, `<=`, `!=` say the same thing
#   2300-27BF technical to dingbats - box drawing, check marks, stars, hearts
#   2B00-2BFF more symbols and arrows
#   FE00-FE0F variation selectors   FEFF byte-order mark (both invisible)
#   1F000-1FAFF emoji
BANNED='[\x{00A0}\x{00AD}\x{2000}-\x{206F}\x{2190}-\x{22FF}\x{2300}-\x{27BF}\x{2B00}-\x{2BFF}\x{FE00}-\x{FE0F}\x{FEFF}\x{1F000}-\x{1FAFF}]'

# `src/pdfbook.j` is a table **of** these characters and their ASCII readings,
# so it has to contain them. `grimoire.toml` is this book's own authored
# content, which the rule exempts by name: `authorsLabel` is the author
# speaking to a reader, and the printable build transliterates it like any
# other text.
EXEMPT='^\./(src/pdfbook\.j|grimoire\.toml):'

found=$(grep -rnP "$BANNED" \
    --include='*.j' --include='*.md' --include='*.toml' \
    --include='*.sh' --include='*.yml' --include='Dockerfile' \
    --include='PKGBUILD*' . | grep -Ev "$EXEMPT" || true)

if [ -n "$found" ]; then
    echo "typographic characters that belong in ASCII:" >&2
    echo "$found" >&2
    exit 1
fi
