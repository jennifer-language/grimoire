# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The book outline: a `SUMMARY.md` parser in the mdBook shape (part headings,
 * nested list entries, prefix and suffix chapters, draft entries, separators)
 * and an automatic fallback that derives an outline by walking the source
 * directory when no `SUMMARY.md` is present. Both produce the same flat
 * `list of Entry`, which is all the sidebar, the page chain, and the PDF need.
 * @module summary
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use strings;
use lists;
use fs;
use path;
use convert;

import "./util.j" as util;

# The four things a line of a SUMMARY can contribute. A "draft" is an entry with
# a title but no target - mdBook's placeholder for a chapter not yet written; it
# shows in the sidebar, greyed out and unlinked.
def const PART as string init "part";
def const PAGE as string init "page";
def const DRAFT as string init "draft";
def const SEPARATOR as string init "separator";

/**
 * One line of the book outline.
 * @field kind {string} "part", "page", "draft", or "separator"
 * @field title {string} the display title (empty for a separator)
 * @field src {string} the source path relative to the source root (pages only)
 * @field out {string} the output path relative to the site root (pages only)
 * @field level {int} the nesting depth, 0 for a top-level entry
 * @field number {string} the dotted section number ("" when unnumbered)
 */
export def struct Entry {
    kind as string,
    title as string,
    src as string,
    out as string,
    level as int,
    number as string
};

/**
 * The kind constant for a part heading.
 * @return {string} "part"
 */
export func partKind() {
    return PART;
}

/**
 * The kind constant for a linked page.
 * @return {string} "page"
 */
export func pageKind() {
    return PAGE;
}

/**
 * The kind constant for a draft (titled but unlinked) entry.
 * @return {string} "draft"
 */
export func draftKind() {
    return DRAFT;
}

/**
 * The kind constant for a separator rule.
 * @return {string} "separator"
 */
export func separatorKind() {
    return SEPARATOR;
}

# indentOf counts the leading blanks of a line, a tab standing for four spaces -
# the unit mdBook itself uses when a SUMMARY mixes the two.
func indentOf(line as string) {
    def n as int init 0;
    for (def ch in strings.chars($line)) {
        if ($ch == " ") {
            $n = $n + 1;
        } elseif ($ch == "\t") {
            $n = $n + 4;
        } else {
            break;
        }
    }
    return $n;
}

# stripMarker removes a leading list marker (`-`, `*`, `+`, or `12.`) and returns
# the remainder, or "" when the line does not start with one.
func stripMarker(text as string) {
    if (strings.startsWith($text, "- ") or strings.startsWith($text, "* ") or
        strings.startsWith($text, "+ ")) {
        return strings.trim(strings.substring($text, 2, len($text)));
    }
    def digits as int init 0;
    for (def ch in strings.chars($text)) {
        if ($ch >= "0" and $ch <= "9") {
            $digits = $digits + 1;
        } else {
            break;
        }
    }
    if ($digits > 0 and strings.startsWith(strings.substring($text, $digits, len($text)), ". ")) {
        return strings.trim(strings.substring($text, $digits + 2, len($text)));
    }
    return "";
}

# linkParts pulls `[title](target)` apart into `[title, target]`, or returns an
# empty list when the text is not a single Markdown link. Nested brackets are not
# supported, matching the Markdown module's own inline scanner.
func linkParts(text as string) {
    def empty as list of string;
    if (not strings.startsWith($text, "[")) {
        return $empty;
    }
    def mid as int init strings.indexOf($text, "](");
    if ($mid < 0) {
        return $empty;
    }
    def close as int init strings.indexOf(strings.substring($text, $mid, len($text)), ")");
    if ($close < 0) {
        return $empty;
    }
    def title as string init strings.substring($text, 1, $mid);
    def target as string init strings.substring($text, $mid + 2, $mid + $close);
    return [strings.trim($title), strings.trim($target)];
}

# nextNumber advances the dotted section counter to `level` and renders it. The
# counter list is threaded through the caller because a Jennifer value is copied,
# not shared - so the updated counters come back alongside the rendered number.
func advance(counters as list of int, level as int) {
    def c as list of int init $counters;
    while (len($c) > $level + 1) {
        $c = lists.pop($c);
    }
    while (len($c) < $level + 1) {
        $c[] = 0;
    }
    $c[$level] = $c[$level] + 1;
    return $c;
}

func renderNumber(counters as list of int) {
    def parts as list of string;
    for (def n in $counters) {
        $parts[] = convert.toString($n);
    }
    return strings.join($parts, ".");
}

/**
 * Parse `SUMMARY.md` source into the book outline. Recognised lines are a
 * `# Part heading`, a `- [Title](path.md)` entry (nested by indentation, and
 * numbered continuously across the book), a bare `[Title](path.md)` prefix or
 * suffix chapter, a `- [Title]()` draft, and a `---` separator. Anything else -
 * prose, HTML comments, blank lines - is ignored, so a hand-maintained SUMMARY
 * with notes in it still parses.
 * @param text {string} the `SUMMARY.md` source
 * @return {list of Entry} the outline, in reading order
 */
export func parse(text as string) {
    def out as list of Entry;
    def counters as list of int;
    def baseIndent as int init -1;
    for (def rawLine in strings.split(util.stripComments($text), "\n")) {
        def trimmed as string init strings.trim($rawLine);
        if ($trimmed == "") {
            continue;
        }
        if (util.isThematicBreak($trimmed)) {
            $out[] = Entry{kind: SEPARATOR, title: "", src: "", out: "", level: 0, number: ""};
            continue;
        }
        if (strings.startsWith($trimmed, "#")) {
            def heading as string init strings.trim(strings.replace($trimmed, "#", ""));
            # The conventional `# Summary` title is the document's own heading, not
            # a part of the book; every other heading opens a part.
            if (strings.lower($heading) != "summary") {
                $out[] = Entry{kind: PART, title: $heading, src: "", out: "", level: 0, number: ""};
            }
            continue;
        }
        def item as string init stripMarker($trimmed);
        def listed as bool init $item != "";
        if (not $listed) {
            $item = $trimmed;
        }
        def parts as list of string init linkParts($item);
        if (len($parts) != 2) {
            continue;
        }
        def indent as int init indentOf($rawLine);
        if ($listed and $baseIndent < 0) {
            $baseIndent = $indent;
        }
        def level as int init 0;
        if ($listed and $indent > $baseIndent) {
            $level = ($indent - $baseIndent) // 2;
        }
        def target as string init $parts[1];
        if ($target == "") {
            $out[] = Entry{
                kind: DRAFT,
                title: $parts[0],
                src: "",
                out: "",
                level: $level,
                number: ""
            };
            continue;
        }
        def src as string init util.cleanPath($target);
        def number as string init "";
        # Prefix and suffix chapters (a link with no list marker) sit outside the
        # numbering, exactly as they do in mdBook.
        if ($listed) {
            $counters = advance($counters, $level);
            $number = renderNumber($counters);
        }
        $out[] = Entry{
            kind: PAGE,
            title: $parts[0],
            src: $src,
            out: util.htmlPath($src),
            level: $level,
            number: $number
        };
    }
    return $out;
}

# markdownFiles walks `dir` and returns every Markdown source under it, as paths
# relative to `dir`, sorted so the generated outline is deterministic.
func markdownFiles(dir as string) {
    def out as list of string;
    def prefix as int init len($dir) + 1;
    for (def st in fs.walk($dir)) {
        if ($st.isDir) {
            continue;
        }
        def rel as string init strings.substring($st.path, $prefix, len($st.path));
        if (strings.lower(path.ext($rel)) != ".md") {
            continue;
        }
        if (strings.lower(path.base($rel)) == "summary.md") {
            continue;
        }
        $out[] = strings.replace($rel, "\\", "/");
    }
    return lists.sort($out);
}

# titleFor derives a display title from a file name: `first-program.md` becomes
# "First program". Used only by the automatic outline; a SUMMARY always wins.
func titleFor(rel as string) {
    def stem as string init path.stem($rel);
    if ($stem == "index" or $stem == "README") {
        def dir as string init util.dirOf($rel);
        if ($dir == "") {
            return "Introduction";
        }
        $stem = path.base($dir);
    }
    def words as string init strings.replace(strings.replace($stem, "-", " "), "_", " ");
    if ($words == "") {
        return $rel;
    }
    def head as string init strings.upper(strings.substring($words, 0, 1));
    return $head + strings.substring($words, 1, len($words));
}

# indexFirst sorts a directory's own landing page ahead of its siblings, so an
# automatic outline opens each section with its overview.
func rankOf(rel as string) {
    def stem as string init path.stem($rel);
    if ($stem == "index" or $stem == "README") {
        return 0;
    }
    return 1;
}

/**
 * Derive an outline by walking the source directory, for a book with no
 * `SUMMARY.md`. Files sort alphabetically inside each directory with the
 * directory's own `index.md` / `README.md` first, and each subdirectory opens a
 * part named after itself - the shape MkDocs produces from a bare directory of
 * Markdown.
 * @param dir {string} the source directory
 * @return {list of Entry} the generated outline
 */
export func fromDirectory(dir as string) {
    def files as list of string init markdownFiles($dir);
    def roots as list of string;
    def nested as list of string;
    for (def rel in $files) {
        if (util.dirOf($rel) == "") {
            $roots[] = $rel;
        } else {
            $nested[] = $rel;
        }
    }
    def out as list of Entry;
    def counters as list of int;
    for (def rel in $roots) {
        if (rankOf($rel) != 0) {
            continue;
        }
        $out[] = Entry{
            kind: PAGE,
            title: titleFor($rel),
            src: $rel,
            out: util.htmlPath($rel),
            level: 0,
            number: ""
        };
    }
    for (def rel in $roots) {
        if (rankOf($rel) == 0) {
            continue;
        }
        $counters = advance($counters, 0);
        $out[] = Entry{
            kind: PAGE,
            title: titleFor($rel),
            src: $rel,
            out: util.htmlPath($rel),
            level: 0,
            number: renderNumber($counters)
        };
    }
    def currentDir as string init "";
    for (def rel in $nested) {
        def dirName as string init util.dirOf($rel);
        if ($dirName != $currentDir) {
            $currentDir = $dirName;
            $out[] = Entry{
                kind: PART,
                title: titleFor($dirName + "/index.md"),
                src: "",
                out: "",
                level: 0,
                number: ""
            };
        }
        $counters = advance($counters, 0);
        $out[] = Entry{
            kind: PAGE,
            title: titleFor($rel),
            src: $rel,
            out: util.htmlPath($rel),
            level: 0,
            number: renderNumber($counters)
        };
    }
    return $out;
}

/**
 * Load the book outline for a source directory: `SUMMARY.md` when it exists,
 * otherwise an outline derived from the directory tree.
 * @param dir {string} the source directory
 * @return {list of Entry} the outline, in reading order
 */
export func load(dir as string) {
    def file as string init path.join($dir, "SUMMARY.md");
    if (fs.isFile($file)) {
        return parse(fs.readString($file));
    }
    return fromDirectory($dir);
}

/**
 * Just the linked pages of an outline, in reading order - the sequence the
 * previous / next chain and the PDF walk.
 * @param entries {list of Entry} the outline
 * @return {list of Entry} the page entries
 */
export func pages(entries as list of Entry) {
    def out as list of Entry;
    for (def e in $entries) {
        if ($e.kind == PAGE) {
            $out[] = $e;
        }
    }
    return $out;
}
