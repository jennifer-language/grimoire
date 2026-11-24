# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.28.0

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
import "./themefile.j" as themefile;
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
import "./themes/sixtyfour.j" as sixtyfour;

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
        terminal.theme(),
        sixtyfour.theme()
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
 * The stylesheet for a theme, ready to write to `assets/grimoire.css`.
 *
 * A theme file's own stylesheet follows the generated one, so its rules and
 * its `--gr-*` overrides win over the shipped values.
 * @param spec {string} a shipped theme's name, or a theme file
 * @return {string} the stylesheet source
 * @throws {Error} kind "grimoire" when a theme file is unusable
 */
export func stylesheet(spec as string) {
    def t as themefile.Loaded init resolve($spec);
    def out as string init palette.stylesheet($t.theme);
    if ($t.css == "") {
        return $out;
    }
    return $out + "\n/* the theme's own stylesheet */\n" + $t.css;
}

/**
 * The theme an `html.theme` setting names, with a theme file's extras.
 *
 * A name is looked up among the shipped themes, falling back to the default
 * as `byName` does. A setting ending in `.toml` is a theme file, read on top
 * of the shipped theme it `extends` (the default when it names none).
 * @param spec {string} a shipped theme's name, or a theme file's path
 * @return {themefile.Loaded} the theme, its stylesheet and its files
 * @throws {Error} kind "grimoire" when a theme file is unusable or extends an
 *   unknown theme
 */
export func resolve(spec as string) {
    if (not themefile.isFile($spec)) {
        return themefile.Loaded{theme: byName($spec), css: "", files: [], dir: ""};
    }
    def base as string init themefile.extendsOf($spec);
    if ($base == "") {
        $base = fallback();
    }
    if (not has($base)) {
        throw Error{
            kind: "grimoire",
            message: "theme " + $spec + ": extends " + $base + ", which is not a shipped theme" +
                " (see: grimoire themes)",
            file: $spec,
            line: 0,
            col: 0
        };
    }
    return themefile.load($spec, byName($base));
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
