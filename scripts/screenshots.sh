#!/bin/sh
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
#
# Regenerate the theme gallery images in docs/screenshots/.
#
# One page of the book is captured per theme, once in light mode and once
# in dark, and the pair is composited side by side. The site is built **once**:
# the HTML is identical for every theme, only assets/grimoire.css differs, so the
# loop swaps the stylesheet rather than rebuilding 10 times.
#
#   scripts/screenshots.sh              # all themes
#   scripts/screenshots.sh nordic ivy   # just these
#
# Requires: chromium (or CHROMIUM=...), ImageMagick, and a Jennifer interpreter.

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

CHROMIUM=${CHROMIUM:-chromium}
MAGICK=${MAGICK:-magick}
JENNIFER=${JENNIFER:-jennifer}

# The page to capture. The command reference has a bit of everything - prose, a
# code block, a table, both nav columns - so a theme's whole surface shows in one
# shot. Anything but themes.html, which is the gallery itself.
PAGE=${PAGE:-commands.html}
SRC=${SRC:-docs}
OUT=${OUT:-docs/screenshots}

# Captured wide enough for the three-column layout (the contents column appears
# at 1400px), then each half is scaled to 640 for a gallery image that is legible
# without being megabytes.
SHOT_W=${SHOT_W:-1440}
SHOT_H=${SHOT_H:-900}
HALF_W=${HALF_W:-640}
STRIP_H=${STRIP_H:-400}

for tool in "$CHROMIUM" "$MAGICK" "$JENNIFER"; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "screenshots: need $tool on PATH" >&2
        exit 1
    }
done

themes=$*
if [ -z "$themes" ]; then
    # Ask Grimoire itself rather than hardcoding a list that would drift.
    themes=$(./grimoire themes | sed -n 's/^  \([a-z][a-z0-9-]*\) - .*/\1/p')
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "building $SRC once (the HTML is theme-independent)"
./grimoire build --src "$SRC" --out "$work/site" --quiet

# Two copies of the page, each pinning a colour mode before the runtime can pick
# one. They live inside the site so their relative asset paths still resolve.
page_dir=$(dirname "$work/site/$PAGE")
for mode in light dark; do
    sed "s|<head>|<head><script>try{localStorage.setItem(\"grimoire-mode\",\"$mode\");}catch(e){}</script>|" \
        "$work/site/$PAGE" > "$page_dir/shot-$mode.html"
done

mkdir -p "$OUT"

for theme in $themes; do
    printf '  %-10s' "$theme"
    "$JENNIFER" run scripts/theme-css.j "$theme" "$work/site/assets/grimoire.css"

    for mode in light dark; do
        # A private profile per run. Without --user-data-dir a headless Chromium
        # tries to hand off to whatever instance already holds the default
        # profile, and hangs instead of rendering - and it would write into the
        # caller's real browser profile besides.
        "$CHROMIUM" --headless --disable-gpu --no-sandbox --hide-scrollbars \
            --user-data-dir="$work/chrome" --no-first-run --disable-extensions \
            --window-size="$SHOT_W,$SHOT_H" --virtual-time-budget=5000 \
            --screenshot="$work/$theme-$mode.png" \
            "file://$page_dir/shot-$mode.html" >/dev/null 2>&1
    done

    # Light on the left, dark on the right, with a hairline between them. The
    # PNG24: prefix forces 8-bit channels - this ImageMagick is a Q16 build and
    # would otherwise write 16-bit PNGs, three times the size for no visible gain.
    "$MAGICK" \
        \( "$work/$theme-light.png" -resize "${HALF_W}x" -crop "${HALF_W}x${STRIP_H}+0+0" +repage \) \
        \( -size 8x"$STRIP_H" xc:gray \) \
        \( "$work/$theme-dark.png" -resize "${HALF_W}x" -crop "${HALF_W}x${STRIP_H}+0+0" +repage \) \
        +append -strip "PNG24:$OUT/$theme.png"

    echo " -> $OUT/$theme.png ($(du -h "$OUT/$theme.png" | cut -f1))"
done

echo "done; $(ls "$OUT"/*.png | wc -l) images in $OUT/"
