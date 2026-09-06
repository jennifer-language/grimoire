# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The two files a built book offers a program rather than a reader: `llms.txt`
 * at the site root, and the search index as JSON beside its JavaScript twin.
 *
 * The audience is an agent that has the *published* book and not its sources. On
 * a checkout there is nothing here worth having - the Markdown is right there,
 * and `grep` beats any index. Over HTTP there is no `grep`, and the alternative
 * to these two files is fetching every page and re-deriving what the build
 * already knows: which chapters exist, in what order, under which part, and what
 * text sits under each heading.
 *
 * Both are written at build time and served as static files. That is the whole
 * design: no daemon, no protocol, no capability, nothing to keep running, and it
 * works on the static hosts these books are published to. A book on GitHub Pages
 * is readable by a program the moment it is deployed.
 *
 * `llms.txt` follows the convention at <https://llmstxt.org>: an H1 with the
 * book title, an optional blockquote summary, free-form details, then `##`
 * sections of link lists. The outline supplies the sections - a part heading in
 * `SUMMARY.md` becomes an `##`, and chapters outside any part fall under a
 * default one - so the file has the shape a reader would recognise from the
 * sidebar. Paths are relative to the site root, because a book does not know
 * where it is published; a fetcher resolves them against the URL it read the
 * file from.
 * @module agents
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use strings;
use json;
use maps;

import "./config.j" as config;
import "./search.j" as search;
import "./summary.j" as summary;
import "./util.j" as util;
import "./version.j" as version;

# Where the JSON index lands. It sits beside `search-index.js` rather than at the
# site root because it is the same data: one file for the browser, one for a
# program. `llms.txt` is the discoverable entry point and links to it, so nothing
# has to guess this path.
def const INDEX_FILE as string init "assets/search-index.json";

# The site-root file name, fixed by the convention.
def const LLMS_FILE as string init "llms.txt";

# The heading for chapters that sit under no part of their own. A book with no
# parts at all gets this one heading and nothing else, which is the right shape:
# the convention wants at least one section.
def const DEFAULT_SECTION as string init "Chapters";

/**
 * The path of the JSON index, relative to the site root.
 * @return {string} the path
 */
export func indexFile() {
    return INDEX_FILE;
}

/**
 * The path of the `llms.txt` file, relative to the site root.
 * @return {string} the path
 */
export func llmsFile() {
    return LLMS_FILE;
}

# The book's own description of itself, carried at the head of the JSON so a
# fetcher that has only this file still knows what it is holding.
def struct Book {
    title as string,
    description as string,
    language as string,
    generator as string
};

# One indexed section. The same five fields as `search.Record`, named rather than
# positional: the JavaScript twin is read by code that ships with it and can
# afford an array, while this one is read by a program that has never seen
# Grimoire.
def struct Section {
    path as string,
    title as string,
    heading as string,
    anchor as string,
    body as string
};

# The document: what the book is, then every section of it.
def struct Index {
    book as Book,
    sections as list of Section
};

/**
 * The search index as JSON: the book's own metadata, then one object per
 * indexed section, in outline order.
 *
 * The records are the ones the search index already built, so this costs a
 * re-encoding and nothing else - and the order is the order the browser index
 * has, which the build fixes deterministically whatever `--jobs` was.
 * @param c {config.Config} the book configuration
 * @param records {list of search.Record} the indexed sections, in outline order
 * @return {string} the JSON document
 */
export func index(c as config.Config, records as list of search.Record) {
    def sections as list of Section;
    for (def r in $records) {
        $sections[] = Section{
            path: $r.path,
            title: $r.title,
            heading: $r.heading,
            anchor: $r.anchor,
            body: $r.body
        };
    }
    def book as Book init Book{
        title: $c.title,
        description: $c.description,
        language: $c.language,
        generator: "Grimoire " + version.number()
    };
    return json.encode(Index{book: $book, sections: $sections}) + "\n";
}

# label renders one chapter's bullet text: the section number when the book
# numbers its chapters, then the title as it was written. The title keeps its
# Markdown - this is a Markdown file, so a chapter called `io.printf` should
# arrive with its backticks intact rather than with them stripped.
func label(e as summary.Entry, numbers as bool) {
    if ($numbers and $e.number != "") {
        return $e.number + ". " + $e.title;
    }
    return $e.title;
}

# indent is the bullet's nesting, mirroring the sidebar: a chapter nested under
# another in `SUMMARY.md` is nested under it here too.
func indent(level as int) {
    def out as string init "";
    for (def i in 0..$level) {
        $out = $out + "  ";
    }
    return $out;
}

# summaryLine folds the description onto one line. A blockquote is one line in
# this format, and a description with a newline in it would end the quote and
# turn the rest into prose.
func summaryLine(text as string) {
    return util.squeeze($text);
}

/**
 * The `llms.txt` for a book: what it is, where its machine-readable index is,
 * and every chapter as a link, grouped by the parts of the outline.
 *
 * Drafts are left out, and so is a chapter whose source is missing: `pages` is
 * the outline the build actually rendered, and a link here to anything else
 * would be a link to a page that was never written. This file exists to be
 * followed rather than read, so a dead link in it is worse than a short list.
 * @param c {config.Config} the book configuration
 * @param entries {list of summary.Entry} the book outline, parts included
 * @param pages {list of summary.Entry} the chapters the build resolved and wrote
 * @return {string} the file contents
 */
export func llms(
    c as config.Config,
    entries as list of summary.Entry,
    pages as list of summary.Entry) {
    def wrote as map of string to int;
    for (def p in $pages) {
        $wrote[$p.out] = 1;
    }
    def out as list of string;
    $out[] = "# " + $c.title;
    if ($c.description != "") {
        $out[] = "";
        $out[] = "> " + summaryLine($c.description);
    }
    $out[] = "";
    $out[] = "- Language: " + $c.language;
    $out[] = "- Every section of every page, as JSON: [" + INDEX_FILE + "](" + INDEX_FILE + ")";
    if ($c.pdf) {
        $out[] = "- The same book in one file: [" + $c.pdfOutput + "](" + $c.pdfOutput + ")";
    }
    # The heading is written when the first chapter under it is: a part with
    # nothing but drafts in it is not a section of anything.
    def pending as string init DEFAULT_SECTION;
    def open as bool init false;
    for (def e in $entries) {
        if ($e.kind == summary.partKind()) {
            $pending = $e.title;
            $open = false;
            continue;
        }
        # A separator ends a part, the same rule the printable build follows: the
        # chapters after it belong to the book rather than to what came before.
        if ($e.kind == summary.separatorKind()) {
            $pending = DEFAULT_SECTION;
            $open = false;
            continue;
        }
        if ($e.kind != summary.pageKind() or not maps.has($wrote, $e.out)) {
            continue;
        }
        if (not $open) {
            $out[] = "";
            $out[] = "## " + $pending;
            $out[] = "";
            $open = true;
        }
        $out[] = indent($e.level) + "- [" + label($e, $c.sectionNumbers) + "](" + $e.out + ")";
    }
    return strings.join($out, "\n") + "\n";
}
