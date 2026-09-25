#!/bin/sh
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
#
# The image entrypoint: enable the plugins the caller asked for, then hand
# everything else to Grimoire.
#
#   docker run --rm -e GRIMOIRE_PLUGINS=epub,linkcheck \
#       -v "$PWD:/work" grimoire build
#
# The image carries the plugin collection at /opt/grimoire-plugins, and carries
# it switched off. A plugin runs only when it has been enabled twice: named here,
# which puts it where Grimoire can find it, and named in the book's own
# `grimoire.toml`, which is what actually runs it. Neither half is a default.
#
# Two decisions worth stating. The links are made in a directory under /tmp
# rather than in the image, because the container may run as any uid - the
# `--user "$(id -u):$(id -g)"` a reader needs for a bind mount - and nothing but
# /tmp is writable for all of them. And an unknown name is an error rather than
# a warning: it is a typo, and failing here says so, where a build that silently
# skipped the plugin would report something less useful several minutes later.

set -eu

COLLECTION=/opt/grimoire-plugins
: "${GRIMOIRE_PLUGINS:=}"
: "${GRIMOIRE_PLUGIN_DIR:=/tmp/grimoire-plugins}"

# The names this image could enable: a directory with a launcher in it.
available() {
    for launcher in "$COLLECTION"/grimoire-*/grimoire-*; do
        [ -x "$launcher" ] || continue
        case "$launcher" in *.j) continue;; esac
        printf '%s ' "$(basename "$launcher" | sed 's/^grimoire-//')"
    done
}

if [ -n "$GRIMOIRE_PLUGINS" ]; then
    mkdir -p "$GRIMOIRE_PLUGIN_DIR"
    PATH="$GRIMOIRE_PLUGIN_DIR:$PATH"
    export PATH

    # Commas, semicolons or spaces: a list in an environment variable is written
    # every one of those ways, and none of them is worth an error message.
    for name in $(printf '%s' "$GRIMOIRE_PLUGINS" | tr ',;' '  '); do
        short=${name#grimoire-}
        launcher="$COLLECTION/grimoire-$short/grimoire-$short"
        if [ ! -x "$launcher" ]; then
            echo "grimoire: GRIMOIRE_PLUGINS names \"$name\", which this image does not carry" >&2
            echo "grimoire: available: $(available)" >&2
            exit 1
        fi
        ln -sf "$launcher" "$GRIMOIRE_PLUGIN_DIR/grimoire-$short"

        # What the plugin needs and the image has not got. A warning, not an
        # error: the book may not use the part that needs it, and the plugin
        # itself reports the failure in terms of what it was doing.
        needs="$COLLECTION/grimoire-$short/NEEDS"
        if [ -f "$needs" ]; then
            while read -r command_needed; do
                case "$command_needed" in ""|\#*) continue;; esac
                command -v "$command_needed" >/dev/null 2>&1 || \
                    echo "grimoire: plugin $short needs \"$command_needed\", which is not in this image" >&2
            done < "$needs"
        fi
    done
fi

# Hand the launcher to the interpreter rather than relying on its shebang, and
# `exec` so that Grimoire is the process the container waits on and signals
# reach it.
exec jennifer run /opt/grimoire/bin/grimoire "$@"
