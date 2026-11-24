# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.28.0

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
import "../src/pluginkit.j" as kit;

# `{{ name }}`, with the spaces optional. A name is a word, or words joined by
# dots: `version`, `book.title`, `env.CI_COMMIT_TAG`.
def const MACRO as string init '\{\{[ \t]*([A-Za-z][A-Za-z0-9_.]*)[ \t]*\}\}';

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
        else { kit.fail("the value of \"" + $name + "\" is not a word or a number"); }
    }
    return "";
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
    if (kit.hasSetting($req, "vars")) {
        for (def name in json.keys($req, "/plugin/settings/vars")) {
            $out[$name] = textOf($req, "/plugin/settings/vars/" + kit.pointerKey($name), $name);
        }
    }
    for (def name in kit.settingTexts($req, "env", [])) {
        def value as string init os.getEnv($name);
        if ($value == "") {
            kit.fail("the environment variable " + $name + " is named in `env` but not set");
        }
        $out["env." + $name] = $value;
    }
    return $out;
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
        if ($m.start > 0 and $line[$m.start - 1..$m.start] == "\\") {
            $out = $out + $line[$at..$m.start - 1] + $m.text;
            $at = $m.end;
            continue;
        }
        def name as string init $m.groups[0];
        if (not maps.has($values, $name)) {
            if ($strict) {
                kit.fail($where + ": nothing is set for " + $m.text);
            }
            continue;
        }
        $out = $out + $line[$at..$m.start] + $values[$name];
        $at = $m.end;
    }
    return $out + $line[$at..len($line)];
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
    def lines as list of string init strings.split($content, "\n");
    def fenced as list of bool init kit.fencedLines($content);
    for (def i in 0..len($lines)) {
        def line as string init $lines[$i];
        if ($fenced[$i]) {
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
    def strict as bool init kit.settingBool($req, "strict", true);
    def replies as list of string;
    for (def i in 0..json.length($req, "/chapters")) {
        def at as string init "/chapters/" + convert.toString($i);
        def src as string init json.asString($req, $at + "/src");
        def content as string init json.asString($req, $at + "/content");
        def out as string init expand($content, $values, $strict, $src);
        if ($out != $content) {
            $replies[] = kit.chapterReply($src, $out);
        }
    }
    return kit.preprocessorReply($replies);
}

/**
 * Run the plugin over one request.
 * @param request {string} the JSON request from stdin
 * @return {int} the exit status
 */
export func run(request as string) {
    try {
        def req as json.Value init kit.request($request, "preprocessor");
        io.printf("%s", replyFor($req));
        return 0;
    } catch (e) {
        return kit.report("grimoire-macros", $e.message);
    }
}
