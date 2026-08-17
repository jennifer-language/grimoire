# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Grimoire - build a documentation website, and a printable PDF, from a
 * directory of Markdown files.
 *
 * Point it at a directory of Markdown. If that directory holds a `SUMMARY.md`
 * it is used as the book outline, in the mdBook shape; if it does not, the
 * outline is derived from the directory tree, the way MkDocs does. The output is
 * a self-contained static site - themed, searchable, and with a colour-mode
 * selector - that works served from a web root, served from a subdirectory, or
 * opened straight off the disk.
 *
 *   grimoire build --src docs --out site
 *   grimoire build --pdf
 *   grimoire serve
 *   grimoire themes
 *
 * @module grimoire
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use fs;
use path;
use time;
use convert;
use strings;

import "args.j" as args;
import "./config.j" as config;
import "./summary.j" as summary;
import "./build.j" as build;
import "./theme.j" as theme;
import "./locale.j" as locale;
import "./serve.j" as serve;
import "./watch.j" as watch;

# Kept in step with `version` in `deck.toml`, which the registry requires to
# match the tag a release is published from.
def const VERSION as string init "grimoire 0.1.0";
def const DEFAULT_CONFIG as string init "grimoire.toml";
def const DEFAULT_ADDR as string init "127.0.0.1:8080";

# --- command-line surface -------------------------------------------

# commonFlags are the four overrides every build-shaped command accepts, so
# `build`, `pdf`, and `serve` all take the same source and output arguments.
func commonFlags(p as args.Parser) {
    def out as args.Parser init $p;
    $out = args.flag($out, "config", "c", DEFAULT_CONFIG, "path to grimoire.toml");
    $out = args.flag($out, "src", "s", "", "source directory (overrides the config)");
    $out = args.flag($out, "out", "o", "", "output directory (overrides the config)");
    $out = args.boolFlag($out, "verbose", "v", "report each chapter as it is rendered");
    return $out;
}

# The interface language, on the two commands that render a site. Not on `pdf`:
# the printed book has no chrome to translate.
func uiLanguageFlag(p as args.Parser) {
    return args.flag(
        $p,
        "ui-language",
        "L",
        "",
        "language for Grimoire's own strings (overrides the config)");
}

# Where the two navigation columns go, on the same two commands. Trying an
# arrangement is exactly what `serve --watch` is for, so it takes them as well.
func columnFlags(p as args.Parser) {
    def out as args.Parser init $p;
    $out = args.flag($out, "nav", "", "", "book contents column: left, right, or off");
    $out = args.flag($out, "toc", "", "", "on-this-page column: left, right, or off");
    return $out;
}

# Emptying the output directory first, on the two commands that write one.
#
# Both directions, unlike the one-way boolean flags around them: this setting has
# a reasonable answer either way, so a book that turns it on in `grimoire.toml`
# still needs a way to say "not this time" - and that way had better not be
# editing the file.
func cleanFlags(p as args.Parser) {
    def out as args.Parser init $p;
    $out = args.boolFlag($out, "clean", "", "empty the output directory first");
    $out = args.boolFlag($out, "no-clean", "", "keep what is already in the output directory");
    return $out;
}

# Where the title in the top bar links, on the two commands that render a site.
# Book identity rather than a per-run choice, like `repoUrl` and `logo` beside it
# - but it is also the setting whose effect you most want to see before writing
# it down, which is what a flag is for. `--title-url ""` puts it back to the
# book's own landing page.
func titleUrlFlag(p as args.Parser) {
    return args.flag($p, "title-url", "", "", "where the title in the top bar links");
}

# Whether a hand-written HTML block in the Markdown reaches the page as written.
# On by default; both directions for the same reason `--clean` has both, and
# because the interesting case - a book assembled from Markdown its author did
# not write - is usually one run rather than a setting.
func rawHtmlFlags(p as args.Parser) {
    def out as args.Parser init $p;
    $out = args.boolFlag($out, "raw-html", "", "emit hand-written HTML blocks as written");
    $out = args.boolFlag($out, "no-raw-html", "", "escape hand-written HTML blocks");
    return $out;
}

func buildParser() {
    def p as args.Parser init commonFlags(args.parser("build", "Build the site"));
    $p = args.flag($p, "theme", "t", "", "theme name (overrides the config)");
    $p = args.flag($p, "mode", "m", "", "default colour mode: auto, light, or dark");
    $p = columnFlags($p);
    $p = cleanFlags($p);
    $p = rawHtmlFlags($p);
    $p = titleUrlFlag($p);
    $p = args.boolFlag($p, "pdf", "", "also render the book to PDF");
    $p = args.boolFlag($p, "no-search", "", "skip the search index");
    $p = args.intFlag($p, "jobs", "j", 0, "chapters to render in parallel (0 = one per CPU)");
    $p = args.boolFlag($p, "quiet", "q", "print nothing on success");
    return uiLanguageFlag($p);
}

func pdfParser() {
    def p as args.Parser init commonFlags(args.parser("pdf", "Render the book to PDF only"));
    $p = args.flag($p, "output", "", "", "PDF path, relative to the output directory");
    $p = args.flag($p, "paper", "", "", "page size: a4 or letter");
    return $p;
}

func serveParser() {
    def p as args.Parser init commonFlags(args.parser("serve", "Build, then serve the site"));
    $p = args.flag($p, "addr", "a", DEFAULT_ADDR, "address to listen on");
    $p = args.boolFlag($p, "no-build", "", "serve what is already in the output directory");
    $p = args.boolFlag($p, "watch", "w", "rebuild whenever a source file changes");
    $p = args.boolFlag($p, "no-reload", "", "with --watch, do not reload the browser");
    $p = columnFlags($p);
    # Only the build `serve` does on the way in prunes; a watch rebuild never
    # does, or the directory being served would empty itself on every save.
    $p = cleanFlags($p);
    $p = rawHtmlFlags($p);
    $p = titleUrlFlag($p);
    return uiLanguageFlag($p);
}

func initParser() {
    def p as args.Parser init args.parser("init", "Write a starter book into a directory");
    $p = args.positionalOpt($p, "dir", ".", "directory to initialise (default: the current one)");
    return $p;
}

func parser() {
    def p as args.Parser init args.parser(
        "grimoire",
        "Build a documentation site and a PDF from a directory of Markdown files");
    $p = args.version($p, VERSION);
    $p = args.command($p, "build", "Build the site", buildParser());
    $p = args.command($p, "pdf", "Render the book to PDF only", pdfParser());
    $p = args.command($p, "serve", "Build, then serve the site over HTTP", serveParser());
    $p = args.command(
        $p,
        "themes",
        "List the built-in themes",
        args.parser("themes", "List the built-in themes"));
    $p = args.command($p, "init", "Write a starter book into a directory", initParser());
    return $p;
}

# --- configuration --------------------------------------------------

# warn reports a problem that does not stop the build: a chapter in the outline
# with no file behind it, a theme name that does not resolve, a flag value
# outside the set it allows.
func warn(message as string) {
    io.eprintf("grimoire: %s\n", $message);
}

# position reads one of the two column-placement flags. A `grimoire.toml` key of
# the wrong shape quietly keeps the default, which is the right stance for a file
# that may be half written - but a flag was typed just now, by someone watching,
# so a value outside the set says so before falling back.
func position(r as args.Result, name as string, deflt as string) {
    def value as string init args.asString($r, $name);
    if (config.validPosition($value)) {
        return $value;
    }
    warn("--" + $name + ": no such position " + $value + " (left, right, or off); using " + $deflt);
    return $deflt;
}

# configure loads the config file named on the command line and layers the
# command-line overrides on top, so a flag always wins over a file.
func configure(r as args.Result, appDir as string) {
    def c as config.Config init config.load(args.asString($r, "config"));
    # Where Grimoire itself is installed, so the build can find the assets it
    # ships (the Jennifer highlight.js grammar). The launcher works it out from
    # its own path and hands it down, rather than anything here reading the
    # working directory - `grimoire` has to run correctly from anywhere.
    $c.appDir = $appDir;
    if (args.has($r, "src")) {
        $c.srcDir = args.asString($r, "src");
    }
    if (args.has($r, "out")) {
        $c.outDir = args.asString($r, "out");
    }
    if (args.has($r, "theme")) {
        $c.theme = args.asString($r, "theme");
    }
    if (args.has($r, "mode")) {
        $c.defaultMode = args.asString($r, "mode");
    }
    if (args.has($r, "nav")) {
        $c.navPosition = position($r, "nav", $c.navPosition);
    }
    if (args.has($r, "toc")) {
        $c.tocPosition = position($r, "toc", $c.tocPosition);
    }
    if (args.has($r, "output")) {
        $c.pdfOutput = args.asString($r, "output");
    }
    if (args.has($r, "paper")) {
        $c.pdfPaper = args.asString($r, "paper");
    }
    if (args.has($r, "pdf")) {
        $c.pdf = true;
    }
    # `--no-clean` wins over `--clean`, which is the safe way round: the two
    # together are a mistake, and the reading that deletes nothing is the one to
    # take when it is not clear which was meant.
    if (args.has($r, "clean")) {
        $c.clean = true;
    }
    if (args.has($r, "no-clean")) {
        $c.clean = false;
    }
    # Same rule as the pair above: the two together are a mistake, and the
    # reading that escapes is the one to take when it is not clear which was
    # meant. Escaping shows the markup; the other way runs it.
    # Taken verbatim, empty included: `--title-url ""` is how a run puts the link
    # back to the book's own landing page when the file says otherwise.
    if (args.has($r, "title-url")) {
        $c.titleUrl = args.asString($r, "title-url");
    }
    if (args.has($r, "raw-html")) {
        $c.rawHtml = true;
    }
    if (args.has($r, "no-raw-html")) {
        $c.rawHtml = false;
    }
    if (args.has($r, "no-search")) {
        $c.search = false;
    }
    if (args.has($r, "jobs")) {
        $c.jobs = args.asInt($r, "jobs");
    }
    if (args.has($r, "ui-language")) {
        $c.uiLanguage = args.asString($r, "ui-language");
    }
    if (args.has($r, "verbose")) {
        $c.verbose = true;
    }
    # Grimoire's own strings are library state rather than a value threaded
    # through the renderer, so they are selected here, at the one point where the
    # configuration is finished and nothing has rendered yet. Every worker that
    # spawns later shares the choice.
    locale.install($c.uiLanguage);
    return $c;
}

func checkTheme(c as config.Config) {
    if (not theme.has($c.theme)) {
        warn("unknown theme " + $c.theme + "; using " + theme.fallback() +
            " (see: grimoire themes)");
    }
}

# checkLanguage says so when Grimoire has no strings of its own in the book's
# language. Not an error: the book still builds, with English furniture around
# the author's own text, which is the only sensible fallback.
func checkLanguage(c as config.Config) {
    if (not locale.has($c.uiLanguage)) {
        warn("no interface strings for " + $c.uiLanguage + "; using English (have: " +
            strings.join(locale.names(), ", ") + ")");
    }
}

func reportMissing(report as build.Report) {
    for (def src in $report.missing) {
        warn("outline entry has no source file: " + $src);
    }
    for (def note in $report.warnings) {
        warn($note);
    }
}

# The same courtesy `build.j` extends to its progress lines, for the one count
# this module formats itself: a summary that says "1 entries" reads as a bug.
func entryCount(n as int) {
    if ($n == 1) {
        return "1 entry";
    }
    return convert.toString($n) + " entries";
}

func humanBytes(n as int) {
    if ($n < 1024) {
        return convert.toString($n) + " B";
    }
    if ($n < 1024 * 1024) {
        return convert.toString($n // 1024) + " KiB";
    }
    # One decimal at this scale: a 1.9 MiB PDF reported as "1 MiB" reads as a bug.
    def tenths as int init ($n * 10) // (1024 * 1024);
    return convert.toString($tenths // 10) + "." + convert.toString($tenths % 10) + " MiB";
}

# --- commands -------------------------------------------------------

func runBuild(r as args.Result, appDir as string) {
    def c as config.Config init configure($r, $appDir);
    checkTheme($c);
    checkLanguage($c);
    def started as time.Time init time.now();
    def report as build.Report init build.run($c);
    def elapsed as int init time.milliseconds(time.sub(time.now(), $started));
    reportMissing($report);
    if (args.has($r, "quiet")) {
        return 0;
    }
    io.printf(
        "built %d pages into %s/ (%s, %d assets) in %d ms\n",
        $report.pages,
        $c.outDir,
        humanBytes($report.written),
        $report.assets,
        $elapsed);
    # Said out loud whenever anything was deleted, and not only under --verbose:
    # this is the one thing a build does that cannot be undone by running it
    # again, so it belongs in the summary a reader actually sees.
    if ($report.pruned > 0) {
        io.printf("  pruned: %s from %s/ before building\n", entryCount($report.pruned), $c.outDir);
    }
    if ($c.search) {
        io.printf("  search index: %d sections\n", $report.records);
    }
    if ($report.pdfBytes > 0) {
        io.printf(
            "  pdf: %s (%s)\n",
            path.join($c.outDir, $c.pdfOutput),
            humanBytes($report.pdfBytes));
    }
    if (len($report.missing) > 0) {
        return 1;
    }
    return 0;
}

func runPdf(r as args.Result, appDir as string) {
    def c as config.Config init configure($r, $appDir);
    if (not fs.isDir($c.srcDir)) {
        warn("source directory not found: " + $c.srcDir);
        return 1;
    }
    def started as time.Time init time.now();
    def entries as list of summary.Entry init build.outline($c);
    def size as int init build.writePdf($c, $entries);
    def elapsed as int init time.milliseconds(time.sub(time.now(), $started));
    io.printf(
        "rendered %s (%s) in %d ms\n",
        path.join($c.outDir, $c.pdfOutput),
        humanBytes($size),
        $elapsed);
    return 0;
}

func runServe(r as args.Result, appDir as string) {
    def c as config.Config init configure($r, $appDir);
    if (not args.has($r, "no-build")) {
        checkTheme($c);
        checkLanguage($c);
        def report as build.Report init build.run($c);
        reportMissing($report);
        io.printf("built %d pages into %s/\n", $report.pages, $c.outDir);
    }
    if (not fs.isDir($c.outDir)) {
        warn("nothing to serve: " + $c.outDir + " does not exist");
        return 1;
    }
    # Reloading the browser is the other half of watching, and is off without it:
    # there is nothing to reload for when nothing is rebuilding.
    def live as bool init args.has($r, "watch") and not args.has($r, "no-reload");
    if (args.has($r, "watch")) {
        io.printf("%s\n", watch.notice($c, $live));
        def configPath as string init args.asString($r, "config");
        spawn {
            return watch.run($c, $configPath);
        };
    }
    return serve.run($c.outDir, args.asString($r, "addr"), $live);
}

func runThemes() {
    io.printf("Built-in themes (set html.theme in grimoire.toml):\n\n");
    for (def line in theme.catalog()) {
        io.printf("  %s\n", $line);
    }
    io.printf("\nEvery theme ships both a light and a dark palette; readers pick with the\n");
    io.printf("selector in the top bar, which defaults to following the system setting.\n");
    return 0;
}

# The starter book `init` writes. A raw string throughout: the TOML holds braces
# and the edit-URL template holds a placeholder, neither of which should be read
# as a Jennifer interpolation slot.
def const STARTER_CONFIG as string init '# Grimoire book configuration.
# Every key is optional - delete what you do not need.

[book]
title = "My Book"
description = "What this book is about."
authors = ["Your Name"]
# What introduces those names in the page footer and on the PDF cover.
# "" prints them alone.
authorsLabel = "Written by"
language = "en"
src = "docs"

[build]
out = "site"
# Empty the output directory before building, so a chapter deleted from the book
# stops being published. Off by default, because an output directory can also
# hold files this tool never wrote. Top-level dotfiles are kept either way.
clean = false

[html]
# Any of the ten built-in themes; run `grimoire themes` for the list.
theme = "grimoire"
# The colour mode a first-time reader gets: auto, light, or dark.
mode = "auto"
# Where the two navigation columns go. navPosition is the book outline,
# tocPosition the headings of the page being read. Each takes left, right, or
# off; off leaves that column out of the pages entirely.
navPosition = "left"
tocPosition = "right"
# A hand-written HTML block in the Markdown reaches the page as written. Turn it
# off for a book assembled from Markdown you did not write - a generated
# reference, contributed chapters - and those blocks are escaped and shown
# instead. Everything else on a page is escaped either way.
rawHtml = true
tocDepth = 3
sectionNumbers = true
# The footer is emitted verbatim, so it may carry HTML.
footer = "Rendered with <a href=\"https://grimoire.jennifer-lang.dev/\">Grimoire</a>"
# Where the title in the top bar links. Unset, it goes to this book. Point it at
# the site this book belongs to and the title becomes the way back out. Absolute
# or root-relative: it is not rewritten per page.
# titleUrl = "https://example.com/"
# repoUrl = "https://example.com/my/book"
# repoLabel = "Source"
# editUrl = "https://example.com/my/book/edit/main/docs/{path}"
# An SVG is inlined into the mark beside the title, so it follows the colour
# mode; any other image is referenced. The path is relative to `src`.
# logo = "logo.svg"
# Give each page a `keywords` meta tag, worked out from its own title, headings,
# and code spans.
keywords = true
# Words the keyword pass should ignore on top of the built-in English list -
# whatever is furniture in the subject this book covers.
# keywordStopwords = ["def", "init", "return"]

[highlight]
# Syntax highlighting for code blocks. This is the master switch, and on its own
# it is the built-in highlighter: Jennifer blocks are coloured while the site is
# built, with no JavaScript and nothing fetched. Off by default.
enabled = false

[highlightjs]
# Additionally load highlight.js from a CDN, which is what colours the languages
# the built-in highlighter does not know. This is the only setting that makes a
# built site depend on a third party, and it does nothing unless [highlight]
# above is also enabled. Everything else here describes that CDN layer.
enabled = false
cdn = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1"
style = "github"
styleDark = "github-dark"
languages = ["bash", "go", "json", "yaml", "xml", "ini"]

[search]
enabled = true
bodyChars = 1200

[pdf]
enabled = false
output = "my-book.pdf"
paper = "a4"
bookmarkLevel = 3
# Print "page/total" at the outside edge of every page footer.
pageNumbers = false
# The other side of that footer: {version} is the git tag, {commit} the short
# commit id when there is no tag. "" leaves that side empty.
# footerLeft = "My Book {version} {commit}"
# Open the book with a title page. Off starts it at the first chapter.
titlePage = true
# Chapters to leave out of the PDF; the site still carries them. A path relative
# to `src`, or a directory with a trailing slash.
# exclude = ["api/", "technical/coverage.md"]
';

def const STARTER_SUMMARY as string init '# Summary

[Introduction](index.md)

# Getting started

- [Installation](getting-started/installation.md)
- [First steps](getting-started/first-steps.md)
';

def const STARTER_INDEX as string init '# Introduction

Welcome. This book was scaffolded by `grimoire init`.

Write your chapters as Markdown files under `docs/`, list them in
`docs/SUMMARY.md`, and run:

```sh
grimoire build
```

Delete `SUMMARY.md` if you would rather have the outline derived from the
directory tree.
';

def const STARTER_INSTALL as string init '# Installation

Describe how to install the thing this book is about.

```sh
# an example command
echo hello
```
';

def const STARTER_FIRST as string init '# First steps

Walk the reader through their first success.

> Tip: headings become anchors, entries in the on-this-page column,
> and records in the search index - so write them as the questions a reader
> would ask.
';

# writeIfAbsent never clobbers: `init` on an existing directory fills the gaps
# and leaves everything already written alone.
func writeIfAbsent(target as string, body as string) {
    if (fs.exists($target)) {
        io.printf("  kept    %s\n", $target);
        return false;
    }
    def dir as string init path.dir($target);
    if ($dir != "" and $dir != ".") {
        fs.mkdirAll($dir);
    }
    fs.writeString($target, $body);
    io.printf("  wrote   %s\n", $target);
    return true;
}

func runInit(r as args.Result) {
    def dir as string init args.asString($r, "dir");
    fs.mkdirAll($dir);
    io.printf("initialising a Grimoire book in %s/\n", $dir);
    writeIfAbsent(path.join($dir, DEFAULT_CONFIG), STARTER_CONFIG);
    writeIfAbsent(path.join($dir, "docs/SUMMARY.md"), STARTER_SUMMARY);
    writeIfAbsent(path.join($dir, "docs/index.md"), STARTER_INDEX);
    writeIfAbsent(path.join($dir, "docs/getting-started/installation.md"), STARTER_INSTALL);
    writeIfAbsent(path.join($dir, "docs/getting-started/first-steps.md"), STARTER_FIRST);
    io.printf("\nnext: grimoire build && grimoire serve\n");
    return 0;
}

# --- entry ----------------------------------------------------------

func dispatch(r as args.Result, appDir as string) {
    match ($r.command) {
        when "build" { return runBuild($r, $appDir); }
        when "pdf" { return runPdf($r, $appDir); }
        when "serve" { return runServe($r, $appDir); }
        when "themes" { return runThemes(); }
        when "init" { return runInit($r); }
        else {
            io.printf("%s\n", args.usage(parser()));
            return 2;
        }
    }
}

/**
 * Run Grimoire: parse the command line, dispatch the command, and turn anything
 * thrown along the way into a diagnostic and a non-zero status. This is the
 * whole program; the `grimoire` launcher exists only to locate it and to say
 * where Grimoire itself is installed.
 * @param appDir {string} the directory holding Grimoire's own bundled assets
 * @param argv {list of string} the command line, program name first
 * @return {int} the process exit status
 */
export func run(appDir as string, argv as list of string) {
    try {
        def result as args.Result init args.parse(parser(), $argv);
        if ($result.done) {
            io.printf("%s\n", $result.helpText);
            return 0;
        }
        return dispatch($result, $appDir);
    } catch (e) {
        warn($e.message);
        return 1;
    }
}
