#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Time the `markdown` and `pdf` modules over a directory of Markdown, with no
 * Grimoire around them.
 *
 *   jennifer run scripts/bench-md.j <docsdir> [reps] [nopdf]
 *
 * `scripts/bench.sh` runs this as one of its cases and folds the output into the
 * result file; it is a separate program because the question it answers is a
 * different one. A `grimoire build` measures Grimoire: reading files, walking
 * the tree, highlighting, the search index, writing output. This measures the
 * three library calls underneath - `markdown.parse`, `markdown.renderPdfDoc`,
 * `pdf.render` - so a change in the modules can be told apart from a change in
 * the tool.
 *
 * Both renderers are timed, but only one of them is on Grimoire's path:
 * `markdown.parse` is, because the site build walks the tree itself, while
 * `markdown.toHtml` is the module's own HTML renderer, here as a reference
 * point. The PDF phases are exactly what `grimoire pdf` does.
 *
 * Output is tab-separated records on stdout, one measurement per line; a
 * `--` prefix would make them look like Markdown, so they are plain.
 * @module benchmd
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use os;
use fs;
use lists;
use maps;
use strings;
use convert;
use time;

import "markdown.j" as markdown;
import "pdf.j" as pdf;

# What separates two chapters in the assembled book, and what `pdfbook` uses. A
# lone comment, so the parse turns it into a page_break node.
def const PAGE_BREAK as string init "<!-- pagebreak -->";

# Wide enough that a zero-padded microsecond count sorts as a number for any file
# this will ever see (10^12 us is eleven days).
def const KEY_WIDTH as int init 12;

# How many of the slowest files to name. Enough to show a pattern, few enough to
# read.
def const SLOW_COUNT as int init 12;

# now is the clock these measurements are taken with, in microseconds. Nanosecond
# resolution is real but not meaningful here - the phases being timed run for
# milliseconds and the numbers are easier to read without the last three digits.
func now() {
    return time.unixNanos(time.now()) // 1000;
}

# pad left-fills a number with zeros, so that string ordering is numeric ordering.
func pad(n as int) {
    def out as string init convert.toString($n);
    while (len($out) < KEY_WIDTH) {
        $out = "0" + $out;
    }
    return $out;
}

# skipValues reads the comma-separated patterns out of a `skip=a,b` argument.
func skipValues(arg as string) {
    def out as list of string;
    for (def part in strings.split(strings.substring($arg, 5, len($arg)), ",")) {
        def clean as string init strings.trim($part);
        if ($clean != "") {
            $out[] = $clean;
        }
    }
    return $out;
}

# excluded reports whether a path matches one of the skip patterns, which are
# plain substrings rather than globs: the caller is passing the book's own
# `pdf.exclude` values, and those are path prefixes.
func excluded(file as string, skip as list of string) {
    for (def pattern in $skip) {
        if (strings.indexOf($file, $pattern) >= 0) {
            return true;
        }
    }
    return false;
}

# sources lists the Markdown under a directory, in a fixed order so that two runs
# read the same bytes in the same sequence.
func sources(dir as string, skip as list of string) {
    def out as list of string;
    for (def st in fs.walk($dir)) {
        if ($st.isDir or not strings.endsWith($st.path, ".md")) {
            continue;
        }
        if (excluded($st.path, $skip)) {
            continue;
        }
        $out[] = $st.path;
    }
    return lists.sort($out);
}

# record prints one measurement.
func record(kind as string, rep as int, phase as string, micros as int) {
    io.printf("%s\t%d\t%s\t%d\n", $kind, $rep, $phase, $micros);
}

# slowest prints the files that cost the most to parse, worst first, from the
# per-file minimum across the repetitions - the minimum rather than the mean
# because the thing being looked for is a file the parser is bad at, and the
# scheduler only ever adds time.
func slowest(best as map of string to int, sizes as map of string to int) {
    def keys as list of string;
    for (def file in maps.keys($best)) {
        $keys[] = pad($best[$file]) + "\t" + $file;
    }
    def sorted as list of string init lists.sort($keys);
    def shown as int init SLOW_COUNT;
    if (len($sorted) < $shown) {
        $shown = len($sorted);
    }
    for (def i in 0..$shown) {
        def key as string init $sorted[len($sorted) - 1 - $i];
        def at as int init strings.indexOf($key, "\t");
        def file as string init strings.substring($key, $at + 1, len($key));
        io.printf("mdslow\t%d\t%d\t%d\t%s\n", $i + 1, $best[$file], $sizes[$file], $file);
    }
}

if (len(os.ARGS) < 2) {
    io.eprintf("usage: bench-md.j <docsdir> [reps] [nopdf] [skip=<substring>,...]\n");
    exit 2;
}

def dir as string init os.ARGS[1];
if (not fs.isDir($dir)) {
    io.eprintf("bench-md.j: not a directory: %s\n", $dir);
    exit 1;
}

# The options, in any order after the directory: a number is the repetition
# count, `nopdf` drops the PDF phases, and `skip=` takes the same paths the
# book's `pdf.exclude` does, so that the PDF measured here covers the same
# chapters `grimoire pdf` measures.
def reps as int init 3;
def withPdf as bool init true;
def skip as list of string;
for (def i in 2..len(os.ARGS)) {
    def arg as string init os.ARGS[$i];
    if ($arg == "nopdf") {
        $withPdf = false;
        continue;
    }
    if (strings.startsWith($arg, "skip=")) {
        for (def pattern in skipValues($arg)) {
            $skip[] = $pattern;
        }
        continue;
    }
    $reps = convert.toInt($arg);
}

# Read the corpus once, outside every timed region: this is a benchmark of the
# modules, and leaving the disk in it would measure the page cache instead.
def files as list of string init sources($dir, $skip);
def texts as list of string;
def sizes as map of string to int;
def total as int init 0;
for (def file in $files) {
    def text as string init fs.readString($file);
    $texts[] = $text;
    $sizes[$file] = len($text);
    $total = $total + len($text);
}
if (len($files) == 0) {
    io.eprintf("bench-md.j: no .md files under %s\n", $dir);
    exit 1;
}

# The whole book as one document, the way `pdfbook.combine` assembles it.
def book as string init strings.join($texts, "\n\n" + PAGE_BREAK + "\n\n");

io.printf("mdcorpus\tfiles\t%d\n", len($files));
io.printf("mdcorpus\tbytes\t%d\n", $total);
io.printf("mdcorpus\tbookbytes\t%d\n", len($book));
io.printf("mdcorpus\treps\t%d\n", $reps);

def best as map of string to int;
for (def rep in 1..$reps + 1) {
    def parseUs as int init 0;
    for (def i in 0..len($files)) {
        def at as int init now();
        markdown.parse($texts[$i]);
        def took as int init now() - $at;
        $parseUs = $parseUs + $took;
        if (not maps.has($best, $files[$i]) or $took < $best[$files[$i]]) {
            $best[$files[$i]] = $took;
        }
    }
    record("md", $rep, "parse_us", $parseUs);

    def htmlUs as int init 0;
    for (def text in $texts) {
        def at as int init now();
        markdown.toHtml($text);
        $htmlUs = $htmlUs + (now() - $at);
    }
    record("md", $rep, "tohtml_us", $htmlUs);

    if ($withPdf) {
        def at as int init now();
        def tree as markdown.Node init markdown.parse($book);
        record("md", $rep, "pdfparse_us", now() - $at);
        def laid as int init now();
        def doc as pdf.Document init markdown.renderPdfDoc($tree, markdown.pdfDefaults());
        record("md", $rep, "pdflayout_us", now() - $laid);
        def emitted as int init now();
        def size as int init len(pdf.render($doc));
        record("md", $rep, "pdfemit_us", now() - $emitted);
        record("md", $rep, "pdf_bytes", $size);
        record("md", $rep, "pdf_pages", len($doc.pages));
    }
}

slowest($best, $sizes);
