#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Write one theme's stylesheet to a path.
 *
 * The screenshot script needs to swap a built site between themes without
 * rebuilding it - the HTML is identical for every theme, only
 * `assets/grimoire.css` changes - and this is the one line of Grimoire it needs
 * to reach in order to do that.
 *
 *   jennifer run scripts/theme-css.j nordic site/assets/grimoire.css
 *
 * @module themecss
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use os;
use fs;
use strings;

import "../src/theme.j" as theme;

if (len(os.ARGS) < 3) {
    io.eprintf("usage: theme-css.j <theme> <output.css>\n");
    exit 2;
}

def name as string init os.ARGS[1];
if (not theme.has($name)) {
    io.eprintf(
        "theme-css.j: unknown theme %s (have: %s)\n",
        $name,
        strings.join(theme.names(), ", "));
    exit 1;
}

fs.writeString(os.ARGS[2], theme.stylesheet($name));
