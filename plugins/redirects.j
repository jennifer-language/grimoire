# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Meta-refresh stubs for pages that moved.
 *
 * A renderer. Every key in the plugin's own table is an old path and a new one:
 *
 *     [renderer.redirects]
 *     "guide/old-name.html" = "guide/new-name.html"
 *
 * Each becomes a small HTML file in the built site that sends a reader on. A URL
 * that was published once is a promise, and a static host has no other way to
 * keep it: there is no server to answer with a 301.
 *
 * The target is written as a path relative to the stub, so a book served from a
 * subdirectory keeps working. A target that is a full URL is used as written.
 *
 * Nothing is overwritten. A stub whose path is a real page of the book would
 * replace that page with a redirect away from itself, so it is refused and
 * reported as a warning instead.
 * @module redirects
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use fs;
use path;
use json;
use strings;
use convert;
use lists;
use maps;

import "html.j" as html;

def const API as int init 1;

# The stub says who wrote it. A build that is not `--clean` finds last build's
# stubs still in place, and a plugin that refused to overwrite anything would
# report every one of them as a collision from the second build on. This is what
# tells one of ours from a file that is somebody else's.
def const MARKER as string init '<meta name="generator" content="grimoire-redirects">';

# Keys of the plugin's table that are Grimoire's, not a redirect.
def const RESERVED as list of string init ["command", "args"];

# A refusal, rather than an exit: `run` turns it into a status and a message on
# stderr, and a test can catch it. `exit` inside a module would take the test
# runner with it.
func fail(message as string) {
    throw Error{kind: "plugin", message: $message, file: "", line: 0, col: 0};
}

/**
 * One redirect: where a reader asks, and where they are sent.
 *
 * The field is `target` rather than `to` because `to` is a keyword.
 * @field from {string} the old path, relative to the site root
 * @field target {string} the new path, relative to the site root, or a full URL
 */
export def struct Move {
    from as string,
    target as string
};

# A key as one segment of a JSON pointer. A redirect's key is a path, and a
# pointer separates its segments with the same character. RFC 6901 order: `~`
# first, then `/`.
func pointerKey(key as string) {
    return strings.replace(strings.replace($key, "~", "~0"), "/", "~1");
}

# Path segments, with the empty ones dropped, so that `a//b` and `./a/b` mean
# what they look like.
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
 * The path from one file to another, both given from the site root.
 *
 * A stub at `guide/old.html` pointing at `reference/new.html` has to say
 * `../reference/new.html`: the site may be published under a subdirectory, and a
 * root-relative link would leave it.
 * @param from {string} the file the link is written in
 * @param target {string} the file it points at
 * @return {string} the target, relative to the file the link is in
 */
export func relativeTo(from as string, target as string) {
    if (strings.contains($target, "://") or strings.startsWith($target, "/") or
        strings.startsWith($target, "#")) {
        return $target;
    }
    def here as list of string init segments(path.dir($from));
    def there as list of string init segments($target);
    def same as int init 0;
    while ($same < len($here) and $same < len($there) - 1 and
        $here[$same] == $there[$same]) {
        $same = $same + 1;
    }
    def out as list of string;
    for (def i in $same..len($here)) {
        $out[] = "..";
    }
    for (def i in $same..len($there)) {
        $out[] = $there[$i];
    }
    if (len($out) == 0) {
        return path.base($target);
    }
    return strings.join($out, "/");
}

/**
 * The stub written for one move.
 *
 * A refresh with no delay, a canonical link for anything that indexes it, and a
 * plain link in the body for a reader whose browser refuses the refresh.
 * @param move {Move} the old path and the new one
 * @param language {string} the book's language, for the `lang` attribute
 * @return {string} the HTML file
 */
export func stub(move as Move, language as string) {
    def href as string init html.escape(html.safeUrl(relativeTo($move.from, $move.target)));
    return '<!doctype html>' + "\n" +
        '<html lang="' + html.escape($language) + '">' + "\n" +
        "<head>\n" +
        '<meta charset="utf-8">' + "\n" +
        '<meta name="robots" content="noindex">' + "\n" +
        MARKER + "\n" +
        '<meta http-equiv="refresh" content="0; url=' + $href + '">' + "\n" +
        '<link rel="canonical" href="' + $href + '">' + "\n" +
        "<title>Moved</title>\n" +
        "</head>\n<body>\n" +
        '<p>This page has moved to <a href="' + $href + '">its new address</a>.</p>' + "\n" +
        "</body>\n</html>\n";
}

/**
 * The moves a request asks for, in a fixed order.
 *
 * Sorted by the old path rather than taken in the order the table was written,
 * because the reply lists what was written and a build says the same thing twice
 * only if the order is decided here.
 * @param req {json.Value} the decoded request
 * @return {list of Move} the redirects to write
 */
export func moves(req as json.Value) {
    def out as list of Move;
    if (not json.has($req, "/plugin/settings")) {
        return $out;
    }
    def names as list of string init lists.sort(json.keys($req, "/plugin/settings"));
    for (def key in $names) {
        if (lists.contains(RESERVED, $key)) {
            continue;
        }
        def at as string init "/plugin/settings/" + pointerKey($key);
        if (json.typeOf(json.get($req, $at)) != "string") {
            fail("redirect \"" + $key + "\" is not a path: a redirect is one string to another");
        }
        $out[] = Move{from: $key, target: json.asString($req, $at)};
    }
    return $out;
}

# A path that stays inside the site. A redirect is written from a table, and a
# table can say `../../etc/passwd` as easily as `old.html`.
#
# An absolute path is refused rather than quietly rebased: `path.join` reads
# `/tmp/x.html` as a path under the site and would write `site/tmp/x.html`, which
# is not the file anybody asked for. A stub is named by the URL it answers, and
# that URL is relative to the site root.
func inside(out as string, from as string) {
    if (strings.startsWith($from, "/") or strings.startsWith($from, "\\")) {
        return false;
    }
    def target as string init path.clean(path.join($out, $from));
    def root as string init path.clean($out);
    return strings.startsWith($target, $root + "/");
}

# The pages the book itself writes, by their path in the site. A stub named after
# one of them would replace a chapter with a redirect away from itself.
func pages(req as json.Value) {
    def out as map of string to int;
    for (def i in 0..json.length($req, "/entries")) {
        def at as string init "/entries/" + convert.toString($i);
        if (json.asString($req, $at + "/kind") == "page") {
            $out[json.asString($req, $at + "/out")] = 1;
        }
    }
    return $out;
}

# Whether a stub may be written here, and why not when it may not.
func refusal(out as string, from as string, written as map of string to int) {
    if (strings.trim($from) == "") {
        return "skipped an empty redirect";
    }
    if (not inside($out, $from)) {
        return $from + " is outside the site, not written";
    }
    if (maps.has($written, $from)) {
        return $from + " is a page of this book, not replaced";
    }
    def target as string init path.join($out, $from);
    if (fs.isFile($target) and not strings.contains(fs.readString($target), MARKER)) {
        return $from + " already exists and is not a redirect, not replaced";
    }
    return "";
}

/**
 * Write the stubs for one request.
 *
 * Returns what it wrote and what it refused, which is the reply the build
 * reports: the files under `written`, the refusals under `warnings`.
 * @param req {json.Value} the decoded request
 * @return {list of string} the reply, as two lists: written, then warnings
 * @throws {Error} kind "plugin" when a redirect is not a pair of paths
 */
export func write(req as json.Value) {
    def out as string init json.asString($req, "/book/out");
    def language as string init json.asString($req, "/book/language");
    def written as list of string;
    def warnings as list of string;
    def chapters as map of string to int init pages($req);
    for (def move in moves($req)) {
        if (strings.trim($move.target) == "") {
            $warnings[] = "skipped an empty redirect";
            continue;
        }
        def no as string init refusal($out, $move.from, $chapters);
        if ($no != "") {
            $warnings[] = $no;
            continue;
        }
        def target as string init path.join($out, $move.from);
        def dir as string init path.dir($target);
        if ($dir != "" and $dir != ".") {
            fs.mkdirAll($dir);
        }
        fs.writeString($target, stub($move, $language));
        $written[] = $move.from;
    }
    return [strings.join($written, "\n"), strings.join($warnings, "\n")];
}

# The reply, as the contract spells it: two optional lists of strings.
func reply(written as string, warnings as string) {
    def parts as list of string init ['"api":' + convert.toString(API)];
    if ($written != "") {
        def items as list of string;
        for (def w in strings.split($written, "\n")) {
            $items[] = json.encode($w);
        }
        $parts[] = '"written":[' + strings.join($items, ",") + ']';
    }
    if ($warnings != "") {
        def items as list of string;
        for (def w in strings.split($warnings, "\n")) {
            $items[] = json.encode($w);
        }
        $parts[] = '"warnings":[' + strings.join($items, ",") + ']';
    }
    return '{' + strings.join($parts, ",") + '}';
}

/**
 * Run the plugin over one request.
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
        if (json.asString($req, "/kind") != "renderer") {
            fail("this is a renderer; the request asks for a " +
                json.asString($req, "/kind"));
        }
        def result as list of string init write($req);
        io.printf("%s", reply($result[0], $result[1]));
        return 0;
    } catch (e) {
        io.eprintf("grimoire-redirects: %s\n", $e.message);
        return 1;
    }
}
