# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * The plugin kit: what a Grimoire plugin written in Jennifer needs from the
 * contract, written once.
 *
 * The plugins that ship with Grimoire import it as `../src/pluginkit.j`. A
 * plugin published on its own carries a copy of this one file in its `src/`,
 * taken from the Grimoire release it needs (0.5.0 or later), and imports it as
 * `./pluginkit.j`. Depending on the whole `@jennifer/grimoire` deck instead would
 * vendor all of Grimoire into every plugin; a deck holding only the kit is
 * planned.
 *
 * So the file has to work alone: it imports nothing but the standard library
 * and no other module of Grimoire.
 *
 * What it covers: reading a request and checking its api and kind, the
 * features (`files`, `mathml`), building replies, settings, errors, CommonMark fences,
 * links into `_generated`, content-hash names, running another program, and
 * bounded concurrent work that reports its first failure in book order.
 * @module pluginkit
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use os;
use fs;
use path;
use json;
use strings;
use lists;
use maps;
use convert;
use regex;
use hash;
use encoding;
use task;

# The contract version: what a request carries and a reply has to claim.
def const API as int init 1;

# What a request offers on top of api 1, and the Grimoire that first offered
# each. A list rather than a version bump, because each only adds fields.
#
# - `files`: a preprocessor's own directory for generated files.
# - `mathml`: a `<math>` element in a chapter reaches every edition: the site
#   and the EPUB carry it, the printable book prints its TeX annotation, and the
#   search index leaves it out.
def const FEATURES as list of string init ["files", "mathml"];
def const FILES_SINCE as string init "0.5.0";
def const SINCE as map of string to string init {"files": "0.5.0", "mathml": "0.5.0"};

# The directory under `book.src` that generated files are treated as lying in.
def const GENERATED as string init "_generated";

# Keys of a plugin's table that are Grimoire's own: the program and its
# arguments. They reach the plugin in `plugin.settings` with everything else.
def const RESERVED as list of string init ["command", "args"];

# --- the contract -----------------------------------------------------

/**
 * The contract version this kit speaks: `1`.
 * @return {int} the api number
 */
export func api() {
    return API;
}

/**
 * The features the Grimoire this kit ships with offers.
 * @return {list of string} the feature names
 */
export func features() {
    return FEATURES;
}

/**
 * The Grimoire version that first offered the `files` feature.
 * @return {string} a version number
 */
export func filesSince() {
    return FILES_SINCE;
}

# The request as JSON. Text that is not JSON at all is the same failure as any
# other bad request, so it carries this module's kind; a cap the decoder hit
# stays "limit".
func decodeRequest(text as string) {
    try {
        return json.decode($text);
    } catch (e) {
        if ($e.kind == "limit") {
            throw $e;
        }
        fail("the request is not JSON: " + $e.message);
    }
}

/**
 * Read a request and check that it is one this plugin can answer: something
 * on stdin, api 1, and the kind of plugin it is.
 * @param text {string} the request as read from stdin
 * @param kind {string} "preprocessor" or "renderer": what this plugin is
 * @return {json.Value} the decoded request
 * @throws {Error} kind "plugin" for an empty request, one that is not a JSON
 *   object or lacks `api` / `kind`, another api or the other kind
 */
export func request(text as string, kind as string) {
    if (strings.trim($text) == "") {
        fail("no request on stdin");
    }
    def req as json.Value init decodeRequest($text);
    if (json.typeOf($req) != "map") {
        fail("the request is not a JSON object");
    }
    if (json.typeOf($req, "/api") != "int") {
        fail("the request has no api number");
    }
    if (json.typeOf($req, "/kind") != "string") {
        fail("the request has no kind");
    }
    if (json.asInt($req, "/api") != API) {
        fail("this plugin speaks api " + convert.toString(API) +
            ", the request speaks " + convert.toString(json.asInt($req, "/api")));
    }
    if (json.asString($req, "/kind") != $kind) {
        fail("this is a " + $kind + "; the request asks for a " + json.asString($req, "/kind"));
    }
    return $req;
}

/**
 * Report a failure the way a plugin does: `NAME: message` on stderr, status 1.
 * A launcher's module ends its `run` with this in its `catch`.
 * @param name {string} the program's name, `grimoire-NAME`
 * @param message {string} what went wrong
 * @return {int} 1, the status to exit with
 */
export func report(name as string, message as string) {
    io.eprintf("%s: %s\n", $name, $message);
    return 1;
}

/**
 * Whether a request offers a feature.
 * @param req {json.Value} the decoded request
 * @param name {string} the feature, such as "files"
 * @return {bool} true when `features` lists it
 */
export func hasFeature(req as json.Value, name as string) {
    if (json.typeOf($req, "/features") != "list") {
        return false;
    }
    for (def i in 0..json.length($req, "/features")) {
        def at as string init "/features/" + convert.toString($i);
        if (json.typeOf($req, $at) == "string" and json.asString($req, $at) == $name) {
            return true;
        }
    }
    return false;
}

/**
 * Refuse a Grimoire that does not offer a feature, naming the version that
 * first did.
 * @param req {json.Value} the decoded request
 * @param name {string} the feature, such as "mathml"
 * @throws {Error} kind "plugin" when the request does not offer it
 */
export func requireFeature(req as json.Value, name as string) {
    if (hasFeature($req, $name)) {
        return;
    }
    def since as string init "a later version";
    if (maps.has(SINCE, $name)) {
        $since = SINCE[$name] + " or later";
    }
    fail("this plugin needs Grimoire " + $since + ", whose requests offer the `" + $name +
        "` feature; this one does not");
}

/**
 * The directory a preprocessor writes generated files into, refusing a
 * Grimoire that has none to offer.
 * @param req {json.Value} the decoded request
 * @return {string} `plugin.files`, an absolute directory that exists
 * @throws {Error} kind "plugin" naming the Grimoire version needed, when the
 *   request does not offer `files`
 */
export func requireFiles(req as json.Value) {
    requireFeature($req, "files");
    if (json.typeOf($req, "/plugin/files") != "string" or
        not fs.isDir(json.asString($req, "/plugin/files"))) {
        fail("the request offers `files` but plugin.files is not a directory");
    }
    return json.asString($req, "/plugin/files");
}

# --- replies ----------------------------------------------------------

/**
 * One chapter of a preprocessor's reply.
 * @param src {string} the chapter's `src`
 * @param content {string} its new Markdown
 * @return {string} the chapter as a JSON object
 */
export func chapterReply(src as string, content as string) {
    return '{"src":' + json.encode($src) + ',"content":' + json.encode($content) + '}';
}

/**
 * A preprocessor's reply: the chapters it changed, and no others.
 * @param chapters {list of string} what `chapterReply` built, in book order
 * @return {string} the reply
 */
export func preprocessorReply(chapters as list of string) {
    return '{"api":' + convert.toString(API) + ',"chapters":[' + strings.join($chapters, ",") +
        ']}';
}

# A list of strings as a JSON array.
func encodedList(items as list of string) {
    def out as list of string;
    for (def item in $items) {
        $out[] = json.encode($item);
    }
    return '[' + strings.join($out, ",") + ']';
}

/**
 * A renderer's reply: what it wrote and what it wants said. An empty list is
 * left out, as the contract allows.
 * @param written {list of string} paths it wrote, under `book.out`
 * @param warnings {list of string} warnings for the build to print
 * @return {string} the reply
 */
export func rendererReply(written as list of string, warnings as list of string) {
    def out as string init '{"api":' + convert.toString(API);
    if (len($written) > 0) {
        $out = $out + ',"written":' + encodedList($written);
    }
    if (len($warnings) > 0) {
        $out = $out + ',"warnings":' + encodedList($warnings);
    }
    return $out + '}';
}

# --- errors -----------------------------------------------------------

/**
 * Refuse, with kind "plugin". A plugin's module throws rather than exits, so a
 * test can catch it; its `run` turns the throw into a status.
 * @param message {string} what is wrong
 * @throws {Error} kind "plugin"
 */
export func fail(message as string) {
    throw Error{kind: "plugin", message: $message, file: "", line: 0, col: 0};
}

/**
 * Refuse with a place in the book. The message starts `chapter:line: `,
 * because the message is what reaches the reader; `file` and `line` carry the
 * same for a caller that catches it.
 * @param kind {string} "plugin", or "limit" for a reached cap
 * @param chapter {string} the chapter's `src`
 * @param line {int} the line, from 1
 * @param message {string} what is wrong there
 * @throws {Error} of the kind given
 */
export func failAt(kind as string, chapter as string, line as int, message as string) {
    throw Error{
        kind: $kind,
        message: $chapter + ":" + convert.toString($line) + ": " + $message,
        file: $chapter,
        line: $line,
        col: 0
    };
}

/**
 * Refuse because a cap was reached: kind "limit", the generic kind every
 * library uses for a size, count or depth cap.
 * @param message {string} which cap, and its value
 * @throws {Error} kind "limit"
 */
export func limit(message as string) {
    throw Error{kind: "limit", message: $message, file: "", line: 0, col: 0};
}

# --- settings ---------------------------------------------------------

/**
 * Grimoire's own keys in a plugin's table, `command` and `args`.
 * @return {list of string} the reserved keys
 */
export func reservedKeys() {
    return RESERVED;
}

/**
 * A key as one segment of a JSON pointer (RFC 6901): `~` and `/` escaped.
 * @param key {string} a settings key, which may hold either
 * @return {string} the segment
 */
export func pointerKey(key as string) {
    return strings.replace(strings.replace($key, "~", "~0"), "/", "~1");
}

# The pointer to one setting.
func settingAt(key as string) {
    return "/plugin/settings/" + pointerKey($key);
}

func wrongType(key as string, want as string, req as json.Value) {
    fail("setting `" + $key + "` must be " + $want + ", not " +
        json.typeOf($req, settingAt($key)));
}

/**
 * Whether the table sets a key.
 * @param req {json.Value} the decoded request
 * @param key {string} the key
 * @return {bool} true when it is there
 */
export func hasSetting(req as json.Value, key as string) {
    return json.has($req, settingAt($key));
}

/**
 * The keys the table sets, in its order, without Grimoire's own.
 * @param req {json.Value} the decoded request
 * @return {list of string} the plugin's keys
 */
export func settingKeys(req as json.Value) {
    def out as list of string;
    if (json.typeOf($req, "/plugin/settings") != "map") {
        return $out;
    }
    for (def key in json.keys($req, "/plugin/settings")) {
        if (not lists.contains(RESERVED, $key)) {
            $out[] = $key;
        }
    }
    return $out;
}

/**
 * Refuse a key the plugin does not know. Grimoire's `command` and `args` are
 * always allowed.
 * @param req {json.Value} the decoded request
 * @param known {list of string} the plugin's own keys
 * @throws {Error} kind "plugin" naming the key and the ones there are
 */
export func checkSettings(req as json.Value, known as list of string) {
    if (json.typeOf($req, "/plugin/settings") == "missing") {
        return;
    }
    if (json.typeOf($req, "/plugin/settings") != "map") {
        fail("plugin.settings is not an object");
    }
    for (def key in settingKeys($req)) {
        if (not lists.contains($known, $key)) {
            fail("unknown setting `" + $key + "`; the settings are " + strings.join($known, ", "));
        }
    }
}

/**
 * A string setting.
 * @param req {json.Value} the decoded request
 * @param key {string} the key
 * @param fallback {string} the value when it is not set
 * @return {string} the value
 * @throws {Error} kind "plugin" when it is set to something else
 */
export func settingText(req as json.Value, key as string, fallback as string) {
    if (not hasSetting($req, $key)) {
        return $fallback;
    }
    if (json.typeOf($req, settingAt($key)) != "string") {
        wrongType($key, "a string", $req);
    }
    return json.asString($req, settingAt($key));
}

/**
 * A true-or-false setting.
 * @param req {json.Value} the decoded request
 * @param key {string} the key
 * @param fallback {bool} the value when it is not set
 * @return {bool} the value
 * @throws {Error} kind "plugin" when it is set to something else
 */
export func settingBool(req as json.Value, key as string, fallback as bool) {
    if (not hasSetting($req, $key)) {
        return $fallback;
    }
    if (json.typeOf($req, settingAt($key)) != "bool") {
        wrongType($key, "true or false", $req);
    }
    return json.asBool($req, settingAt($key));
}

/**
 * A whole-number setting.
 * @param req {json.Value} the decoded request
 * @param key {string} the key
 * @param fallback {int} the value when it is not set
 * @return {int} the value
 * @throws {Error} kind "plugin" when it is set to something else
 */
export func settingInt(req as json.Value, key as string, fallback as int) {
    if (not hasSetting($req, $key)) {
        return $fallback;
    }
    if (json.typeOf($req, settingAt($key)) != "int") {
        wrongType($key, "a whole number", $req);
    }
    return json.asInt($req, settingAt($key));
}

/**
 * A number setting, written with or without a fraction.
 * @param req {json.Value} the decoded request
 * @param key {string} the key
 * @param fallback {float} the value when it is not set
 * @return {float} the value
 * @throws {Error} kind "plugin" when it is set to something else
 */
export func settingNumber(req as json.Value, key as string, fallback as float) {
    if (not hasSetting($req, $key)) {
        return $fallback;
    }
    def t as string init json.typeOf($req, settingAt($key));
    if ($t == "int") {
        return convert.toFloat(json.asInt($req, settingAt($key)));
    }
    if ($t != "float") {
        wrongType($key, "a number", $req);
    }
    return json.asFloat($req, settingAt($key));
}

/**
 * A list-of-strings setting.
 * @param req {json.Value} the decoded request
 * @param key {string} the key
 * @param fallback {list of string} the value when it is not set
 * @return {list of string} the value
 * @throws {Error} kind "plugin" when it is set to something else
 */
export func settingTexts(req as json.Value, key as string, fallback as list of string) {
    if (not hasSetting($req, $key)) {
        return $fallback;
    }
    if (json.typeOf($req, settingAt($key)) != "list") {
        wrongType($key, "a list of strings", $req);
    }
    def out as list of string;
    for (def i in 0..json.length($req, settingAt($key))) {
        def at as string init settingAt($key) + "/" + convert.toString($i);
        if (json.typeOf($req, $at) != "string") {
            wrongType($key, "a list of strings", $req);
        }
        $out[] = json.asString($req, $at);
    }
    return $out;
}

# --- fences -----------------------------------------------------------

/**
 * One fenced code block, as CommonMark reads it.
 *
 * Lines are counted from 0 as `strings.split(content, "\n")` gives them; a line
 * number for a reader is `first + 1`.
 * @field first {int} the opening fence's line
 * @field last {int} the closing fence's line, or the chapter's last line when
 *   the fence is never closed
 * @field closed {bool} whether a closing fence was found
 * @field mark {string} "`" or "~"
 * @field size {int} how many of them open it
 * @field width {int} the opener's indentation, in columns
 * @field indent {string} the opener's indentation, as written
 * @field info {string} the info string, trimmed
 * @field body {string} the content, the opener's indentation taken off each
 *   line, each line ending in a newline; "" for an empty fence
 */
export def struct Fence {
    first as int,
    last as int,
    closed as bool,
    mark as string,
    size as int,
    width as int,
    indent as string,
    info as string,
    body as string
};

# An indentation: how many columns, tabs to the next multiple of four, and how
# many characters it spans.
def struct Leading {
    width as int,
    chars as int
};

/**
 * A line without the carriage return a CRLF file leaves on it.
 * @param line {string} one line
 * @return {string} the line
 */
export func chomp(line as string) {
    if (strings.endsWith($line, "\r")) {
        return strings.substring($line, 0, len($line) - 1);
    }
    return $line;
}

# Only the first four characters can matter: four spaces or tabs already put a
# line past the three columns a fence may be indented, and every caller stops
# there. Splitting the whole line into characters was the scanner's main cost.
func leading(line as string) {
    def width as int init 0;
    def n as int init 0;
    def head as string init $line;
    if (len($head) > 4) {
        $head = strings.substring($line, 0, 4);
    }
    for (def ch in strings.chars($head)) {
        if ($ch == " ") {
            $width = $width + 1;
        } elseif ($ch == "\t") {
            $width = $width + 4 - $width % 4;
        } else {
            break;
        }
        $n = $n + 1;
    }
    return Leading{width: $width, chars: $n};
}

# How many times `mark` repeats from the start of `text`.
func runOf(text as string, mark as string) {
    def n as int init 0;
    for (def ch in strings.chars($text)) {
        if ($ch != $mark) {
            break;
        }
        $n = $n + 1;
    }
    return $n;
}

# What `openerOf` returns for a line that opens no fence. Built once: almost
# every line of a chapter is one.
def const NO_FENCE as Fence init Fence{
    first: 0,
    last: 0,
    closed: false,
    mark: "",
    size: 0,
    width: 0,
    indent: "",
    info: "",
    body: ""
};

/**
 * The fence a line opens, or one with `size` 0 when it opens none.
 *
 * CommonMark: up to three columns of indentation, three or more backticks or
 * tildes, then an info string, which after backticks may not hold a backtick.
 * Four columns is indented code, never a fence.
 * @param line {string} one line
 * @return {Fence} `mark`, `size`, `width`, `indent` and `info` set
 */
export func openerOf(line as string) {
    def none as Fence init NO_FENCE;
    def text as string init chomp($line);
    # Most lines are prose: no backtick or tilde after the indentation means no
    # fence, and that is settled without measuring anything.
    def bare as string init strings.trimLeft($text);
    if ($bare == "" or not (strings.startsWith($bare, "`") or strings.startsWith($bare, "~"))) {
        return $none;
    }
    def lead as Leading init leading($text);
    if ($lead.width > 3) {
        return $none;
    }
    def rest as string init strings.substring($text, $lead.chars, len($text));
    if ($rest == "") {
        return $none;
    }
    def mark as string init strings.substring($rest, 0, 1);
    if ($mark != "`" and $mark != "~") {
        return $none;
    }
    def size as int init runOf($rest, $mark);
    if ($size < 3) {
        return $none;
    }
    def info as string init strings.trim(strings.substring($rest, $size, len($rest)));
    if ($mark == "`" and strings.contains($info, "`")) {
        return $none;
    }
    $none.mark = $mark;
    $none.size = $size;
    $none.width = $lead.width;
    $none.indent = strings.substring($text, 0, $lead.chars);
    $none.info = $info;
    return $none;
}

/**
 * Whether a line closes a fence: the same character, at least as many, up to
 * three columns in, and nothing after them but spaces.
 * @param line {string} one line
 * @param open {Fence} what `openerOf` read
 * @return {bool} true when it closes
 */
export func closes(line as string, open as Fence) {
    def text as string init chomp($line);
    def lead as Leading init leading($text);
    if ($lead.width > 3) {
        return false;
    }
    def rest as string init strings.substring($text, $lead.chars, len($text));
    def size as int init runOf($rest, $open.mark);
    if ($size < $open.size) {
        return false;
    }
    return strings.trim(strings.substring($rest, $size, len($rest))) == "";
}

/**
 * The language of a fence: its info string's first word.
 * @param info {string} the info string
 * @return {string} the language, or ""
 */
export func languageOf(info as string) {
    def trimmed as string init strings.trim($info);
    if ($trimmed == "") {
        return "";
    }
    return regex.split('\s+', $trimmed)[0];
}

# A content line with up to `width` columns of spaces taken off, as CommonMark
# does for a fence that is itself indented.
func unindent(line as string, width as int) {
    def text as string init chomp($line);
    def n as int init 0;
    def head as string init $text;
    if (len($head) > $width) {
        $head = strings.substring($text, 0, $width);
    }
    for (def ch in strings.chars($head)) {
        if ($ch != " ") {
            break;
        }
        $n = $n + 1;
    }
    return strings.substring($text, $n, len($text));
}

/**
 * Every fenced code block in a chapter, in order.
 *
 * A fence runs to the first line that closes it, so a shorter fence inside a
 * longer one is content, and a fence that is never closed runs to the end of
 * the chapter. Fences are found at the top level of the chapter: one inside a
 * block quote is not seen, and one in a list item only when its indentation is
 * under four columns.
 * @param content {string} the chapter's Markdown
 * @return {list of Fence} the fences
 */
export func fencesIn(content as string) {
    def out as list of Fence;
    def lines as list of string init strings.split($content, "\n");
    def i as int init 0;
    while ($i < len($lines)) {
        # A line with neither mark opens nothing; most lines are prose.
        if (not strings.contains($lines[$i], "`") and not strings.contains($lines[$i], "~")) {
            $i = $i + 1;
            continue;
        }
        def open as Fence init openerOf($lines[$i]);
        if ($open.size == 0) {
            $i = $i + 1;
            continue;
        }
        def j as int init $i + 1;
        while ($j < len($lines) and not closes($lines[$j], $open)) {
            $j = $j + 1;
        }
        $open.first = $i;
        $open.closed = $j < len($lines);
        $open.last = $j;
        if (not $open.closed) {
            $open.last = len($lines) - 1;
        }
        def body as list of string;
        def stop as int init $j;
        if (not $open.closed) {
            $stop = len($lines);
        }
        for (def k in $i + 1..$stop) {
            $body[] = unindent($lines[$k], $open.width);
        }
        if (len($body) > 0) {
            $open.body = strings.join($body, "\n") + "\n";
        }
        $out[] = $open;
        $i = $open.last + 1;
    }
    return $out;
}

/**
 * Which lines of a chapter belong to fenced code, fences included: the lines a
 * plugin that rewrites prose leaves alone.
 * @param content {string} the chapter's Markdown
 * @return {list of bool} one per line of `strings.split(content, "\n")`
 */
export func fencedLines(content as string) {
    def out as list of bool;
    def lines as list of string init strings.split($content, "\n");
    for (def i in 0..len($lines)) {
        $out[] = false;
    }
    for (def f in fencesIn($content)) {
        for (def k in $f.first..$f.last + 1) {
            $out[$k] = true;
        }
    }
    return $out;
}

# --- generated files and names ----------------------------------------

/**
 * The directory under `book.src` that generated files are treated as lying in:
 * `_generated`.
 * @return {string} the name
 */
export func generatedName() {
    return GENERATED;
}

/**
 * A chapter's link to a file a plugin generated: relative to the chapter, into
 * `_generated/PLUGIN/`.
 * @param chapter {string} the chapter's `src`
 * @param plugin {string} the plugin's table name, `plugin.name`
 * @param file {string} the file's name in `plugin.files`
 * @return {string} the link, such as `../_generated/mermaid/ab12.svg`
 */
export func generatedLink(chapter as string, plugin as string, file as string) {
    def up as string init strings.repeat("../", strings.count($chapter, "/"));
    return $up + GENERATED + "/" + $plugin + "/" + $file;
}

/**
 * A name made from content: the first hex digits of the sha256 of the parts,
 * one per line. Put in everything that changes the file and nothing else, and a
 * rebuild writes the same names.
 * @param parts {list of string} what the file depends on
 * @param digits {int} how many hex digits, 1 to 64
 * @return {string} the name
 * @throws {Error} kind "plugin" for a digit count out of range
 */
export func contentName(parts as list of string, digits as int) {
    if ($digits < 1 or $digits > 64) {
        fail("a content name has 1 to 64 hex digits");
    }
    def digest as string init encoding.toText(
        "hex",
        hash.compute("sha256", convert.bytesFromString("utf-8", strings.join($parts, "\n"))));
    return strings.substring($digest, 0, $digits);
}

# --- other programs ---------------------------------------------------

/**
 * What running a program gave.
 * @field started {bool} whether it could be started at all
 * @field exitCode {int} its status, -1 when it did not start
 * @field stdout {string} what it wrote to stdout
 * @field stderr {string} what it wrote to stderr
 * @field message {string} "" on success; otherwise its first message line,
 *   from stderr or else stdout, or why it could not start, or `exited N`
 */
export def struct Ran {
    started as bool,
    exitCode as int,
    stdout as string,
    stderr as string,
    message as string
};

/**
 * The first line of a message that has anything on it, trimmed.
 * @param text {string} a program's output
 * @return {string} the line, or ""
 */
export func firstLine(text as string) {
    for (def line in strings.split($text, "\n")) {
        if (strings.trim($line) != "") {
            return strings.trim($line);
        }
    }
    return "";
}

/**
 * Run a program with text on stdin, and never throw: a program that cannot
 * start, or that fails, is a `Ran` whose `message` says so.
 * @param argv {list of string} the program and its arguments
 * @param input {string} what goes on its stdin
 * @return {Ran} what happened
 */
export func runProgram(argv as list of string, input as string) {
    def out as Ran init Ran{started: false, exitCode: -1, stdout: "", stderr: "", message: ""};
    def result as os.Result;
    try {
        $result = os.run($argv, $input);
    } catch (e) {
        $out.message = $e.message;
        return $out;
    }
    $out.started = true;
    $out.exitCode = $result.exitCode;
    $out.stdout = $result.stdout;
    $out.stderr = $result.stderr;
    if ($result.exitCode != 0) {
        $out.message = firstLine($result.stderr);
        if ($out.message == "") {
            $out.message = firstLine($result.stdout);
        }
        if ($out.message == "") {
            $out.message = "exited " + convert.toString($result.exitCode);
        }
    }
    return $out;
}

/**
 * The message for a program that is not there: what to install, or which
 * setting points at it.
 * @param program {string} the command that was tried
 * @param why {string} what running it said
 * @param install {string} the package or command to install
 * @param setting {string} the setting that names the program's path
 * @return {string} the message
 */
export func missingProgram(program as string, why as string, install as string, setting as string) {
    return "cannot run " + $program + " (" + $why + "); install " + $install + ", or set `" +
        $setting + "` to where it is";
}

/**
 * The first executable of a name on `PATH`.
 * @param command {string} a bare command name
 * @return {string} its path, or "" when there is none
 */
export func onPath(command as string) {
    def raw as string init os.getEnv("PATH");
    if ($raw == "") {
        return "";
    }
    for (def dir in strings.split($raw, ":")) {
        if ($dir == "") {
            continue;
        }
        def candidate as string init path.join($dir, $command);
        if (not fs.isFile($candidate)) {
            continue;
        }
        if (fs.stat($candidate).mode & 0o111 == 0) {
            continue;
        }
        return $candidate;
    }
    return "";
}

# --- bounded concurrent work ------------------------------------------

# One item's result: its value, or the error it threw.
def struct Done {
    index as int,
    value as string,
    kind as string,
    message as string,
    file as string,
    line as int
};

# One task's share: the items it runs, and their places.
def struct Share {
    indexes as list of int,
    items as list of json.Value
};

# Run one item, turning a throw into a value. The error is read as an `Error`
# where it is one, so a place in the book survives; any other thrown value
# keeps its kind and message.
func attempt(worker as func, context as json.Value, item as json.Value, index as int) {
    def out as Done init Done{index: $index, value: "", kind: "", message: "", file: "", line: 0};
    try {
        $out.value = $worker($context, $item);
    } catch (e) {
        $out.kind = $e.kind;
        $out.message = $e.message;
        try {
            def err as Error init $e;
            $out.file = $err.file;
            $out.line = $err.line;
        } catch (other) {
            $out.file = "";
        }
    }
    return $out;
}

func runShare(worker as func, context as json.Value, share as Share) {
    def out as list of Done;
    for (def k in 0..len($share.indexes)) {
        $out[] = attempt($worker, $context, $share.items[$k], $share.indexes[$k]);
    }
    return $out;
}

/**
 * Run `worker(context, item)` for every item, up to `jobs` at a time, and
 * return the results in item order.
 *
 * Item `i` goes to task `i % n`. Every item runs; then the first one that
 * threw, in item order, is thrown again with its kind, message and place, so
 * the failure reported is the first in the book whichever finished first. The
 * worker is a top-level function taking a `json.Value` context and a
 * `json.Value` item and returning a string.
 * @param jobs {int} tasks at once; 0 is one per CPU
 * @param worker {func} the function to run
 * @param context {json.Value} what every call is given
 * @param items {list of json.Value} one per call
 * @return {list of string} what each call returned
 * @throws {Error} the first failure in item order
 */
export func work(jobs as int, worker as func, context as json.Value, items as list of json.Value) {
    def count as int init len($items);
    def values as list of string;
    if ($count == 0) {
        return $values;
    }
    def n as int init $jobs;
    if ($n < 1) {
        $n = os.NCPU;
    }
    if ($n > $count) {
        $n = $count;
    }
    def shares as list of Share;
    for (def w in 0..$n) {
        $shares[] = Share{indexes: [], items: []};
    }
    for (def i in 0..$count) {
        def s as Share init $shares[$i % $n];
        $s.indexes[] = $i;
        $s.items[] = $items[$i];
        $shares[$i % $n] = $s;
        $values[] = "";
    }
    def tasks as list of task of list of Done;
    for (def share in $shares) {
        $tasks[] = spawn {
            return runShare($worker, $context, $share);
        };
    }
    def failures as list of Done;
    for (def i in 0..$count) {
        $failures[] = Done{index: -1, value: "", kind: "", message: "", file: "", line: 0};
    }
    for (def t in $tasks) {
        for (def d in task.wait($t)) {
            $values[$d.index] = $d.value;
            if ($d.kind != "") {
                $failures[$d.index] = $d;
            }
        }
    }
    for (def f in $failures) {
        if ($f.index >= 0) {
            throw Error{kind: $f.kind, message: $f.message, file: $f.file, line: $f.line, col: 0};
        }
    }
    return $values;
}
