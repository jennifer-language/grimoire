# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.28.0

/**
 * Custom themes: a theme read from a TOML file instead of compiled in.
 *
 * A book that wants its own colours names a file in `html.theme`
 * (`theme = "theme/house.toml"`). The file gives the same things a shipped
 * theme does - the two palettes, the three font stacks, the corner radius and
 * the measure - and any it leaves out come from the shipped theme it
 * `extends`. It can add a stylesheet, appended after the generated one, and
 * the files that stylesheet needs (web fonts), copied into the site's assets.
 *
 * Strict, unlike `grimoire.toml`: a configuration typo falls back to a
 * default, but a theme file is something the book asked for by name, so a
 * missing file, an unknown key or an unusable colour stops the build with a
 * message naming it. Every value ends up in a stylesheet, which is also why
 * the values are checked rather than passed through.
 * @module themefile
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use toml;
use fs;
use path;
use strings;
use regex;
use lists;
use convert;

import "./palette.j" as palette;

/**
 * A theme read from a file, with what the site needs beyond the palette.
 * @field theme {palette.Theme} the resolved theme, every slot filled
 * @field css {string} the extra stylesheet's text, `""` for none
 * @field files {list of string} files to copy into `assets/`, relative to `dir`
 * @field dir {string} the directory the theme file sits in
 */
export def struct Loaded {
    theme as palette.Theme,
    css as string,
    files as list of string,
    dir as string
};

/** The keys a theme file may carry at its top level. */
def const TOP_KEYS as list of string init [
    "name",
    "label",
    "description",
    "extends",
    "radius",
    "contentWidth",
    "stylesheet",
    "files",
    "fonts",
    "light",
    "dark"
];

/** The palette slots, in the order the `Palette` struct declares them. */
def const SLOTS as list of string init [
    "bg",
    "surface",
    "surfaceAlt",
    "border",
    "text",
    "muted",
    "heading",
    "accent",
    "accentHover",
    "onAccent",
    "codeText",
    "codeBg",
    "selection",
    "shadow"
];

/**
 * The light-palette slots the printed book draws with. The PDF writer takes a
 * colour as `#rrggbb`, so these must be written that way.
 */
def const PRINTED_SLOTS as list of string init [
    "surface",
    "surfaceAlt",
    "border",
    "muted",
    "accent",
    "codeBg"
];

/** A hex colour: three, four, six or eight digits. */
def const HEX_COLOUR as string init '^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$';

/** A functional colour; its arguments are numbers, units and separators only. */
def const FUNCTION_COLOUR as string init '^(rgb|rgba|hsl|hsla)\([0-9.,% /deg-]+\)$';

/** The six-digit hex form the printed book reads. */
def const HEX6 as string init '^#[0-9a-fA-F]{6}$';

/** The font roles a theme file may set. */
def const FONT_KEYS as list of string init ["body", "heading", "mono"];

/**
 * Whether a theme setting names a file rather than a shipped theme.
 * @param spec {string} the `html.theme` value
 * @return {bool} true when it ends in `.toml`
 */
export func isFile(spec as string) {
    return strings.endsWith($spec, ".toml");
}

/**
 * Read a theme file.
 * @param file {string} the theme file
 * @param base {palette.Theme} the shipped theme it extends (the caller looks it up)
 * @return {Loaded} the theme and its extras
 * @throws {Error} kind "grimoire" when the file is missing or unusable
 */
export func load(file as string, base as palette.Theme) {
    if (not fs.isFile($file)) {
        bad($file, "no such theme file");
    }
    def doc as toml.Value init toml.decode("");
    try {
        $doc = toml.decode(fs.readString($file));
    } catch (e) {
        bad($file, "not a TOML document: " + $e.message);
    }
    checkKeys($file, $doc, "", TOP_KEYS);
    def t as palette.Theme init $base;
    $t.name = text($file, $doc, "/name", path.stem($file));
    $t.label = text($file, $doc, "/label", $t.name);
    $t.description = text($file, $doc, "/description", "");
    $t.radius = number($file, $doc, "/radius", $t.radius, 0, 64);
    $t.contentWidth = number($file, $doc, "/contentWidth", $t.contentWidth, 480, 1600);
    if (toml.has($doc, "/fonts")) {
        checkKeys($file, $doc, "/fonts", FONT_KEYS);
        $t.fontBody = font($file, $doc, "/fonts/body", $t.fontBody);
        $t.fontHeading = font($file, $doc, "/fonts/heading", $t.fontHeading);
        $t.fontMono = font($file, $doc, "/fonts/mono", $t.fontMono);
    }
    $t.light = paletteFrom($file, $doc, "/light", $t.light);
    $t.dark = paletteFrom($file, $doc, "/dark", $t.dark);
    for (def slot in PRINTED_SLOTS) {
        if (not isHex6(slotOf($t.light, $slot))) {
            bad(
                $file,
                "light." + $slot + " must be #rrggbb: the printed book draws with it (got " +
                    slotOf($t.light, $slot) + ")");
        }
    }
    def dir as string init path.dir($file);
    def css as string init "";
    def sheet as string init text($file, $doc, "/stylesheet", "");
    if ($sheet != "") {
        def sheetPath as string init path.join($dir, relative($file, "stylesheet", $sheet));
        if (not fs.isFile($sheetPath)) {
            bad($file, "stylesheet " + $sheet + " is not a file next to the theme");
        }
        $css = fs.readString($sheetPath);
    }
    def files as list of string init [];
    if (toml.has($doc, "/files")) {
        if (toml.typeOf($doc, "/files") != "list") {
            bad($file, "files must be a list of paths");
        }
        for (def i in 0..toml.length($doc, "/files")) {
            def ptr as string init "/files/" + convert.toString($i);
            if (toml.typeOf($doc, $ptr) != "string") {
                bad($file, "files must be a list of paths");
            }
            def one as string init relative($file, "files", toml.asString($doc, $ptr));
            if (not fs.isFile(path.join($dir, $one))) {
                bad($file, "files: " + $one + " is not a file next to the theme");
            }
            $files[] = $one;
        }
    }
    return Loaded{theme: $t, css: $css, files: $files, dir: $dir};
}

/**
 * The name of the shipped theme a theme file extends.
 *
 * Read on its own so the registry can look the base up before the file is
 * loaded on top of it.
 * @param file {string} the theme file
 * @return {string} the `extends` value, `""` when the file names none
 * @throws {Error} kind "grimoire" when the file is missing or not TOML
 */
export func extendsOf(file as string) {
    if (not fs.isFile($file)) {
        bad($file, "no such theme file");
    }
    def doc as toml.Value init toml.decode("");
    try {
        $doc = toml.decode(fs.readString($file));
    } catch (e) {
        bad($file, "not a TOML document: " + $e.message);
    }
    return text($file, $doc, "/extends", "");
}

# paletteFrom overlays a [light] or [dark] table on the base palette.
func paletteFrom(file as string, doc as toml.Value, table as string, base as palette.Palette) {
    if (not toml.has($doc, $table)) {
        return $base;
    }
    checkKeys($file, $doc, $table, SLOTS);
    def out as palette.Palette init $base;
    for (def slot in toml.keys($doc, $table)) {
        def ptr as string init $table + "/" + $slot;
        if (toml.typeOf($doc, $ptr) != "string") {
            bad($file, $table[1..] + "." + $slot + " must be a colour string");
        }
        def colour as string init strings.trim(toml.asString($doc, $ptr));
        if (not isColour($colour)) {
            bad(
                $file,
                $table[1..] + "." + $slot + " is not a colour: " + $colour +
                    " (use #rgb, #rrggbb, #rrggbbaa, rgb(), rgba(), hsl() or hsla())");
        }
        $out = withSlot($out, $slot, $colour);
    }
    return $out;
}

# checkKeys refuses a key the table does not define.
func checkKeys(file as string, doc as toml.Value, table as string, allowed as list of string) {
    if (toml.typeOf($doc, $table) != "map") {
        bad($file, "[" + $table[1..] + "] must be a table");
    }
    for (def key in toml.keys($doc, $table)) {
        if (not lists.contains($allowed, $key)) {
            def where as string init "";
            if ($table != "") {
                $where = " in [" + $table[1..] + "]";
            }
            bad($file, "unknown key " + $key + $where + "; known: " + strings.join($allowed, ", "));
        }
    }
}

# text reads an optional string value.
func text(file as string, doc as toml.Value, ptr as string, deflt as string) {
    if (not toml.has($doc, $ptr)) {
        return $deflt;
    }
    if (toml.typeOf($doc, $ptr) != "string") {
        bad($file, $ptr[1..] + " must be a string");
    }
    def value as string init toml.asString($doc, $ptr);
    if (regex.matches('[<>{};]', $value)) {
        bad($file, $ptr[1..] + ' may not contain any of < > { } ;');
    }
    return $value;
}

# number reads an optional int value within bounds.
func number(file as string, doc as toml.Value, ptr as string, deflt as int, lo as int, hi as int) {
    if (not toml.has($doc, $ptr)) {
        return $deflt;
    }
    if (toml.typeOf($doc, $ptr) != "int") {
        bad($file, $ptr[1..] + " must be an integer");
    }
    def value as int init toml.asInt($doc, $ptr);
    if ($value < $lo or $value > $hi) {
        bad(
            $file,
            $ptr[1..] + " must be from " + convert.toString($lo) + " to " +
                convert.toString($hi) + ", got " + convert.toString($value));
    }
    return $value;
}

# font reads an optional font stack. A stack goes into a CSS declaration, so
# anything that could end the declaration is refused.
func font(file as string, doc as toml.Value, ptr as string, deflt as string) {
    def value as string init text($file, $doc, $ptr, $deflt);
    if (strings.trim($value) == "") {
        bad($file, $ptr[1..] + " may not be empty");
    }
    if (strings.contains($value, "\\")) {
        bad($file, $ptr[1..] + " may not contain a backslash");
    }
    return $value;
}

# relative checks a path the theme names: relative to the theme, inside its
# directory.
func relative(file as string, what as string, value as string) {
    def clean as string init path.clean($value);
    if ($value == "" or path.isAbs($value) or $clean == ".." or strings.startsWith($clean, "../")) {
        bad($file, $what + ": " + $value + " must be a path inside the theme's directory");
    }
    return $clean;
}

/**
 * Whether a string is a CSS colour a theme may use.
 * @param value {string} the candidate
 * @return {bool} true for hex (3, 4, 6 or 8 digits) or an rgb() / rgba() / hsl() / hsla() form
 */
export func isColour(value as string) {
    return regex.matches(HEX_COLOUR, $value) or regex.matches(FUNCTION_COLOUR, $value);
}

# isHex6 is the one form the printed book reads.
func isHex6(value as string) {
    return regex.matches(HEX6, $value);
}

# slotOf reads a palette slot by name.
func slotOf(p as palette.Palette, slot as string) {
    match ($slot) {
        when "bg" { return $p.bg; }
        when "surface" { return $p.surface; }
        when "surfaceAlt" { return $p.surfaceAlt; }
        when "border" { return $p.border; }
        when "text" { return $p.text; }
        when "muted" { return $p.muted; }
        when "heading" { return $p.heading; }
        when "accent" { return $p.accent; }
        when "accentHover" { return $p.accentHover; }
        when "onAccent" { return $p.onAccent; }
        when "codeText" { return $p.codeText; }
        when "codeBg" { return $p.codeBg; }
        when "selection" { return $p.selection; }
        else { return $p.shadow; }
    }
}

# withSlot sets a palette slot by name.
func withSlot(p as palette.Palette, slot as string, colour as string) {
    def out as palette.Palette init $p;
    match ($slot) {
        when "bg" { $out.bg = $colour; }
        when "surface" { $out.surface = $colour; }
        when "surfaceAlt" { $out.surfaceAlt = $colour; }
        when "border" { $out.border = $colour; }
        when "text" { $out.text = $colour; }
        when "muted" { $out.muted = $colour; }
        when "heading" { $out.heading = $colour; }
        when "accent" { $out.accent = $colour; }
        when "accentHover" { $out.accentHover = $colour; }
        when "onAccent" { $out.onAccent = $colour; }
        when "codeText" { $out.codeText = $colour; }
        when "codeBg" { $out.codeBg = $colour; }
        when "selection" { $out.selection = $colour; }
        else { $out.shadow = $colour; }
    }
    return $out;
}

# bad stops the build over the theme file.
func bad(file as string, message as string) {
    throw Error{
        kind: "grimoire",
        message: "theme " + $file + ": " + $message,
        file: $file,
        line: 0,
        col: 0
    };
}
