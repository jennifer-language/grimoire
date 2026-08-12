# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Shared helpers for Grimoire: heading slugs, URL and path rewriting, text
 * squeezing, and the small string utilities every other module needs. Pure
 * string work with no I/O, so it stays testable and runs on both binaries.
 * @module util
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use strings;
use lists;
use maps;
use convert;

# The ASCII characters a slug keeps verbatim. Whitespace becomes a dash and every
# other ASCII character is dropped; see `slugify` for why that distinction is the
# whole point. Non-ASCII letters are kept too, which this set cannot express.
def const SLUG_KEEP as string init "abcdefghijklmnopqrstuvwxyz0123456789-_";

# The last ASCII code point. A character above it is a letter of some script the
# fold did not reduce to ASCII, and is kept rather than dropped.
def const ASCII_MAX as int init 127;

/**
 * Whether `url` points outside the generated site (an absolute URL, a protocol
 * relative URL, or a mail link) and must therefore be left untouched.
 * @param url {string} the raw link target
 * @return {bool} true when the target is external
 */
export func isExternal(url as string) {
    return strings.contains($url, "://") or strings.startsWith($url, "//") or
        strings.startsWith($url, "mailto:") or strings.startsWith($url, "tel:");
}

/**
 * A URL-safe anchor slug for a heading, in exactly the GitHub / mdBook shape:
 * diacritics folded, lowercased, whitespace turned into a dash, and every other
 * character **dropped** rather than folded into a separator.
 *
 * That last rule is the one that matters, and it is easy to get wrong. Dropping
 * punctuation is what makes a heading like ``REPL (`cmd/jennifer/repl.go`)``
 * anchor at `repl-cmdjenniferreplgo`; treating the slashes and dots as
 * separators would give `repl-cmd-jennifer-repl-go` instead and silently break
 * every hand-written cross-reference in a book migrated from mdBook. Runs of
 * dashes are likewise preserved, not collapsed - `M20 - System libraries`
 * anchors at `m20---system-libraries`.
 *
 * A character outside ASCII is kept as-is, so a book in a non-Latin script gets
 * real anchors rather than `section`, `section-1`, `section-2`.
 * @param text {string} the heading's flattened text
 * @return {string} the slug
 */
export func slugify(text as string) {
    def lowered as string init strings.lower(strings.fold($text));
    def out as list of string;
    for (def ch in strings.chars($lowered)) {
        if ($ch == " " or $ch == "\t" or $ch == "\n" or $ch == "\r") {
            $out[] = "-";
        } elseif (strings.contains(SLUG_KEEP, $ch)) {
            $out[] = $ch;
        } elseif (convert.toCodepoint($ch) > ASCII_MAX) {
            $out[] = $ch;
        }
    }
    if (len($out) == 0) {
        return "section";
    }
    return strings.join($out, "");
}

/**
 * Make `slug` unique against the slugs already handed out, appending `-1`, `-2`
 * and so on the way GitHub disambiguates repeated headings. The caller keeps the
 * `seen` map (slug to the number of times it has been issued) and layers the
 * returned slug back into it with `remember`.
 * @param seen {map of string to int} slugs already issued on this page
 * @param slug {string} the candidate slug
 * @return {string} a slug not yet present in `seen`
 */
export func uniqueSlug(seen as map of string to int, slug as string) {
    if (not maps.has($seen, $slug)) {
        return $slug;
    }
    def n as int init $seen[$slug];
    return $slug + "-" + convert.toString($n);
}

/**
 * Record that `slug` (derived from `base`) has been issued, returning the updated
 * counter map. Kept beside `uniqueSlug` because the two always travel together
 * and value semantics mean the caller must thread the map itself.
 * @param seen {map of string to int} slugs already issued on this page
 * @param base {string} the undisambiguated slug
 * @return {map of string to int} the updated counter map
 */
export func remember(seen as map of string to int, base as string) {
    def out as map of string to int init $seen;
    if (maps.has($out, $base)) {
        $out[$base] = $out[$base] + 1;
    } else {
        $out[$base] = 1;
    }
    return $out;
}

/**
 * The output path for a source page: the same relative path with a `.md`
 * extension swapped for `.html`, and `README.md` folded onto `index.html` so a
 * directory readme becomes its directory's landing page.
 * @param src {string} the source path, relative to the source root
 * @return {string} the output path, relative to the output root
 */
export func htmlPath(src as string) {
    def p as string init strings.replace($src, "\\", "/");
    def cut as int init len($p) - 3;
    if (strings.endsWith(strings.lower($p), ".md")) {
        $p = strings.substring($p, 0, $cut);
    }
    if ($p == "README" or strings.endsWith($p, "/README")) {
        $p = strings.substring($p, 0, len($p) - 6) + "index";
    }
    return $p + ".html";
}

/**
 * How many directory levels deep a site-relative path sits: `"index.html"` is 0,
 * `"guide/syntax.html"` is 1. Drives the `../` prefix that keeps every generated
 * page usable straight off the filesystem, with no web server.
 * @param path {string} a site-relative path
 * @return {int} the directory depth
 */
export func depthOf(path as string) {
    def n as int init 0;
    for (def ch in strings.chars($path)) {
        if ($ch == "/") {
            $n = $n + 1;
        }
    }
    return $n;
}

/**
 * The `../` chain that walks from a page at `depth` back to the site root ("" at
 * the root itself).
 * @param depth {int} the page's directory depth
 * @return {string} the relative prefix
 */
export func relPrefix(depth as int) {
    def out as string init "";
    for (def i in 0..$depth) {
        $out = $out + "../";
    }
    return $out;
}

/**
 * Collapse a path containing `.` and `..` segments, keeping it relative. Used to
 * resolve a link written relative to its own page into a site-relative path.
 * @param path {string} the path to clean
 * @return {string} the cleaned path
 */
export func cleanPath(path as string) {
    def parts as list of string;
    for (def seg in strings.split(strings.replace($path, "\\", "/"), "/")) {
        if ($seg == "" or $seg == ".") {
            continue;
        }
        if ($seg == ".." and len($parts) > 0 and $parts[len($parts) - 1] != "..") {
            $parts = lists.pop($parts);
            continue;
        }
        $parts[] = $seg;
    }
    return strings.join($parts, "/");
}

/**
 * The directory part of a site-relative path, without a trailing slash ("" for a
 * path at the root).
 * @param path {string} a site-relative path
 * @return {string} the directory part
 */
export func dirOf(path as string) {
    def idx as int init -1;
    def i as int init 0;
    for (def ch in strings.chars($path)) {
        if ($ch == "/") {
            $idx = $i;
        }
        $i = $i + 1;
    }
    if ($idx < 0) {
        return "";
    }
    return strings.substring($path, 0, $idx);
}

/**
 * Split an in-page fragment off a link target, returning `[target, fragment]`
 * where the fragment keeps its leading `#` (or is "" when there is none).
 * @param url {string} the raw link target
 * @return {list of string} the target and its fragment
 */
export func splitFragment(url as string) {
    def at as int init strings.indexOf($url, "#");
    if ($at < 0) {
        return [$url, ""];
    }
    return [strings.substring($url, 0, $at), strings.substring($url, $at, len($url))];
}

/**
 * Collapse every run of whitespace in `s` to a single space and trim the ends -
 * the shape body text needs before it goes into the search index or a snippet.
 * @param s {string} the text to squeeze
 * @return {string} the squeezed text
 */
export func squeeze(s as string) {
    # Whole-string library calls, not a per-rune loop: this runs over every block
    # of every chapter, and appending a rune at a time to a Jennifer string copies
    # the string each pass - quadratic on exactly the long inputs that matter.
    def flat as string init strings.replace($s, "\t", " ");
    $flat = strings.replace($flat, "\n", " ");
    $flat = strings.replace($flat, "\r", " ");
    def parts as list of string;
    for (def part in strings.split($flat, " ")) {
        if ($part != "") {
            $parts[] = $part;
        }
    }
    return strings.join($parts, " ");
}

/**
 * Truncate `s` to at most `limit` runes, cutting at the last space before the
 * limit so a snippet never ends mid-word. Adds no ellipsis - the caller decides
 * how a truncated value is presented.
 * @param s {string} the text to truncate
 * @param limit {int} the maximum rune count
 * @return {string} the truncated text
 */
export func truncate(s as string, limit as int) {
    if (len($s) <= $limit) {
        return $s;
    }
    def cut as string init strings.substring($s, 0, $limit);
    def parts as list of string init strings.split($cut, " ");
    if (len($parts) < 2) {
        return $cut;
    }
    def kept as string init strings.join(lists.pop($parts), " ");
    # Only honour the word boundary when it leaves a usable snippet; a single
    # enormous token would otherwise truncate to almost nothing.
    if (len($kept) > $limit // 2) {
        return $kept;
    }
    return $cut;
}

/**
 * Drop HTML comment lines (`<!-- ... -->`, whole-line only) from Markdown source.
 * The Markdown renderer has no notion of raw HTML, so a generator's banner
 * comment would otherwise surface as body text.
 * @param md {string} the Markdown source
 * @return {string} the source without whole-line HTML comments
 */
export func stripComments(md as string) {
    def out as list of string;
    def inside as bool init false;
    for (def line in strings.split($md, "\n")) {
        def t as string init strings.trim($line);
        if ($inside) {
            if (strings.contains($t, "-->")) {
                $inside = false;
            }
            continue;
        }
        if (strings.startsWith($t, "<!--")) {
            if (not strings.contains($t, "-->")) {
                $inside = true;
            }
            continue;
        }
        $out[] = $line;
    }
    return strings.join($out, "\n");
}

/**
 * Whether a trimmed line is a Markdown thematic break (three or more `-`, `*`, or
 * `_`, optionally spaced). The Markdown module models a break itself now, so this
 * is for `SUMMARY.md`, which is read line by line rather than parsed: there a
 * break is a separator between outline sections.
 * @param line {string} the trimmed line
 * @return {bool} true when the line is a thematic break
 */
export func isThematicBreak(line as string) {
    def marker as string init "";
    def count as int init 0;
    for (def ch in strings.chars($line)) {
        if ($ch == " " or $ch == "\t") {
            continue;
        }
        if ($ch != "-" and $ch != "*" and $ch != "_") {
            return false;
        }
        if ($marker == "") {
            $marker = $ch;
        } elseif ($ch != $marker) {
            return false;
        }
        $count = $count + 1;
    }
    return $count >= 3;
}
