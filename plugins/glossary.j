# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The first use of a glossary term on a page, linked to its definition.
 *
 * A preprocessor. The terms are the headings of the glossary chapter, so the
 * list maintains itself: a definition added there starts being linked on the
 * next build, and one renamed stops. An optional terms file adds the words that
 * are not headings - a plural, an abbreviation, the spelling everybody actually
 * writes.
 *
 * Only the **first** occurrence on a page is linked. A term linked at every
 * mention is a page of blue text, and the second link is never the one a reader
 * follows.
 *
 * What is never touched: the glossary chapter itself, headings, fenced code,
 * inline code, and anything already inside a link. A term inside a code span is
 * usually the thing rather than the word for the thing.
 * @module glossary
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use fs;
use path;
use json;
use toml;
use strings;
use convert;
use lists;
use maps;

def const API as int init 1;

# The characters a slug keeps, and the rule around them: this mirrors Grimoire's
# own `util.slugify`, because the anchor has to be the one Grimoire wrote into
# the page. Diacritics folded, lowercased, whitespace to a dash, everything else
# dropped rather than turned into a separator.
def const SLUG_KEEP as string init "abcdefghijklmnopqrstuvwxyz0123456789-_";
def const ASCII_MAX as int init 127;

# A character that can be part of a word. A term matches only when what is
# around it is not one of these, so "index" does not match inside "indexed".
def const WORD as string init "abcdefghijklmnopqrstuvwxyz0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ";

# A refusal, rather than an exit: `run` turns it into a status and a message on
# stderr, and a test can catch it. `exit` inside a module would take the test
# runner with it.
func fail(message as string) {
    throw Error{kind: "plugin", message: $message, file: "", line: 0, col: 0};
}

/**
 * One glossary entry: the word to look for, and where its definition is.
 * @field word {string} the term, as it is written in the glossary
 * @field anchor {string} the fragment its definition lives at
 */
export def struct Term {
    word as string,
    anchor as string
};

/**
 * A heading's anchor, the way Grimoire writes it.
 * @param text {string} the heading text
 * @return {string} the fragment, without the `#`
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

# The heading text of one line, or "" when the line is not a heading of the
# wanted depth. Trailing hashes are the closed ATX form and are not part of the
# text.
func headingAt(line as string, depth as int) {
    def marker as string init strings.repeat("#", $depth) + " ";
    if (not strings.startsWith($line, $marker)) {
        return "";
    }
    def text as string init strings.trim(strings.substring($line, len($marker), len($line)));
    while (strings.endsWith($text, "#")) {
        $text = strings.trim(strings.substring($text, 0, len($text) - 1));
    }
    return $text;
}

/**
 * The terms a glossary chapter defines: its headings at one depth.
 *
 * Fenced code is skipped, so a `#` inside a shell example is not a definition.
 * @param content {string} the glossary chapter, as Markdown
 * @param depth {int} the heading level the definitions sit at
 * @return {list of Term} the terms, in the order the chapter defines them
 */
export func termsIn(content as string, depth as int) {
    def out as list of Term;
    def fenced as bool init false;
    for (def line in strings.split($content, "\n")) {
        def trimmed as string init strings.trim($line);
        if (strings.startsWith($trimmed, "```") or strings.startsWith($trimmed, "~~~")) {
            $fenced = not $fenced;
            continue;
        }
        if ($fenced) {
            continue;
        }
        def text as string init headingAt($line, $depth);
        if ($text == "") {
            continue;
        }
        $out[] = Term{word: $text, anchor: slugify($text)};
    }
    return $out;
}

/**
 * The extra terms a terms file names.
 *
 * A file of alias to term: `"outlines" = "outline"` links the plural to the
 * definition of the singular. A value that is empty means the alias is itself a
 * heading, which is the case for a term whose spelling only differs in case.
 * @param file {string} the path to the TOML file
 * @param defined {list of Term} the terms the chapter defines
 * @return {list of Term} the aliases, with the anchors they resolve to
 * @throws {Error} kind "plugin" when the file is missing or names an unknown term
 */
export func aliasesIn(file as string, defined as list of Term) {
    def out as list of Term;
    if (not fs.isFile($file)) {
        fail("terms file not found: " + $file);
    }
    def anchors as map of string to string;
    for (def term in $defined) {
        $anchors[strings.lower($term.word)] = $term.anchor;
    }
    def doc as toml.Value init toml.decode(fs.readString($file));
    if (not toml.has($doc, "/terms")) {
        return $out;
    }
    # Sorted rather than taken in the order the file lists them: two terms of the
    # same length are matched in the order they arrive here, and a build says the
    # same thing twice only if that order is decided rather than inherited.
    for (def alias in lists.sort(toml.keys($doc, "/terms"))) {
        def wanted as string init strings.lower(toml.asString(
            $doc,
            "/terms/" + strings.replace($alias, "/", "~1")));
        if ($wanted == "") {
            $wanted = strings.lower($alias);
        }
        if (not maps.has($anchors, $wanted)) {
            fail("terms file: \"" + $alias + "\" points at \"" + $wanted +
                "\", which the glossary does not define");
        }
        $out[] = Term{word: $alias, anchor: $anchors[$wanted]};
    }
    return $out;
}

# The sort key: the negative length, because `lists.sortBy` sorts ascending by a
# key and what is wanted is longest first - "search index" matched before
# "index", so the shorter term does not eat the longer one's first word. The sort
# is stable, so terms of the same length stay in the order the glossary defines
# them.
func negativeLength(term as Term) {
    return 0 - len($term.word);
}

/**
 * The terms to look for, longest first.
 * @param chapter {list of Term} what the glossary chapter defines
 * @param extra {list of Term} what the terms file adds
 * @return {list of Term} all of them, in matching order
 */
export func ordered(chapter as list of Term, extra as list of Term) {
    def all as list of Term init $chapter;
    for (def term in $extra) {
        $all[] = $term;
    }
    return lists.sortBy($all, negativeLength);
}

# --- finding a term in prose ---------------------------------------

# The regions of a line a term must not be found in, blanked out to keep every
# position where it was: inline code, an existing link or image, a reference
# definition, and a raw HTML tag or autolink. The result is the same length as
# the line, so an index into it is an index into the line.
func masked(line as string) {
    def out as list of string;
    def chars as list of string init strings.chars($line);
    def i as int init 0;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        def closer as string init "";
        if ($ch == "`") {
            $closer = "`";
        } elseif ($ch == "[") {
            $closer = ")";
        } elseif ($ch == "<") {
            $closer = ">";
        }
        if ($closer == "") {
            $out[] = $ch;
            $i = $i + 1;
            continue;
        }
        def stop as int init $i + 1;
        while ($stop < len($chars) and $chars[$stop] != $closer) {
            $stop = $stop + 1;
        }
        if ($stop >= len($chars)) {
            # No closer on this line: it is prose after all, not a span.
            $out[] = $ch;
            $i = $i + 1;
            continue;
        }
        for (def k in $i..$stop + 1) {
            $out[] = "~";
        }
        $i = $stop + 1;
    }
    return strings.join($out, "");
}

# Whether the character at an index is one a word is made of. Out of range is
# not: the start and the end of a line are boundaries.
func wordAt(text as string, i as int) {
    if ($i < 0 or $i >= len($text)) {
        return false;
    }
    return strings.contains(WORD, strings.substring($text, $i, $i + 1));
}

/**
 * Where a term occurs in a line as a whole word, or -1.
 *
 * The search is case-insensitive and runs over the masked line, so a term inside
 * code or inside a link is not found. What is returned is an index into the line
 * itself.
 * @param line {string} the line, as written
 * @param word {string} the term to look for
 * @return {int} the index of the first whole-word occurrence, or -1
 */
export func wordIndex(line as string, word as string) {
    def hay as string init strings.lower(masked($line));
    def needle as string init strings.lower($word);
    if ($needle == "") {
        return -1;
    }
    def from as int init 0;
    while ($from <= len($hay) - len($needle)) {
        def rest as string init strings.substring($hay, $from, len($hay));
        def at as int init strings.indexOf($rest, $needle);
        if ($at < 0) {
            return -1;
        }
        def start as int init $from + $at;
        def stop as int init $start + len($needle);
        if (not wordAt($hay, $start - 1) and not wordAt($hay, $stop)) {
            return $start;
        }
        $from = $start + 1;
    }
    return -1;
}

# Path segments, empty ones dropped.
func segments(p as string) {
    def out as list of string;
    for (def part in strings.split(strings.replace($p, "\\", "/"), "/")) {
        if ($part == "" or $part == ".") {
            continue;
        }
        $out[] = $part;
    }
    return $out;
}

/**
 * The glossary chapter, as a link from another chapter.
 *
 * Both paths are given from the book's source root, and a link is written
 * relative to the chapter that holds it, so `guide/syntax.md` reaches the
 * glossary at `../glossary.md`.
 * @param src {string} the chapter the link is written in
 * @param chapter {string} the glossary chapter
 * @return {string} the path to write in the link
 */
export func linkTo(src as string, chapter as string) {
    def here as list of string init segments(path.dir($src));
    def there as list of string init segments($chapter);
    def same as int init 0;
    while ($same < len($here) and $same < len($there) - 1 and $here[$same] == $there[$same]) {
        $same = $same + 1;
    }
    def out as list of string;
    for (def i in $same..len($here)) {
        $out[] = "..";
    }
    for (def i in $same..len($there)) {
        $out[] = $there[$i];
    }
    return strings.join($out, "/");
}

# A line that prose cannot be found in: a heading (a link there would change the
# anchor Grimoire writes), or a table of contents entry the author wrote by hand.
func skippable(line as string) {
    def trimmed as string init strings.trim($line);
    return strings.startsWith($trimmed, "#");
}

/**
 * Link the first use of each term in one chapter.
 *
 * Terms are tried longest first, so "search index" is linked before "index" can
 * take its first word. Each definition is linked once: the second link to the
 * same place is never the one a reader follows.
 * @param content {string} the chapter, as Markdown
 * @param terms {list of Term} the terms to look for, longest first
 * @param target {string} the glossary chapter, as a path from this chapter
 * @return {string} the chapter, with the links in it
 */
export func link(content as string, terms as list of Term, target as string) {
    def lines as list of string init strings.split($content, "\n");
    def linked as map of string to int;
    for (def term in $terms) {
        if (maps.has($linked, $term.anchor)) {
            continue;
        }
        def fenced as bool init false;
        for (def i in 0..len($lines)) {
            def line as string init $lines[$i];
            def trimmed as string init strings.trim($line);
            if (strings.startsWith($trimmed, "```") or strings.startsWith($trimmed, "~~~")) {
                $fenced = not $fenced;
                continue;
            }
            if ($fenced or $line == "" or skippable($line)) {
                continue;
            }
            def at as int init wordIndex($line, $term.word);
            if ($at < 0) {
                continue;
            }
            def stop as int init $at + len($term.word);
            $lines[$i] = strings.substring($line, 0, $at) + "[" +
                strings.substring($line, $at, $stop) + "](" + $target + "#" + $term.anchor + ")" +
                strings.substring($line, $stop, len($line));
            $linked[$term.anchor] = 1;
            break;
        }
    }
    return strings.join($lines, "\n");
}

/**
 * Run the plugin over one request: link the first use of every term in every
 * chapter but the glossary itself.
 * @param request {string} the JSON request from stdin
 * @return {int} the exit status
 */
export func run(request as string) {
    try {
        if (strings.trim($request) == "") {
            fail("no request on stdin");
        }
        def req as json.Value init json.decode($request);
        if (json.asInt($req, "/api") != API) {
            fail("this plugin speaks api " + convert.toString(API) +
                ", the request speaks " + convert.toString(json.asInt($req, "/api")));
        }
        if (json.asString($req, "/kind") != "preprocessor") {
            fail("this is a preprocessor; the request asks for a " +
                json.asString($req, "/kind"));
        }
        io.printf("%s", replyFor($req));
        return 0;
    } catch (e) {
        io.eprintf("grimoire-glossary: %s\n", $e.message);
        return 1;
    }
}

# The chapter that holds the definitions, as the settings name it.
func chapterOf(req as json.Value) {
    if (json.has($req, "/plugin/settings/chapter")) {
        return json.asString($req, "/plugin/settings/chapter");
    }
    return "glossary.md";
}

# The reply: every chapter the terms reached, and nothing else.
func replyFor(req as json.Value) {
    def chapter as string init chapterOf($req);
    def depth as int init 2;
    if (json.has($req, "/plugin/settings/depth")) {
        $depth = json.asInt($req, "/plugin/settings/depth");
    }
    def source as string init "";
    for (def i in 0..json.length($req, "/chapters")) {
        def at as string init "/chapters/" + convert.toString($i);
        if (json.asString($req, $at + "/src") == $chapter) {
            $source = json.asString($req, $at + "/content");
        }
    }
    if ($source == "") {
        fail("no glossary chapter at " + $chapter + ": name one with `chapter`");
    }
    def defined as list of Term init termsIn($source, $depth);
    def extra as list of Term;
    if (json.has($req, "/plugin/settings/terms")) {
        $extra = aliasesIn(json.asString($req, "/plugin/settings/terms"), $defined);
    }
    def terms as list of Term init ordered($defined, $extra);
    def replies as list of string;
    for (def i in 0..json.length($req, "/chapters")) {
        def at as string init "/chapters/" + convert.toString($i);
        def src as string init json.asString($req, $at + "/src");
        if ($src == $chapter) {
            continue;
        }
        def content as string init json.asString($req, $at + "/content");
        def out as string init link($content, $terms, linkTo($src, $chapter));
        if ($out != $content) {
            $replies[] = '{"src":' + json.encode($src) + ',"content":' + json.encode($out) + '}';
        }
    }
    return '{"api":' + convert.toString(API) + ',"chapters":[' +
        strings.join($replies, ",") + ']}';
}
