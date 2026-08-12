# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The theme registry: it knows the shipped themes by name and hands back a
 * ready-to-write stylesheet. Adding a theme means writing one file under
 * `src/themes/` and listing it in `all()` here - nothing else in Grimoire needs
 * to know a theme exists.
 * @module theme
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use lists;

import "./palette.j" as palette;
import "./themes/grimoire.j" as grimoire;
import "./themes/obsidian.j" as obsidian;
import "./themes/ivy.j" as ivy;
import "./themes/ember.j" as ember;
import "./themes/meridian.j" as meridian;
import "./themes/nordic.j" as nordic;
import "./themes/carbon.j" as carbon;
import "./themes/orchid.j" as orchid;
import "./themes/sepia.j" as sepia;
import "./themes/terminal.j" as terminal;

/**
 * The name of the theme used when the configuration names none, or names one
 * that does not exist.
 * @return {string} the fallback theme name
 */
export func fallback() {
    return "grimoire";
}

/**
 * Every shipped theme, in presentation order.
 * @return {list of palette.Theme} the themes
 */
export func all() {
    return [
        grimoire.theme(),
        obsidian.theme(),
        meridian.theme(),
        nordic.theme(),
        carbon.theme(),
        ivy.theme(),
        sepia.theme(),
        orchid.theme(),
        ember.theme(),
        terminal.theme()
    ];
}

/**
 * The names of the shipped themes.
 * @return {list of string} the theme names
 */
export func names() {
    def out as list of string;
    for (def t in all()) {
        $out[] = $t.name;
    }
    return $out;
}

/**
 * Whether a theme of that name ships with grimoire.
 * @param name {string} the theme name
 * @return {bool} true when the name resolves
 */
export func has(name as string) {
    return lists.contains(names(), $name);
}

/**
 * Look a theme up by name, falling back to the default when the name is unknown
 * so a typo in `grimoire.toml` degrades to a themed site rather than no site.
 * @param name {string} the theme name
 * @return {palette.Theme} the theme
 */
export func byName(name as string) {
    def themes as list of palette.Theme init all();
    for (def t in $themes) {
        if ($t.name == $name) {
            return $t;
        }
    }
    return $themes[0];
}

/**
 * The stylesheet for a named theme, ready to write to `assets/grimoire.css`.
 * @param name {string} the theme name
 * @return {string} the stylesheet source
 */
export func stylesheet(name as string) {
    return palette.stylesheet(byName($name));
}

/**
 * A one-line catalog of the shipped themes, for `grimoire themes`.
 *
 * Sorted by name, which is what someone reading the list is looking one up by.
 * `all()` keeps its own order because `byName` falls back to its first entry -
 * sorting there would quietly hand the default to whichever theme sorts first.
 * Every line begins with the name, so sorting the rendered lines sorts by name.
 * @return {list of string} one description line per theme, alphabetically
 */
export func catalog() {
    def out as list of string;
    for (def t in all()) {
        $out[] = $t.name + " - " + $t.label + ": " + $t.description;
    }
    return lists.sort($out);
}
