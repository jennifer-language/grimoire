# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Values a book writes once and uses everywhere.
 *
 * A preprocessor. `{{ version }}` in a chapter becomes what `grimoire.toml`
 * says it is, and a release that changes the number changes it in one place
 * rather than in every page that mentions it. A version written by hand is
 * wrong the day after it is written, and nobody notices until a reader copies
 * it.
 *
 * Three sources, in the order a name is looked up: the book itself
 * (`{{ book.title }}`), the values the table declares, and the environment
 * variables the book allows. The last is how a pipeline injects a number it
 * knows and the repository does not.
 *
 * A name with nothing behind it stops the build and says which chapter asked
 * for it. That is the point of the plugin: a placeholder that reaches a reader
 * is worse than a build that stopped.
 * @module macros
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use os;
use json;
use strings;
use convert;
use maps;
use regex;

def const API as int init 1;

# `{{ name }}`, with the spaces optional. A name is a word, or words joined by
# dots: `version`, `book.title`, `env.CI_COMMIT_TAG`.
def const MACRO as string init '\{\{[ \t]*([A-Za-z][A-Za-z0-9_.]*)[ \t]*\}\}';

# A refusal, rather than an exit: `run` turns it into a status and a message on
# stderr, and a test can catch it. `exit` inside a module would take the test
# runner with it.
func fail(message as string) {
    throw Error{kind: "plugin", message: $message, file: "", line: 0, col: 0};
}

# One value from the settings table, as text. A number in a manifest is a number
# and reaches a page as one; anything with a shape - a list, a table - is a
# configuration mistake worth naming rather than printing as JSON.
func textOf(req as json.Value, at as string, name as string) {
    match (json.typeOf(json.get($req, $at))) {
        when "string" { return json.asString($req, $at); }
        when "int" { return convert.toString(json.asInt($req, $at)); }
        when "float" { return convert.toString(json.asFloat($req, $at)); }
        when "bool" { if (json.asBool($req, $at)) {
            return "true";
        }
        return "false"; }
        else { fail("the value of \"" + $name + "\" is not a word or a number"); }
    }
    return "";
}

# A key as one segment of a pointer: a macro name may hold a dot, and a pointer
# separates its segments with a slash, so only `~` and `/` need escaping here.
func pointerKey(key as string) {
    return strings.replace(strings.replace($key, "~", "~0"), "/", "~1");
}

/**
 * Every name a chapter may use, and what it stands for.
 *
 * The book's own metadata is always there; `vars` is what the table declares;
 * `env` names the environment variables the book is willing to read, because a
 * build that can print any variable it likes is one careless page away from
 * publishing a token.
 * @param req {json.Value} the decoded request
 * @return {map of string to string} the names and their values
 * @throws {Error} kind "plugin" when a value has no printable shape, or a named
 *   environment variable is not set
 */
export func valuesOf(req as json.Value) {
    def out as map of string to string;
    $out["book.title"] = json.asString($req, "/book/title");
    $out["book.description"] = json.asString($req, "/book/description");
    $out["book.language"] = json.asString($req, "/book/language");
    def authors as list of string;
    for (def i in 0..json.length($req, "/book/authors")) {
        $authors[] = json.asString($req, "/book/authors/" + convert.toString($i));
    }
    $out["book.authors"] = strings.join($authors, ", ");
    if (json.has($req, "/plugin/settings/vars")) {
        for (def name in json.keys($req, "/plugin/settings/vars")) {
            $out[$name] = textOf($req, "/plugin/settings/vars/" + pointerKey($name), $name);
        }
    }
    if (json.has($req, "/plugin/settings/env")) {
        for (def i in 0..json.length($req, "/plugin/settings/env")) {
            def name as string init json.asString(
                $req,
                "/plugin/settings/env/" + convert.toString($i));
            def value as string init os.getEnv($name);
            if ($value == "") {
                fail("the environment variable " + $name + " is named in `env` but not set");
            }
            $out["env." + $name] = $value;
        }
    }
    return $out;
}

# The fence a line opens or closes, or "".
func fenceOf(line as string) {
    def trimmed as string init strings.trim($line);
    for (def mark in ["```", "~~~"]) {
        if (not strings.startsWith($trimmed, $mark)) {
            continue;
        }
        def run as int init 0;
        for (def ch in strings.chars($trimmed)) {
            if ($ch != strings.substring($mark, 0, 1)) {
                break;
            }
            $run = $run + 1;
        }
        return strings.substring($trimmed, 0, $run);
    }
    return "";
}

# One line, with every macro on it expanded. A backslash in front of one prints
# it instead, which is how a page documents the syntax.
func expandLine(
    line as string,
    values as map of string to string,
    strict as bool,
    where as string) {
    def out as string init "";
    def at as int init 0;
    for (def m in regex.findAll(MACRO, $line)) {
        if ($m.start > 0 and strings.substring($line, $m.start - 1, $m.start) == "\\") {
            $out = $out + strings.substring($line, $at, $m.start - 1) + $m.text;
            $at = $m.end;
            continue;
        }
        def name as string init $m.groups[0];
        if (not maps.has($values, $name)) {
            if ($strict) {
                fail($where + ": nothing is set for " + $m.text);
            }
            continue;
        }
        $out = $out + strings.substring($line, $at, $m.start) + $values[$name];
        $at = $m.end;
    }
    return $out + strings.substring($line, $at, len($line));
}

/**
 * One chapter, with its macros expanded.
 *
 * Fenced code is left alone: a page showing what a macro looks like is a page
 * about macros, and expanding the example would make it a lie.
 * @param content {string} the chapter, as Markdown
 * @param values {map of string to string} the names and their values
 * @param strict {bool} whether an unknown name stops the build
 * @param where {string} the chapter's path, for the message when it does
 * @return {string} the chapter, expanded
 * @throws {Error} kind "plugin" when `strict` and a name has nothing behind it
 */
export func expand(
    content as string,
    values as map of string to string,
    strict as bool,
    where as string) {
    def out as list of string;
    def fence as string init "";
    for (def line in strings.split($content, "\n")) {
        def mark as string init fenceOf($line);
        if ($fence == "" and $mark != "") {
            $fence = $mark;
            $out[] = $line;
            continue;
        }
        if ($fence != "") {
            if ($mark == $fence) {
                $fence = "";
            }
            $out[] = $line;
            continue;
        }
        $out[] = expandLine($line, $values, $strict, $where);
    }
    return strings.join($out, "\n");
}

# The reply: the chapters that carried a macro, and no others.
func replyFor(req as json.Value) {
    def values as map of string to string init valuesOf($req);
    def strict as bool init true;
    if (json.has($req, "/plugin/settings/strict")) {
        $strict = json.asBool($req, "/plugin/settings/strict");
    }
    def replies as list of string;
    for (def i in 0..json.length($req, "/chapters")) {
        def at as string init "/chapters/" + convert.toString($i);
        def src as string init json.asString($req, $at + "/src");
        def content as string init json.asString($req, $at + "/content");
        def out as string init expand($content, $values, $strict, $src);
        if ($out != $content) {
            $replies[] = '{"src":' + json.encode($src) + ',"content":' + json.encode($out) + '}';
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
        io.eprintf("grimoire-macros: %s\n", $e.message);
        return 1;
    }
}
