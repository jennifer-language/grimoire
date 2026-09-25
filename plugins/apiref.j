# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Reference chapters written from Jennifer docblocks.
 *
 * A preprocessor. Where a chapter says
 *
 *     {{#apiref src}}
 *
 * the directive is replaced by the documentation of every `.j` file under that
 * path: the module summary, then each exported struct, function and constant,
 * with the types and descriptions its docblocks carry. A file or a directory
 * both work, and a directory is walked in sorted order so two builds agree.
 *
 * The parsing is `docblock.parse`, which is the blessed reader for the format,
 * so what appears here is what the source says rather than what a second parser
 * guessed. This program only decides what that data looks like as Markdown.
 *
 * Reference pages that are generated are the ones that stay true, and a chapter
 * that holds a directive is still a chapter: it keeps its title, its prose, and
 * its place in `SUMMARY.md`. The outline stays the author's.
 *
 * Paths are relative to where the build runs, not to the book, because source
 * code usually sits beside a book rather than inside it - `{{#apiref src}}` from
 * a project whose book is `docs/`.
 * @module apiref
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
use regex;

import "docblock.j" as docblock;

def const API as int init 1;

# `{{#apiref path}}`, alone on its line. A marker inside a sentence is prose
# about the syntax, which the chapter documenting this plugin is full of.
def const DIRECTIVE as string init '^[ \t]*\{\{#apiref[ \t]+([^}]+?)[ \t]*\}\}[ \t]*$';

# A directive with a backslash in front of it prints itself, which is how a book
# documents the syntax.
def const ESCAPED as string init '^([ \t]*)\\(\{\{#apiref.*)$';

# A refusal, rather than an exit: `run` turns it into a status and a message on
# stderr, and a test can catch it. `exit` inside a module would take the test
# runner with it.
func fail(message as string) {
    throw Error{kind: "plugin", message: $message, file: "", line: 0, col: 0};
}

func hashes(level as int) {
    return strings.repeat("#", $level);
}

# A heading level is clamped rather than allowed to run past six, where Markdown
# stops having headings.
func clamped(level as int) {
    if ($level < 2) {
        return 2;
    }
    if ($level > 6) {
        return 6;
    }
    return $level;
}

# Prose from a docblock is already Markdown - the format is written for people
# to read in the source - so it passes through. Blank summaries are dropped
# rather than printed as empty paragraphs.
func prose(summary as string, description as string) {
    def out as list of string;
    if (strings.trim($summary) != "") {
        $out[] = strings.trim($summary);
    }
    if (strings.trim($description) != "") {
        $out[] = strings.trim($description);
    }
    return $out;
}

# A table of named things - a function's parameters or a struct's fields.
#
# One string rather than a list of them, because every piece this program
# produces is a *block* and blocks are joined with a blank line between. A table
# whose rows were blocks would be six paragraphs that happen to contain pipes.
func table(items as list of docblock.ParamDoc, heading as string) {
    if (len($items) == 0) {
        return "";
    }
    def out as list of string;
    $out[] = "| " + $heading + " | Type | |";
    $out[] = "| --- | --- | --- |";
    for (def item in $items) {
        def kind as string init "";
        if ($item.type != "") {
            $kind = "`" + $item.type + "`";
        }
        $out[] = "| `" + $item.name + "` | " + $kind + " | " + $item.description + " |";
    }
    return strings.join($out, "\n");
}

# The signature, rebuilt from what the docblock names. It is the parameter list
# a caller writes, which is what a reference page is read for.
func signature(f as docblock.FuncDoc) {
    def parts as list of string;
    for (def p in $f.params) {
        if ($p.type == "") {
            $parts[] = $p.name;
        } else {
            $parts[] = $p.name + " as " + $p.type;
        }
    }
    return $f.name + "(" + strings.join($parts, ", ") + ")";
}

# --- rendering one file ----------------------------------------------

# The heading is the bare name, so the anchor a reader links to is `#distance`
# rather than the whole signature slugified. The signature goes underneath, in a
# fenced block, where Grimoire's own highlighter colours it.
func funcSection(f as docblock.FuncDoc, level as int) {
    def out as list of string;
    $out[] = hashes($level) + " `" + $f.name + "`";
    $out[] = "```jennifer\n" + signature($f) + "\n```";
    for (def p in prose($f.summary, $f.description)) {
        $out[] = $p;
    }
    def params as string init table($f.params, "Parameter");
    if ($params != "") {
        $out[] = $params;
    }
    if ($f.returns.type != "") {
        $out[] = "**Returns** `" + $f.returns.type + "` " + $f.returns.description;
    }
    for (def t in $f.throws) {
        $out[] = "**Throws** `" + $t.type + "` " + $t.description;
    }
    if ($f.deprecated != "") {
        $out[] = "**Deprecated.** " + $f.deprecated;
    }
    return $out;
}

func structSection(s as docblock.StructDoc, level as int) {
    def out as list of string;
    $out[] = hashes($level) + " `" + $s.name + "`";
    for (def p in prose($s.summary, $s.description)) {
        $out[] = $p;
    }
    def fields as string init table($s.fields, "Field");
    if ($fields != "") {
        $out[] = $fields;
    }
    if ($s.deprecated != "") {
        $out[] = "**Deprecated.** " + $s.deprecated;
    }
    return $out;
}

func constSection(c as docblock.ConstDoc, level as int) {
    def out as list of string;
    def kind as string init "";
    if ($c.type != "") {
        $kind = " `" + $c.type + "`";
    }
    $out[] = hashes($level) + " `" + $c.name + "`" + $kind;
    for (def p in prose($c.summary, $c.description)) {
        $out[] = $p;
    }
    return $out;
}

# One file: its module preamble, then what it exports, in the order the source
# declares it. `private` brings in what it does not export, for a book
# documenting a tree it also maintains.
func fileSection(file as string, level as int, private as bool) {
    def doc as docblock.FileDoc init docblock.parse(fs.readString($file));
    def out as list of string;
    def name as string init path.base($file);
    if (strings.endsWith($name, ".j")) {
        $name = strings.substring($name, 0, len($name) - 2);
    }
    $out[] = hashes($level) + " `" + $name + "`";
    for (def p in prose($doc.module.summary, $doc.module.description)) {
        $out[] = $p;
    }
    for (def s in $doc.structs) {
        if ($s.exported or $private) {
            for (def line in structSection($s, clamped($level + 1))) {
                $out[] = $line;
            }
        }
    }
    for (def f in $doc.funcs) {
        if ($f.exported or $private) {
            for (def line in funcSection($f, clamped($level + 1))) {
                $out[] = $line;
            }
        }
    }
    for (def c in $doc.consts) {
        if ($c.exported or $private) {
            for (def line in constSection($c, clamped($level + 1))) {
                $out[] = $line;
            }
        }
    }
    return $out;
}

# Every `.j` file under a path, sorted, so the chapter reads the same on every
# build. A single file is a path too.
func sourcesUnder(root as string) {
    if (fs.isFile($root)) {
        return [$root];
    }
    if (not fs.isDir($root)) {
        fail($root + ": no such file or directory");
    }
    def out as list of string;
    for (def st in fs.walk($root)) {
        if ($st.isDir or not strings.endsWith($st.path, ".j")) {
            continue;
        }
        # A test overlay documents the tests, not the module.
        if (strings.endsWith($st.path, "_test.j")) {
            continue;
        }
        $out[] = $st.path;
    }
    if (len($out) == 0) {
        fail($root + ": no Jennifer sources here");
    }
    return lists.sort($out);
}

func reference(root as string, level as int, private as bool) {
    def out as list of string;
    for (def file in sourcesUnder($root)) {
        for (def line in fileSection($file, $level, $private)) {
            $out[] = $line;
        }
    }
    return strings.join($out, "\n\n");
}

# --- expanding a chapter ---------------------------------------------

/**
 * One chapter with its `{{#apiref}}` directives expanded.
 *
 * A directive stands alone on its line; one inside a sentence is prose about
 * the syntax. A line that carries a backslash in front of a directive prints
 * the directive instead of following it, which is how a book documents it.
 * @param content {string} the chapter's Markdown
 * @param level {int} the heading level a module gets
 * @param private {bool} whether to document what a module does not export
 * @return {string} the chapter, expanded
 * @throws {Error} kind "plugin" when a directive names a path with no sources
 */
export func expand(content as string, level as int, private as bool) {
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
        $out[] = reference(strings.trim($m.groups[0]), $level, $private);
    }
    return strings.join($out, "\n");
}

/**
 * Run the plugin over one request: expand every chapter that carries a
 * directive, and reply with those.
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
        def level as int init 2;
        if (json.has($req, "/plugin/settings/depth")) {
            $level = clamped(json.asInt($req, "/plugin/settings/depth"));
        }
        def private as bool init false;
        if (json.has($req, "/plugin/settings/private")) {
            $private = json.asBool($req, "/plugin/settings/private");
        }
        def replies as list of string;
        for (def i in 0..json.length($req, "/chapters")) {
            def at as string init "/chapters/" + convert.toString($i);
            def content as string init json.asString($req, $at + "/content");
            def expanded as string init expand($content, $level, $private);
            if ($expanded != $content) {
                $replies[] = '{"src":' + json.encode(json.asString($req, $at + "/src")) +
                    ',"content":' + json.encode($expanded) + '}';
            }
        }
        io.printf('{"api":%d,"chapters":[%s]}', API, strings.join($replies, ","));
        return 0;
    } catch (e) {
        io.eprintf("grimoire-apiref: %s\n", $e.message);
        return 1;
    }
}
