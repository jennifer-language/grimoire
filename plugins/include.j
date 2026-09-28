# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * `{{#include}}`: a file pulled into a chapter.
 *
 *     {{#include examples/hello.j}}          the whole file
 *     {{#include examples/hello.j:3:12}}     lines 3 to 12, inclusive
 *     {{#include examples/hello.j:5}}        line 5 onwards
 *
 * The point is a book that quotes code it does not own a copy of. A snippet
 * pasted into a chapter is wrong the day the code changes and nobody notices
 * until a reader tries it; a file read at build time is either right or a failed
 * build.
 *
 * Paths are relative to the book's source directory. A path that climbs out of
 * it with `..` is refused: a book is a directory, and a preprocessor that reads
 * `/etc/passwd` into a page because someone wrote a chapter that says so is a
 * hole rather than a feature.
 *
 * This is also the reference implementation of the preprocessor contract, and it
 * is deliberately the plugin that needs nothing installed: read a JSON request
 * on stdin, write a JSON reply on stdout, exit 0. `src/plugin.j` documents the
 * shape.
 * @module include
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use fs;
use path;
use json;
use regex;
use strings;
use lists;
use convert;

# The contract version this speaks.
def const API as int init 1;

# `{{#include path}}`, `{{#include path:from}}`, `{{#include path:from:to}}`.
# The directive stands alone on its line: a marker inside a sentence is prose
# about the syntax, which a manual documenting this plugin is full of.
def const RANGE as string init '(?::([0-9]+))?(?::([0-9]+))?';
def const DIRECTIVE as string init '^[ \t]*\{\{#include[ \t]+([^:}]+?)' + RANGE +
    '[ \t]*\}\}[ \t]*$';

# A directive written with a backslash in front of it is left on the page without
# the backslash, which is how a book documents the syntax. The convention is
# mdBook's, and a chapter about this plugin needs it.
def const ESCAPED as string init '^([ \t]*)\\(\{\{#include.*)$';

# A refusal, rather than an exit: `run` turns it into a status and a message on
# stderr, and a test can catch it. `exit` inside a module would take the test
# runner with it.
func fail(message as string) {
    throw Error{kind: "plugin", message: $message, file: "", line: 0, col: 0};
}

/**
 * The requested range of a file, counting from 1 the way an editor does.
 *
 * An out-of-range first line is an error rather than an empty string: the book
 * meant to quote something. A last line past the end is the end, because that is
 * what `:5:` means when a file grows shorter.
 * @param file {string} the file's path, for the message when the range is wrong
 * @param text {string} the file's contents
 * @param lo {int} the first line, 1-based, or 0 for the whole file
 * @param hi {int} the last line, or 0 for the end of the file
 * @return {string} the lines, joined
 * @throws {Error} kind "plugin" when the first line is past the end of the file
 */
export func slice(file as string, text as string, lo as int, hi as int) {
    def all as list of string init strings.split($text, "\n");
    # A file ends with a newline, which splits into a trailing empty line that is
    # not a line of the file.
    if (len($all) > 0 and $all[len($all) - 1] == "") {
        $all = lists.head($all, len($all) - 1);
    }
    if ($lo == 0) {
        return strings.join($all, "\n");
    }
    if ($lo > len($all)) {
        fail($file + ": line " + convert.toString($lo) + " is past the end of the file");
    }
    def last as int init $hi;
    if ($last == 0 or $last > len($all)) {
        $last = len($all);
    }
    def out as list of string;
    def i as int init $lo - 1;
    while ($i < $last) {
        $out[] = $all[$i];
        $i = $i + 1;
    }
    return strings.join($out, "\n");
}

/**
 * A directive's path, as a file inside the book.
 * @param root {string} the book's source directory
 * @param wanted {string} the path as the directive wrote it
 * @return {string} the file to read
 * @throws {Error} kind "plugin" when it climbs out of the book, or is not there
 */
export func resolve(root as string, wanted as string) {
    def target as string init path.clean(path.join($root, strings.trim($wanted)));
    if (not strings.startsWith($target, path.clean($root) + "/")) {
        fail(strings.trim($wanted) + ": outside the book");
    }
    if (not fs.isFile($target)) {
        fail(strings.trim($wanted) + ": no such file");
    }
    return $target;
}

# An absent range reads as "not given" rather than as line zero.
func number(text as string) {
    if ($text == "") {
        return 0;
    }
    return convert.toInt($text);
}

/**
 * One chapter, with every directive replaced by what it names.
 *
 * Directives are resolved once, not recursively: a file that includes a file
 * that includes a file is a knot to untangle at three in the morning, and
 * nothing in a book needs it.
 * @param root {string} the book's source directory
 * @param content {string} the chapter, as Markdown
 * @return {string} the chapter, with the files pulled in
 * @throws {Error} kind "plugin" when a directive names something it may not read
 */
export func expand(root as string, content as string) {
    def out as list of string;
    for (def line in strings.split($content, "\n")) {
        def esc as regex.Match init regex.find(ESCAPED, $line);
        if (len($esc.groups) > 0) {
            $out[] = $esc.groups[0] + $esc.groups[1];
            continue;
        }
        def m as regex.Match init regex.find(DIRECTIVE, $line);
        if (len($m.groups) == 0) {
            $out[] = $line;
            continue;
        }
        def file as string init resolve($root, $m.groups[0]);
        $out[] = slice($file, fs.readString($file), number($m.groups[1]), number($m.groups[2]));
    }
    return strings.join($out, "\n");
}

# The reply: the chapters that carried a directive, and no others.
func replyFor(req as json.Value) {
    def root as string init json.asString($req, "/book/src");
    def replies as list of string;
    for (def i in 0..json.length($req, "/chapters")) {
        def at as string init "/chapters/" + convert.toString($i);
        def content as string init json.asString($req, $at + "/content");
        def expanded as string init expand($root, $content);
        if ($expanded != $content) {
            $replies[] = '{"src":' + json.encode(json.asString($req, $at + "/src")) +
                ',"content":' + json.encode($expanded) + '}';
        }
    }
    return '{"api":' + convert.toString(API) + ',"chapters":[' +
        strings.join($replies, ",") + ']}';
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
        if (json.asString($req, "/kind") != "preprocessor") {
            fail("this is a preprocessor; the request asks for a " +
                json.asString($req, "/kind"));
        }
        io.printf("%s", replyFor($req));
        return 0;
    } catch (e) {
        io.eprintf("grimoire-include: %s\n", $e.message);
        return 1;
    }
}
