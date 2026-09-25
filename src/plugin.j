# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Preprocessors: programs that rewrite the book's Markdown before it is
 * rendered.
 *
 * A plugin is a separate executable, not a Jennifer module. `import` resolves at
 * parse time, so a released Grimoire cannot load code it was not built with;
 * running a program is the one extension point the language leaves open. The
 * cost is a process and a JSON round trip, and the gain is that a plugin can be
 * written in anything and installed without rebuilding anything.
 *
 * A plugin is found beside Grimoire, in its `plugins/` directory, or on `PATH`,
 * or at the path `command` names. The plugins that ship are the first case, and
 * deliberately not installed into `/usr/bin`: sharing a prefix with the command
 * itself would cost a keystroke on every `grimoire<TAB>`.
 *
 * Each configured plugin is run **once** over the whole book, in the order
 * `grimoire.toml` lists them, on the main task before any chapter is spawned.
 * That is what keeps the byte-identical-output promise intact: nothing here
 * races, and the rendered result depends on the plugins only through the text
 * they hand back. A plugin that answers differently for the same input breaks
 * that promise on its own, which is the one rule the contract cannot enforce.
 *
 * The request arrives on stdin as one JSON object and the reply is read from
 * stdout:
 *
 *     {"api": 1,
 *      "book": {"title": ..., "description": ..., "authors": [...],
 *               "language": ..., "src": ..., "out": ...},
 *      "plugin": {"name": "include", "settings": { ... }},
 *      "entries": [{"kind": "page", "title": ..., "src": ..., "out": ...,
 *                   "level": 0, "number": ...}, ...],
 *      "chapters": [{"src": "index.md", "content": "# ..."}, ...]}
 *
 *     {"api": 1, "chapters": [{"src": "index.md", "content": "# ..."}]}
 *
 * The reply may be sparse: a chapter it does not mention is unchanged. `entries`
 * carries the whole outline, parts and separators included, so a plugin can see
 * where a chapter sits without reparsing `SUMMARY.md`. Adding or reordering
 * entries is not part of this version - the reply's `chapters` is the only thing
 * read back.
 *
 * The rewritten book is materialised into a scratch directory and the build
 * reads chapters from there. Assets, images, and the logo keep coming from the
 * source tree, so a plugin only ever sees, and only ever affects, Markdown.
 * @module plugin
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use strings;
use json;
use maps;
use fs;
use os;
use path;
use convert;
use meta;

import "./config.j" as config;
import "./summary.j" as summary;

# The version the request carries and the reply is checked against. A plugin
# written for a later Grimoire can refuse an older one by reading it, and this
# one refuses a reply that does not claim the same number rather than guessing
# at a shape it does not know.
def const API as int init 1;

# fail raises a build error that names the plugin, because "exit 1" on its own
# sends the reader to the wrong repository.
func fail(kind as string, name as string, message as string) {
    throw Error{
        kind: "grimoire",
        message: $kind + " " + $name + ": " + $message,
        file: "",
        line: 0,
        col: 0
    };
}

# jsonEntry renders one outline entry.
func jsonEntry(e as summary.Entry) {
    return '{"kind":' + json.encode($e.kind) +
        ',"title":' + json.encode($e.title) +
        ',"src":' + json.encode($e.src) +
        ',"out":' + json.encode($e.out) +
        ',"level":' + convert.toString($e.level) +
        ',"number":' + json.encode($e.number) + '}';
}

# jsonChapter renders one chapter and its current text.
func jsonChapter(src as string, content as string) {
    return '{"src":' + json.encode($src) + ',"content":' + json.encode($content) + '}';
}

# request builds the JSON handed to one plugin. The text is assembled rather
# than built as a `json.Value` because the payload is a fixed shape with one
# opaque hole in it - `settings` is already JSON, straight from the config.
func request(
    c as config.Config,
    spec as config.Plugin,
    kind as string,
    entries as list of summary.Entry,
    pages as list of summary.Entry,
    sources as map of string to string) {
    def outline as list of string;
    for (def e in $entries) {
        $outline[] = jsonEntry($e);
    }
    def chapters as list of string;
    for (def p in $pages) {
        $chapters[] = jsonChapter($p.src, $sources[$p.src]);
    }
    def authors as list of string;
    for (def name in $c.authors) {
        $authors[] = json.encode($name);
    }
    return '{"api":' + convert.toString(API) +
        ',"kind":' + json.encode($kind) +
        ',"book":{"title":' + json.encode($c.title) +
        ',"description":' + json.encode($c.description) +
        ',"authors":[' + strings.join($authors, ",") + ']' +
        ',"language":' + json.encode($c.language) +
        ',"src":' + json.encode($c.srcDir) +
        ',"out":' + json.encode($c.outDir) + '}' +
        ',"plugin":{"name":' + json.encode($spec.name) +
        ',"settings":' + $spec.settings + '}' +
        ',"entries":[' + strings.join($outline, ",") + ']' +
        ',"chapters":[' + strings.join($chapters, ",") + ']}';
}

# merge reads a reply and returns the sources with its rewrites applied. A
# chapter the reply does not mention keeps the text it had; a chapter the book
# does not have is an error rather than a new file, because the outline decides
# what a book contains and a preprocessor does not.
func merge(
    kind as string,
    spec as config.Plugin,
    sources as map of string to string,
    reply as string) {
    def out as map of string to string init $sources;
    def doc as json.Value init json.decode($reply);
    if (json.typeOf($doc) != "map" or not json.has($doc, "/api")) {
        fail($kind, $spec.name, "reply is not an object with an `api` field");
    }
    if (json.asInt($doc, "/api") != API) {
        fail(
            $kind,
            $spec.name,
            "reply speaks api " + convert.toString(json.asInt($doc, "/api")) +
                ", this build speaks " + convert.toString(API));
    }
    if (not json.has($doc, "/chapters")) {
        return $out;
    }
    for (def i in 0..json.length($doc, "/chapters")) {
        def at as string init "/chapters/" + convert.toString($i);
        def src as string init json.asString($doc, $at + "/src");
        if (not maps.has($out, $src)) {
            fail($kind, $spec.name, "reply rewrites a chapter the book does not have: " + $src);
        }
        $out[$src] = json.asString($doc, $at + "/content");
    }
    return $out;
}

# The directory Grimoire keeps its own plugins in. `appDir` points at the module
# tree - `src/`, where the bundled highlight.js grammar lives - and `plugins/`
# sits beside it, because `src/` holds modules and nothing else.
def const SHIPPED as string init "plugins";

# Where a program came from, in the order a bare name is looked for. The words
# are what `grimoire plugins` prints, so they are written for a reader deciding
# whether to trust a book.
def const SHIPS as string init "ships with Grimoire";
def const IN_BOOK as string init "in this book";
def const OUTSIDE as string init "outside this book";
def const ON_PATH as string init "found on PATH";
def const NOWHERE as string init "not found";

/**
 * One configured plugin, and the program it would actually run.
 *
 * Resolution and reporting read the same answer from here, so what a build says
 * it runs is what it runs.
 * @field kind {string} "preprocessor" or "renderer"
 * @field name {string} the table name in `grimoire.toml`
 * @field command {string} the command as configured
 * @field args {list of string} the arguments that come before the request
 * @field path {string} the program that will run, or "" when nothing was found
 * @field origin {string} where it came from, in words: one of the five above
 */
export def struct Resolved {
    kind as string,
    name as string,
    command as string,
    args as list of string,
    path as string,
    origin as string
};

# The first executable of this name on `PATH`, or "". `os.run` does this lookup
# itself and says nothing about it, which is the point of doing it again here:
# a reader deciding whether to build a book wants the path before it runs, not
# the error afterwards.
func onPath(command as string) {
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

# Whether a path is inside the directory the build runs in, which is the tree a
# reader can review by reading the book's own repository.
func within(here as string, target as string) {
    def root as string init path.clean($here);
    def full as string init path.clean($target);
    return $full == $root or strings.startsWith($full, $root + "/");
}

/**
 * Work out what one configured plugin would run.
 *
 * A name with a separator in it is a path and is used as written: that is how a
 * book points at a plugin it keeps in its own repository. A bare name is looked
 * for beside Grimoire first and left to `PATH` otherwise.
 *
 * Looking beside Grimoire is what keeps the plugins that ship out of `/usr/bin`.
 * They would work there, but `grimoire` and `grimoire-include` share a prefix,
 * so installing them next to the command turns `grimoire<TAB>` from a completed
 * word into an ambiguous one - a small tax on every invocation, paid by
 * everyone, to save a lookup here.
 * @param c {config.Config} the book configuration, for `appDir`
 * @param kind {string} "preprocessor" or "renderer"
 * @param spec {config.Plugin} the table as `grimoire.toml` wrote it
 * @return {Resolved} the program, and where it came from
 */
export func resolved(c as config.Config, kind as string, spec as config.Plugin) {
    def out as Resolved init Resolved{
        kind: $kind,
        name: $spec.name,
        command: $spec.command,
        args: $spec.args,
        path: "",
        origin: NOWHERE
    };
    if (strings.contains($spec.command, "/")) {
        def full as string init $spec.command;
        if (not strings.startsWith($full, "/")) {
            $full = path.join(os.cwd(), $full);
        }
        $out.path = path.clean($full);
        if (not fs.isFile($out.path)) {
            $out.path = "";
            return $out;
        }
        $out.origin = OUTSIDE;
        if (within(os.cwd(), $out.path)) {
            $out.origin = IN_BOOK;
        }
        return $out;
    }
    def shipped as string init path.join(path.dir($c.appDir), path.join(SHIPPED, $spec.command));
    if (fs.isFile($shipped)) {
        $out.path = $shipped;
        $out.origin = SHIPS;
        return $out;
    }
    def found as string init onPath($spec.command);
    if ($found != "") {
        $out.path = $found;
        $out.origin = ON_PATH;
    }
    return $out;
}

/**
 * Every plugin this book would run, preprocessors first, in configuration order.
 * @param c {config.Config} the book configuration
 * @return {list of Resolved} one entry per configured plugin
 */
export func plan(c as config.Config) {
    def out as list of Resolved;
    for (def spec in $c.preprocessors) {
        $out[] = resolved($c, "preprocessor", $spec);
    }
    for (def spec in $c.renderers) {
        $out[] = resolved($c, "renderer", $spec);
    }
    return $out;
}

# One padded column. `io.printf` has no width verbs, so the padding is done here.
func padded(text as string, width as int) {
    def out as string init $text;
    while (len($out) < $width) {
        $out = $out + " ";
    }
    return $out;
}

/**
 * The plan as aligned lines, one per plugin.
 *
 * Four columns: what kind it is, what it is called, what will run, and where
 * that came from. The path is the whole point - a table name says nothing about
 * which program answers to it.
 * @param plan {list of Resolved} what `plan` worked out
 * @return {list of string} one line per plugin, aligned
 */
export func listing(plan as list of Resolved) {
    def kinds as int init 0;
    def names as int init 0;
    for (def r in $plan) {
        if (len($r.kind) > $kinds) {
            $kinds = len($r.kind);
        }
        if (len($r.name) > $names) {
            $names = len($r.name);
        }
    }
    def out as list of string;
    for (def r in $plan) {
        def target as string init $r.path;
        if ($target == "") {
            $target = $r.command;
        }
        def line as string init padded($r.kind, $kinds) + "  " + padded($r.name, $names) +
            "  ->  " + $target + "  (" + $r.origin + ")";
        if (len($r.args) > 0) {
            $line = $line + "\n" + padded("", $kinds + $names + 2) + "      args: " +
                strings.join($r.args, " ");
        }
        $out[] = $line;
    }
    return $out;
}

/**
 * The plugins worth saying something about before a build runs.
 *
 * A program that ships with Grimoire, or one the book carries in its own tree,
 * is reviewable by reading the repository. One that came from `PATH` or from
 * somewhere else on the machine is not, and one that is missing will stop the
 * build. Neither is refused here: a book names what it runs, and that is the
 * gate. Saying so is what this is for.
 * @param c {config.Config} the book configuration
 * @return {list of string} one warning per plugin that came from outside the book
 */
export func concerns(c as config.Config) {
    def out as list of string;
    for (def r in plan($c)) {
        if ($r.origin == SHIPS or $r.origin == IN_BOOK) {
            continue;
        }
        if ($r.origin == NOWHERE) {
            $out[] = $r.kind + " " + $r.name + ": nothing named " + $r.command +
                " was found; the build will stop when it runs";
            continue;
        }
        if ($r.origin == ON_PATH) {
            $out[] = $r.kind + " " + $r.name + ": runs " + $r.path +
                ", found on PATH rather than in this book";
            continue;
        }
        $out[] = $r.kind + " " + $r.name + ": runs " + $r.path +
            ", which is outside this book";
    }
    return $out;
}

# runOne feeds the request to one plugin and reads its reply. `os.run` raises a
# plain runtime error when the program is not on `PATH`, which says "executable
# file not found" and nothing about Grimoire - so it is caught and named here.
func runOne(c as config.Config, kind as string, spec as config.Plugin, body as string) {
    def found as Resolved init resolved($c, $kind, $spec);
    # The configured command when nothing was found, so `os.run` produces its own
    # "executable file not found" and this reports the name the book wrote.
    def program as string init $found.path;
    if ($program == "") {
        $program = $spec.command;
    }
    # Under `--verbose`, what is about to run, by its real path. A plugin is the
    # one thing a build executes that the build did not write, and until this
    # line a preprocessor ran without the build saying anything at all.
    if ($c.verbose) {
        io.printf("  plugin  %s %s  ->  %s\n", $kind, $spec.name, $program);
    }
    def argv as list of string init [$program];
    for (def arg in $spec.args) {
        $argv[] = $arg;
    }
    def result as os.Result;
    try {
        $result = os.run($argv, $body);
    } catch (e) {
        fail($kind, $spec.name, "could not run " + $spec.command + " (" + $e.message + ")");
    }
    if ($result.exitCode != 0) {
        fail(
            $kind,
            $spec.name,
            "exited " + convert.toString($result.exitCode) + ": " +
                strings.trim($result.stderr));
    }
    return $result.stdout;
}

# scratch writes the rewritten book to a fresh directory and returns it. Every
# chapter is written, not only the rewritten ones, so the directory is a complete
# source tree and the rest of the build needs to know nothing about plugins.
func scratch(pages as list of summary.Entry, sources as map of string to string) {
    def root as string init fs.makeTempDir(os.tempDir(), "grimoire-content-");
    for (def p in $pages) {
        def target as string init path.join($root, $p.src);
        def dir as string init path.dir($target);
        if ($dir != "" and $dir != ".") {
            fs.mkdirAll($dir);
        }
        fs.writeString($target, $sources[$p.src]);
    }
    return $root;
}

/**
 * Run every configured preprocessor over the book.
 *
 * @param c {config.Config} the book configuration
 * @param entries {list of summary.Entry} the whole outline, parts included
 * @param pages {list of summary.Entry} the chapters the build resolved, in
 *   outline order - the ones whose sources exist
 * @return {string} the directory chapters are to be read from: a scratch tree
 *   when a plugin ran, `srcDir` when none is configured
 * @throws {Error} kind "grimoire" when a plugin is missing, exits non-zero, or
 *   answers with something this version cannot read
 */
export func preprocess(
    c as config.Config,
    entries as list of summary.Entry,
    pages as list of summary.Entry) {
    if (len($c.preprocessors) == 0) {
        return $c.srcDir;
    }
    if (not meta.hasCapability("exec")) {
        fail(
            "preprocessor",
            $c.preprocessors[0].name,
            "this interpreter cannot run programs; preprocessors need the default `jennifer`");
    }
    def sources as map of string to string;
    for (def p in $pages) {
        $sources[$p.src] = fs.readString(path.join($c.srcDir, $p.src));
    }
    for (def spec in $c.preprocessors) {
        def reply as string init runOne(
            $c,
            "preprocessor",
            $spec,
            request($c, $spec, "preprocessor", $entries, $pages, $sources));
        $sources = merge("preprocessor", $spec, $sources, $reply);
    }
    return scratch($pages, $sources);
}

# reported reads a renderer's reply: what it wrote, and anything it wants the
# build to say. A renderer writes its own files, so there is nothing to apply -
# only to report.
func reported(kind as string, spec as config.Plugin, reply as string, key as string) {
    def out as list of string;
    def doc as json.Value init json.decode($reply);
    if (json.typeOf($doc) != "map" or not json.has($doc, "/api")) {
        fail($kind, $spec.name, "reply is not an object with an `api` field");
    }
    if (json.asInt($doc, "/api") != API) {
        fail(
            $kind,
            $spec.name,
            "reply speaks api " + convert.toString(json.asInt($doc, "/api")) +
                ", this build speaks " + convert.toString(API));
    }
    if (not json.has($doc, "/" + $key)) {
        return $out;
    }
    for (def i in 0..json.length($doc, "/" + $key)) {
        $out[] = json.asString($doc, "/" + $key + "/" + convert.toString($i));
    }
    return $out;
}

/**
 * One renderer's result: what it wrote, and what it wants said.
 * @field name {string} the table name it was configured under
 * @field written {list of string} the paths it reports having written
 * @field warnings {list of string} anything it wants the build to report
 */
export def struct Rendered {
    name as string,
    written as list of string,
    warnings as list of string
};

/**
 * Run every configured renderer over the built site.
 *
 * Called once the site and the PDF are on disk, because that is what a renderer
 * is given: the same book, already built. It writes its own files and Grimoire
 * reads back only what it says it did.
 * @param c {config.Config} the book configuration
 * @param entries {list of summary.Entry} the whole outline, parts included
 * @param pages {list of summary.Entry} the chapters the build resolved
 * @return {list of Rendered} one result per renderer, in configuration order
 * @throws {Error} kind "grimoire" when a renderer is missing, exits non-zero, or
 *   answers with something this version cannot read
 */
export func render(
    c as config.Config,
    entries as list of summary.Entry,
    pages as list of summary.Entry) {
    def out as list of Rendered;
    if (len($c.renderers) == 0) {
        return $out;
    }
    if (not meta.hasCapability("exec")) {
        fail(
            "renderer",
            $c.renderers[0].name,
            "this interpreter cannot run programs; renderers need the default `jennifer`");
    }
    # The chapters go over as the preprocessors left them, which is the book the
    # site was built from. A renderer making a second edition wants that text,
    # not the HTML it can read off disk for itself.
    def sources as map of string to string;
    for (def p in $pages) {
        $sources[$p.src] = fs.readString(path.join(config.contentDir($c), $p.src));
    }
    for (def spec in $c.renderers) {
        def reply as string init runOne(
            $c,
            "renderer",
            $spec,
            request($c, $spec, "renderer", $entries, $pages, $sources));
        $out[] = Rendered{
            name: $spec.name,
            written: reported("renderer", $spec, $reply, "written"),
            warnings: reported("renderer", $spec, $reply, "warnings")
        };
    }
    return $out;
}

/**
 * Remove a scratch tree, if the directory given is one.
 *
 * Called once the build has finished with it. The test is on the path rather
 * than on a flag, so a caller that never ran a plugin - and is holding `srcDir`
 * - cannot delete the book.
 * @param c {config.Config} the book configuration
 * @param dir {string} the directory `preprocess` returned
 * @return {bool} whether anything was removed
 */
export func discard(c as config.Config, dir as string) {
    if ($dir == "" or $dir == $c.srcDir or not strings.contains($dir, "grimoire-content-")) {
        return false;
    }
    fs.removeAll($dir);
    return true;
}
