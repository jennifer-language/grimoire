# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The build itself: read the outline, render every chapter, write the site, and
 * report what happened. This is the only module that touches the filesystem for
 * output, so everything below it stays pure and testable.
 *
 * The generated site is deliberately **portable**: every asset and every
 * cross-link is written relative to the page that holds it, so the same output
 * directory works served from a web root, served from a subdirectory, or opened
 * straight off the disk with no server at all.
 * @module build
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use fs;
use os;
use path;
use task;
use strings;
use lists;
use maps;
use convert;

import "./config.j" as config;
import "./summary.j" as summary;
import "./content.j" as content;
import "./layout.j" as layout;
import "./theme.j" as theme;
import "./assets.j" as assets;
import "./keywords.j" as keywords;
import "./search.j" as search;
import "./pdfbook.j" as pdfbook;
import "./util.j" as util;

# Where Grimoire keeps the highlight.js grammar it ships, relative to its own
# program directory (`src/`, where main.j lives).
def const HLJS_GRAMMAR as string init "assets/hljs-jennifer.js";

# Folded into the scheduling key so equal-sized chapters keep a stable order; it
# only has to exceed the number of chapters a book can hold.
def const WEIGHT_SCALE as int init 1000000;

# A bound on the script-stripping loop: a logo needing more passes than this is
# not a logo, and an unbounded loop over hostile input is how a build hangs.
def const MAX_SCRIPT_STRIPS as int init 64;

/**
 * What a build produced.
 * @field pages {int} chapters written
 * @field assets {int} non-Markdown files copied from the source tree
 * @field records {int} sections in the search index
 * @field written {int} total bytes written
 * @field missing {list of string} outline entries whose source file is absent
 * @field warnings {list of string} non-fatal problems worth telling the user about
 * @field pdfBytes {int} the PDF size, or 0 when no PDF was built
 */
export def struct Report {
    pages as int,
    assets as int,
    records as int,
    written as int,
    missing as list of string,
    warnings as list of string,
    pdfBytes as int
};

# note prints one progress line when the run asked for them. Printing from inside
# a render worker is safe - `io.printf` writes a whole line at a time, so lines
# from concurrent workers interleave but never garble - though with more than one
# job the order is the order chapters finish, not the order they are listed.
func note(c as config.Config, message as string) {
    if ($c.verbose) {
        io.printf("%s\n", $message);
    }
}

# writeFile creates the parent directory and writes the file, returning the byte
# count so the report can total the output without a second stat pass.
func writeFile(target as string, text as string) {
    def dir as string init path.dir($target);
    if ($dir != "" and $dir != ".") {
        fs.mkdirAll($dir);
    }
    fs.writeString($target, $text);
    return len($text);
}

# searchNote names the search index in the asset line only when one is built.
# plural picks the right noun for a count, so a progress line does not say
# "1 jobs".
func plural(n as int, one as string, many as string) {
    if ($n == 1) {
        return convert.toString($n) + " " + $one;
    }
    return convert.toString($n) + " " + $many;
}

func searchNote(c as config.Config) {
    if ($c.search) {
        return ", search index";
    }
    return "";
}

# resolvePages drops outline entries whose source is missing and de-duplicates
# repeated targets, keeping the first mention - the position a reader will use
# for previous / next.
func resolvePages(c as config.Config, entries as list of summary.Entry) {
    def out as list of summary.Entry;
    def seen as map of string to int;
    for (def e in summary.pages($entries)) {
        if (maps.has($seen, $e.out)) {
            continue;
        }
        if (not fs.isFile(path.join($c.srcDir, $e.src))) {
            continue;
        }
        $seen[$e.out] = 1;
        $out[] = $e;
    }
    return $out;
}

# rendersRoot reports whether the outline itself puts a chapter at the site root.
# This has to be answered from the outline rather than from the output directory:
# on a rebuild the previous run's index.html is still sitting there, so asking the
# filesystem answers a question about the last build, not this one.
func rendersRoot(pages as list of summary.Entry) {
    for (def p in $pages) {
        if ($p.out == "index.html") {
            return true;
        }
    }
    return false;
}

# missingPages lists the outline entries with no file behind them, so the build
# can report a broken SUMMARY instead of silently skipping a chapter.
func missingPages(c as config.Config, entries as list of summary.Entry) {
    def out as list of string;
    for (def e in summary.pages($entries)) {
        if (not fs.isFile(path.join($c.srcDir, $e.src))) {
            $out[] = $e.src;
        }
    }
    return $out;
}

# How many keywords a page's meta tag carries. Enough to describe a chapter,
# few enough that the tag stays a summary rather than a word list.
def const KEYWORD_LIMIT as int init 10;

# pageKeywords derives the `keywords` meta tag for a page, or "" when the book
# has turned them off.
func pageKeywords(c as config.Config, rendered as content.Rendered) {
    if (not $c.keywords) {
        return "";
    }
    return keywords.line($rendered, KEYWORD_LIMIT, $c.keywordStopwords);
}

# editUrl fills the `{path}` slot of the configured template with the chapter's
# source path.
func editUrl(c as config.Config, src as string) {
    if ($c.editUrlTemplate == "") {
        return "";
    }
    return strings.replace($c.editUrlTemplate, '{path}', $src);
}

# titleFor prefers the outline title (it is what the sidebar shows) and falls
# back to the chapter's own first heading.
func titleFor(entry as summary.Entry, rendered as content.Rendered) {
    if ($entry.title != "") {
        return $entry.title;
    }
    return $rendered.title;
}

# plainTitle strips the Markdown out of an outline title, for the search index
# and the document title where markup would only be noise.
func plainTitle(title as string) {
    return util.squeeze(strings.replace($title, "`", ""));
}

# copyAssets mirrors every non-Markdown file from the source tree into the
# output, so images, downloads, and a favicon sit beside the pages that use them.
func copyAssets(c as config.Config) {
    def count as int init 0;
    def prefix as int init len($c.srcDir) + 1;
    for (def st in fs.walk($c.srcDir)) {
        if ($st.isDir) {
            continue;
        }
        def rel as string init strings.replace(
            strings.substring($st.path, $prefix, len($st.path)),
            "\\",
            "/");
        if (strings.lower(path.ext($rel)) == ".md") {
            continue;
        }
        def target as string init path.join($c.outDir, $rel);
        def dir as string init path.dir($target);
        if ($dir != "" and $dir != ".") {
            fs.mkdirAll($dir);
        }
        fs.writeBytes($target, fs.readBytes($st.path));
        $count = $count + 1;
    }
    return $count;
}

# redirect is the stand-in landing page for a book whose outline has no chapter
# at the site root: a meta refresh plus a plain link, so it works with scripting
# off and never leaves a reader on a blank page.
func redirect(c as config.Config, target as string) {
    return "<!DOCTYPE html>\n<html lang=\"" + $c.language + "\">\n<head>\n" +
        '<meta charset="utf-8">' + "\n" +
        '<meta http-equiv="refresh" content="0; url=' + $target + '">' + "\n" +
        '<link rel="canonical" href="' + $target + '">' + "\n" +
        "<title>" + $c.title + "</title>\n</head>\n<body>\n" +
        '<p>Continue to <a href="' + $target + '">' + $c.title + "</a>.</p>\n" +
        "</body>\n</html>\n";
}

# --- brand and highlighting assets ---------------------------------

# resolveBrand turns the configured logo path into the markup the top bar uses.
# An SVG is read and inlined so it inherits the colour mode and costs no extra
# request; anything else is referenced as an image. A `<script>` inside an SVG
# would run with the page`s own origin, so it is stripped: a logo is artwork.
func resolveBrand(c as config.Config) {
    if ($c.logo == "") {
        return layout.noBrand();
    }
    def source as string init path.join($c.srcDir, $c.logo);
    if (not fs.isFile($source)) {
        return layout.noBrand();
    }
    if (strings.lower(path.ext($c.logo)) != ".svg") {
        # Copied into the site by copyAssets, alongside every other non-Markdown
        # file, so the reference resolves without any extra work here.
        return layout.imageBrand($c.logo);
    }
    def markup as string init fs.readString($source);
    def at as int init strings.indexOf($markup, "<svg");
    if ($at < 0) {
        return layout.noBrand();
    }
    # Drop anything before the root element: an XML prolog or a DOCTYPE is legal
    # in a standalone file but not inside an HTML document.
    return layout.svgBrand(stripScripts(strings.substring($markup, $at, len($markup))));
}

# stripScripts removes every `<script>...</script>` from inlined markup.
func stripScripts(markup as string) {
    def out as string init $markup;
    def guard as int init 0;
    while ($guard < MAX_SCRIPT_STRIPS) {
        def start as int init strings.indexOf(strings.lower($out), "<script");
        if ($start < 0) {
            return $out;
        }
        def rest as string init strings.substring($out, $start, len($out));
        def close as int init strings.indexOf(strings.lower($rest), "</script>");
        if ($close < 0) {
            return strings.substring($out, 0, $start);
        }
        $out = strings.substring($out, 0, $start) +
            strings.substring($rest, $close + len("</script>"), len($rest));
        $guard = $guard + 1;
    }
    return $out;
}

# shipHighlightGrammar copies Grimoire's own Jennifer highlight.js grammar into
# the site. No CDN carries a Jennifer language, so without this the one language
# a Jennifer book is certain to contain would be the one left unhighlighted.
func shipHighlightGrammar(c as config.Config) {
    def source as string init path.join($c.appDir, HLJS_GRAMMAR);
    if (not fs.isFile($source)) {
        return 0;
    }
    return writeFile(path.join($c.outDir, "assets/hljs-jennifer.js"), fs.readString($source));
}

# One worker's share of the render: the chapters it wrote and the index records
# it produced. Chapters are independent, so the expensive part of a build - the
# Markdown parse, which is the bulk of it - parallelises cleanly.
# Records are returned grouped by chapter, with the chapter each group belongs
# to, so the caller can reassemble them in outline order. Concatenating whole
# workers instead would make the search index depend on how the work was split -
# the same book would produce a different file at `-j 4` and `-j 16`.
def struct Slice {
    chapters as list of int,
    chapterRecords as list of list of search.Record,
    written as int
};

# workerCount picks the parallelism: the configured value, else one worker per
# CPU, never more workers than there are chapters to render.
func workerCount(c as config.Config, total as int) {
    def n as int init $c.jobs;
    if ($n < 1) {
        $n = os.NCPU;
    }
    if ($n > $total) {
        $n = $total;
    }
    if ($n < 1) {
        return 1;
    }
    return $n;
}

# prepareDirs creates every output directory up front, on this task, so the
# workers only ever write files - no two of them race to create the same parent.
func prepareDirs(c as config.Config, pages as list of summary.Entry) {
    def seen as map of string to int;
    for (def e in $pages) {
        def dir as string init path.dir(path.join($c.outDir, $e.out));
        if ($dir != "" and $dir != "." and not maps.has($seen, $dir)) {
            $seen[$dir] = 1;
            fs.mkdirAll($dir);
        }
    }
    fs.mkdirAll(path.join($c.outDir, "assets"));
    # The PDF task writes concurrently with the render workers, so its directory
    # is created here too - on this task, before anything is spawned.
    if ($c.pdf) {
        def pdfDir as string init path.dir(path.join($c.outDir, $c.pdfOutput));
        if ($pdfDir != "" and $pdfDir != ".") {
            fs.mkdirAll($pdfDir);
        }
    }
}

# pageRecords turns one rendered chapter into its search records, skipping the
# empty lead-in a chapter has when its first heading is also its first line.
func pageRecords(c as config.Config, out as string, title as string, rendered as content.Rendered) {
    def records as list of search.Record;
    for (def section in $rendered.sections) {
        if ($section.text == "" and $section.heading == "") {
            continue;
        }
        $records[] = search.record(
            $out,
            $title,
            $section.heading,
            $section.anchor,
            $section.text,
            $c.searchBodyChars);
    }
    return $records;
}

# One chapter's place in the work queue: its index in `pages`, and how much work
# it is likely to be.
def struct Chunk {
    index as int,
    weight as int
};

# byWeight orders the heaviest chapter first. The index is folded into the key so
# equal-sized chapters keep a fixed order and the build stays deterministic.
func byWeight(c as Chunk) {
    return -($c.weight * WEIGHT_SCALE) + $c.index;
}

# leastLoaded returns the worker with the smallest accumulated weight, preferring
# the lowest-numbered on a tie so the assignment is deterministic.
func leastLoaded(loads as list of int) {
    def at as int init 0;
    def i as int init 1;
    while ($i < len($loads)) {
        if ($loads[$i] < $loads[$at]) {
            $at = $i;
        }
        $i = $i + 1;
    }
    return $at;
}

# assignWork splits the chapters across workers, heaviest first, each one going
# to whichever worker is least loaded so far.
#
# Chapter sizes here span two orders of magnitude - 135 KiB against a 7 KiB
# median - so how the work is split decides the wall clock. Dealing them out in
# outline order leaves one worker holding 337 KiB while another holds far less;
# this rule gets the largest share down to 213 KiB on eight workers, which is
# exactly the total divided by eight. At sixteen it reaches 135 KiB, the size of
# the single largest chapter and therefore the floor - a chapter cannot be split.
#
# Sorting first and then dealing round-robin is the obvious approximation and is
# not good enough: it improves on eight workers but is *worse* than plain
# round-robin on sixteen. Taking the least-loaded worker each time is the version
# that holds up.
func assignWork(c as config.Config, pages as list of summary.Entry, jobs as int) {
    def chunks as list of Chunk;
    def i as int init 0;
    while ($i < len($pages)) {
        def file as string init path.join($c.srcDir, $pages[$i].src);
        def weight as int init 0;
        if (fs.isFile($file)) {
            $weight = fs.stat($file).size;
        }
        $chunks[] = Chunk{index: $i, weight: $weight};
        $i = $i + 1;
    }
    def buckets as list of list of int;
    def loads as list of int;
    for (def w in 0..$jobs) {
        def empty as list of int;
        $buckets[] = $empty;
        $loads[] = 0;
    }
    for (def chunk in lists.sortBy($chunks, byWeight)) {
        def w as int init leastLoaded($loads);
        # The append sugar does not chain after an index, and value semantics mean
        # the inner list has to be taken out, extended, and put back.
        def bucket as list of int init $buckets[$w];
        $bucket[] = $chunk.index;
        $buckets[$w] = $bucket;
        $loads[$w] = $loads[$w] + $chunk.weight;
    }
    return $buckets;
}

/**
 * The work split a build would use, for inspecting or testing the scheduler
 * without running a build.
 * @param c {config.Config} the book configuration
 * @param pages {list of summary.Entry} the chapters to render
 * @param jobs {int} how many workers to split across
 * @return {list of list of int} each worker's chapter indices
 */
export func assignment(c as config.Config, pages as list of summary.Entry, jobs as int) {
    return assignWork($c, $pages, $jobs);
}

/**
 * The chapters a build would render, in outline order and with missing sources
 * dropped.
 * @param c {config.Config} the book configuration
 * @param entries {list of summary.Entry} the outline
 * @return {list of summary.Entry} the renderable chapters
 */
export func resolvedPages(c as config.Config, entries as list of summary.Entry) {
    return resolvePages($c, $entries);
}

# emptyGroups is one empty record group per chapter, ready to be filled in.
func emptyGroups(n as int) {
    def out as list of list of search.Record;
    for (def i in 0..$n) {
        def none as list of search.Record;
        $out[] = $none;
    }
    return $out;
}

# placeRecords slots one worker's results back into their chapters' positions, so
# the index is assembled in outline order rather than in whatever order the work
# happened to be split.
func placeRecords(groups as list of list of search.Record, slice as Slice) {
    def out as list of list of search.Record init $groups;
    def k as int init 0;
    while ($k < len($slice.chapters)) {
        $out[$slice.chapters[$k]] = $slice.chapterRecords[$k];
        $k = $k + 1;
    }
    return $out;
}

func flattenRecords(groups as list of list of search.Record) {
    def out as list of search.Record;
    for (def group in $groups) {
        $out = lists.concat($out, $group);
    }
    return $out;
}

# renderSlice renders the chapters one worker was given. Which chapters those
# are is decided up front by `assignWork`, so a worker just walks its own list.
func renderSlice(
    c as config.Config,
    pages as list of summary.Entry,
    labels as list of string,
    items as list of layout.NavItem,
    brand as layout.Brand,
    mine as list of int) {
    def chapters as list of int;
    def chapterRecords as list of list of search.Record;
    def written as int init 0;
    def at as int init 0;
    while ($at < len($mine)) {
        def i as int init $mine[$at];
        def entry as summary.Entry init $pages[$i];
        def source as string init path.join($c.srcDir, $entry.src);
        note($c, "  render  " + $entry.src + "  ->  " + $entry.out);
        def rendered as content.Rendered init content.render(fs.readString($source), $c.highlight);
        def root as string init util.relPrefix(util.depthOf($entry.out));
        def view as layout.View init layout.View{
            title: plainTitle(titleFor($entry, $rendered)),
            keywords: pageKeywords($c, $rendered),
            body: $rendered.html,
            toc: content.tocHtml($rendered.headings, $c.tocDepth),
            root: $root,
            prevTitle: "",
            prevHref: "",
            nextTitle: "",
            nextHref: "",
            editUrl: editUrl($c, $entry.src)
        };
        if ($i > 0) {
            $view.prevTitle = $labels[$i - 1];
            $view.prevHref = $root + $pages[$i - 1].out;
        }
        if ($i + 1 < len($pages)) {
            $view.nextTitle = $labels[$i + 1];
            $view.nextHref = $root + $pages[$i + 1].out;
        }
        def nav as string init layout.navHtml($items, $entry.out, $root);
        $written = $written +
            writeFile(path.join($c.outDir, $entry.out), layout.page($c, $view, $nav, $brand));
        if ($c.search) {
            $chapters[] = $i;
            $chapterRecords[] = pageRecords($c, $entry.out, $view.title, $rendered);
        }
        $at = $at + 1;
    }
    return Slice{chapters: $chapters, chapterRecords: $chapterRecords, written: $written};
}

/**
 * Build the site: render every chapter, write the theme stylesheet, the runtime,
 * and the search index, copy the source tree's other files across, and render
 * the PDF when the configuration asks for one. Chapters render in parallel, one
 * task per CPU by default.
 * @param c {config.Config} the book configuration
 * @return {Report} what was written
 * @throws {Error} when the source directory is absent or a chapter fails to render
 */
export func run(c as config.Config) {
    if (not fs.isDir($c.srcDir)) {
        throw Error{
            kind: "grimoire",
            message: "source directory not found: " + $c.srcDir,
            file: $c.srcDir,
            line: 0,
            col: 0
        };
    }
    def entries as list of summary.Entry init summary.load($c.srcDir);
    def pages as list of summary.Entry init resolvePages($c, $entries);
    def records as list of search.Record;
    def written as int init 0;
    fs.mkdirAll($c.outDir);
    # The sidebar and the pager labels are Markdown. Render them once here rather
    # than once per chapter: on a book this size that is the difference between
    # a few hundred Markdown parses and a few tens of thousands.
    def items as list of layout.NavItem init layout.navItems($entries, $c.sectionNumbers);
    def labels as list of string;
    for (def e in $pages) {
        $labels[] = content.inline($e.title);
    }
    def brand as layout.Brand init resolveBrand($c);
    prepareDirs($c, $pages);
    # The PDF is one long serial layout - the parse and page flow inside the
    # `markdown` module, which cannot be split across tasks. Starting it here
    # rather than after the site means it overlaps the parallel chapter render
    # instead of queueing behind it, so `--pdf` costs about max(site, pdf)
    # instead of their sum. It writes a different file, so nothing races.
    def pdfTasks as list of task of int;
    if ($c.pdf) {
        note($c, "  pdf     laying out " + $c.pdfOutput + " (alongside the site)");
        $pdfTasks[] = spawn {
            return writePdf($c, $entries);
        };
    }
    def jobs as int init workerCount($c, len($pages));
    def buckets as list of list of int init assignWork($c, $pages, $jobs);
    # No `grimoire:` prefix here - that one is reserved for warnings on stderr, and
    # a progress header wearing it would read like something had gone wrong.
    note(
        $c,
        "building " + $c.srcDir + " -> " + $c.outDir + " (theme " + $c.theme + ", " +
            plural(len($pages), "chapter", "chapters") + ", " +
            plural($jobs, "job", "jobs") + ")");
    def workers as list of task of Slice;
    for (def w in 0..$jobs) {
        def mine as list of int init $buckets[$w];
        $workers[] = spawn {
            return renderSlice($c, $pages, $labels, $items, $brand, $mine);
        };
    }
    def perChapter as list of list of search.Record init emptyGroups(len($pages));
    for (def worker in $workers) {
        def slice as Slice init task.wait($worker);
        $written = $written + $slice.written;
        $perChapter = placeRecords($perChapter, $slice);
    }
    $records = flattenRecords($perChapter);
    note($c, "  assets  stylesheet, runtime" + searchNote($c));
    $written = $written +
        writeFile(path.join($c.outDir, "assets/grimoire.css"), theme.stylesheet($c.theme));
    $written = $written + writeFile(path.join($c.outDir, "assets/grimoire.js"), assets.runtime());
    if ($c.search) {
        $written = $written +
            writeFile(path.join($c.outDir, "assets/search-index.js"), search.script($records));
    }
    # A book whose outline never lands on the site root still needs a landing page,
    # and it is rewritten on every build: the first chapter, the title, or the
    # outline order can all have changed since the last run.
    if (len($pages) > 0 and not rendersRoot($pages)) {
        $written = $written +
            writeFile(path.join($c.outDir, "index.html"), redirect($c, $pages[0].out));
    }
    def warnings as list of string;
    if ($c.logo != "" and not fs.isFile(path.join($c.srcDir, $c.logo))) {
        $warnings[] = "logo not found, falling back to the default mark: " + $c.logo;
    }
    if (config.usesHighlightJs($c)) {
        if (shipHighlightGrammar($c) == 0) {
            $warnings[] = "highlight.js grammar for Jennifer not found at " +
                path.join($c.appDir, HLJS_GRAMMAR) +
                "; other languages still highlight, Jennifer falls back to the built-in pass";
        }
    }
    if (config.highlightJsIgnored($c)) {
        $warnings[] = "[highlightjs] enabled = true is ignored while [highlight] enabled = false;" +
            " no highlighting and no CDN request";
    }
    def copied as int init copyAssets($c);
    note($c, "  copied  " + plural($copied, "file", "files") + " from " + $c.srcDir);
    def pdfBytes as int init 0;
    for (def pdfTask in $pdfTasks) {
        $pdfBytes = task.wait($pdfTask);
        $written = $written + $pdfBytes;
    }
    return Report{
        pages: len($pages),
        assets: $copied,
        records: len($records),
        written: $written,
        missing: missingPages($c, $entries),
        warnings: $warnings,
        pdfBytes: $pdfBytes
    };
}

/**
 * Render just the PDF, without rebuilding the site.
 * @param c {config.Config} the book configuration
 * @param entries {list of summary.Entry} the book outline
 * @return {int} the size of the written PDF, in bytes
 * @throws {Error} when the document cannot be laid out
 */
export func writePdf(c as config.Config, entries as list of summary.Entry) {
    def target as string init path.join($c.outDir, $c.pdfOutput);
    def dir as string init path.dir($target);
    if ($dir != "" and $dir != ".") {
        fs.mkdirAll($dir);
    }
    def data as bytes init pdfbook.render($c, $entries);
    fs.writeBytes($target, $data);
    return len($data);
}

/**
 * Load the outline for a configuration, for callers that need it without
 * running a full build (the PDF-only path).
 * @param c {config.Config} the book configuration
 * @return {list of summary.Entry} the outline
 */
export func outline(c as config.Config) {
    return summary.load($c.srcDir);
}
