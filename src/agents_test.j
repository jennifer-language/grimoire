# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `agents.j`, run by `jennifer test src/agents_test.j`.
 *
 * Both files here are read by a program that has never seen Grimoire, which is
 * what the tests are about. The JSON is decoded and walked rather than matched
 * as text, so a renamed field fails here rather than in whatever is parsing it;
 * and `llms.txt` is checked for the two things a fetcher depends on - that every
 * link points at a page the build actually wrote, and that the outline's parts
 * survive as sections.
 * @module agents_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use strings;
use lists;

# A book with a description and no PDF; the tests that need another shape say so
# by changing one field.
func book() {
    def c as config.Config init config.defaults();
    $c.title = "The Book";
    $c.description = "What it is about.";
    $c.language = "de";
    return $c;
}

func rec(path as string, heading as string, body as string) {
    return search.record($path, "Page " + $path, $heading, "anchor-x", $body, 1200);
}

func page(title as string, out as string, level as int, number as string) {
    return summary.Entry{
        kind: summary.pageKind(),
        title: $title,
        src: $out + ".md",
        out: $out,
        level: $level,
        number: $number
    };
}

func part(title as string) {
    return summary.Entry{
        kind: summary.partKind(),
        title: $title,
        src: "",
        out: "",
        level: 0,
        number: ""
    };
}

func separator() {
    return summary.Entry{
        kind: summary.separatorKind(),
        title: "",
        src: "",
        out: "",
        level: 0,
        number: ""
    };
}

func draft(title as string) {
    return summary.Entry{
        kind: summary.draftKind(),
        title: $title,
        src: "",
        out: "",
        level: 0,
        number: ""
    };
}

# The outline the build resolved: every page entry it was handed. A test that
# wants a missing chapter passes a shorter list.
func resolved(entries as list of summary.Entry) {
    def out as list of summary.Entry;
    for (def e in $entries) {
        if ($e.kind == summary.pageKind()) {
            $out[] = $e;
        }
    }
    return $out;
}

func lines(text as string) {
    return strings.split(strings.trim($text), "\n");
}

# --- the JSON index --------------------------------------------------

func testIndexCarriesTheBooksOwnMetadata() {
    def none as list of search.Record;
    def doc as json.Value init json.decode(index(book(), $none));
    testing.assertEqual(json.asString($doc, "/book/title"), "The Book");
    testing.assertEqual(json.asString($doc, "/book/description"), "What it is about.");
    testing.assertEqual(json.asString($doc, "/book/language"), "de");
    testing.assertContains(json.asString($doc, "/book/generator"), "Grimoire ");
}

# Named fields rather than the JavaScript twin's positional arrays: this one is
# read by something that was not shipped with it.
func testIndexSectionsAreNamedObjects() {
    def records as list of search.Record init [rec("a.html", "Heading", "body text")];
    def doc as json.Value init json.decode(index(book(), $records));
    testing.assertEqual(json.length($doc, "/sections"), 1);
    testing.assertEqual(json.asString($doc, "/sections/0/path"), "a.html");
    testing.assertEqual(json.asString($doc, "/sections/0/title"), "Page a.html");
    testing.assertEqual(json.asString($doc, "/sections/0/heading"), "Heading");
    testing.assertEqual(json.asString($doc, "/sections/0/anchor"), "anchor-x");
    testing.assertEqual(json.asString($doc, "/sections/0/body"), "body text");
}

# The order is the outline order the build fixed; a search hit's position in a
# book is part of what it means.
func testIndexKeepsRecordOrder() {
    def records as list of search.Record init [
        rec("a.html", "One", "x"),
        rec("b.html", "Two", "y"),
        rec("c.html", "Three", "z")
    ];
    def doc as json.Value init json.decode(index(book(), $records));
    testing.assertEqual(json.asString($doc, "/sections/0/path"), "a.html");
    testing.assertEqual(json.asString($doc, "/sections/1/path"), "b.html");
    testing.assertEqual(json.asString($doc, "/sections/2/path"), "c.html");
}

func testIndexOfAnEmptyBookIsStillValidJson() {
    def none as list of search.Record;
    def doc as json.Value init json.decode(index(book(), $none));
    testing.assertEqual(json.length($doc, "/sections"), 0);
}

# Every text file this repository writes ends in one.
func testIndexEndsWithANewline() {
    def none as list of search.Record;
    testing.assertTrue(strings.endsWith(index(book(), $none), "\n"));
}

# --- llms.txt --------------------------------------------------------

func testLlmsOpensWithTheTitleAndSummary() {
    def outline as list of summary.Entry init [page("Intro", "index.html", 0, "")];
    def got as list of string init lines(llms(book(), $outline, resolved($outline)));
    testing.assertEqual($got[0], "# The Book");
    testing.assertEqual($got[2], "> What it is about.");
}

# The blockquote is the summary slot of the convention, so a book without a
# description has no blockquote rather than an empty one.
func testLlmsWithoutADescriptionHasNoBlockquote() {
    def c as config.Config init book();
    $c.description = "";
    def outline as list of summary.Entry init [page("Intro", "index.html", 0, "")];
    testing.assertFalse(strings.contains(llms($c, $outline, resolved($outline)), ">"));
}

# A description written across two lines would end the blockquote and turn the
# rest into prose.
func testLlmsFoldsTheDescriptionOntoOneLine() {
    def c as config.Config init book();
    $c.description = "One line.\nAnd another.";
    def outline as list of summary.Entry init [page("Intro", "index.html", 0, "")];
    def got as list of string init lines(llms($c, $outline, resolved($outline)));
    testing.assertEqual($got[2], "> One line. And another.");
}

func testLlmsPointsAtTheJsonIndex() {
    def outline as list of summary.Entry init [page("Intro", "index.html", 0, "")];
    testing.assertContains(llms(book(), $outline, resolved($outline)), indexFile());
}

# The printable book is worth naming when there is one, and worth not inventing
# when there is not.
func testLlmsNamesThePdfOnlyWhenThereIsOne() {
    def outline as list of summary.Entry init [page("Intro", "index.html", 0, "")];
    testing.assertFalse(strings.contains(llms(book(), $outline, resolved($outline)), "book.pdf"));
    def c as config.Config init book();
    $c.pdf = true;
    testing.assertContains(llms($c, $outline, resolved($outline)), "book.pdf");
}

# A part heading in `SUMMARY.md` is a section here, and the chapters before any
# part fall under the default one.
func testLlmsTurnsPartsIntoSections() {
    def outline as list of summary.Entry init [
        page("Intro", "index.html", 0, ""),
        part("Guides"),
        page("First", "first.html", 0, ""),
        part("Reference"),
        page("API", "api.html", 0, "")
    ];
    def got as string init llms(book(), $outline, resolved($outline));
    testing.assertContains($got, "## Chapters");
    testing.assertContains($got, "## Guides");
    testing.assertContains($got, "## Reference");
}

# The same rule the printable build follows: a separator ends a part, so what
# comes after it belongs to the book rather than to what came before.
func testLlmsEndsAPartAtASeparator() {
    def outline as list of summary.Entry init [
        part("Guides"),
        page("First", "first.html", 0, ""),
        separator(),
        page("Appendix", "appendix.html", 0, "")
    ];
    def got as list of string init lines(llms(book(), $outline, resolved($outline)));
    testing.assertEqual($got[len($got) - 3], "## Chapters");
    testing.assertEqual($got[len($got) - 1], "- [Appendix](appendix.html)");
}

# A part whose chapters are all drafts is not a section of anything, so its
# heading is never written.
func testLlmsSkipsAPartWithNothingUnderIt() {
    def outline as list of summary.Entry init [
        page("Intro", "index.html", 0, ""),
        part("Planned"),
        draft("Someday")
    ];
    def got as string init llms(book(), $outline, resolved($outline));
    testing.assertFalse(strings.contains($got, "Planned"));
    testing.assertFalse(strings.contains($got, "Someday"));
}

# The build drops a chapter whose source is missing and warns about it. Linking
# it here would be a link to a page nobody wrote.
func testLlmsLinksOnlyWhatTheBuildWrote() {
    def outline as list of summary.Entry init [
        page("Here", "here.html", 0, ""),
        page("Gone", "gone.html", 0, "")
    ];
    def wrote as list of summary.Entry init [page("Here", "here.html", 0, "")];
    def got as string init llms(book(), $outline, $wrote);
    testing.assertContains($got, "here.html");
    testing.assertFalse(strings.contains($got, "gone.html"));
}

func testLlmsNestsTheWayTheSidebarDoes() {
    def outline as list of summary.Entry init [
        page("Top", "top.html", 0, ""),
        page("Under", "under.html", 1, "")
    ];
    def got as list of string init lines(llms(book(), $outline, resolved($outline)));
    testing.assertEqual($got[len($got) - 2], "- [Top](top.html)");
    testing.assertEqual($got[len($got) - 1], "  - [Under](under.html)");
}

func testLlmsCarriesSectionNumbersWhenTheBookDoes() {
    def outline as list of summary.Entry init [page("Install", "install.html", 0, "2.1")];
    def c as config.Config init book();
    testing.assertContains(
        llms($c, $outline, resolved($outline)),
        "- [2.1. Install](install.html)");
    $c.sectionNumbers = false;
    testing.assertContains(llms($c, $outline, resolved($outline)), "- [Install](install.html)");
}

# A chapter titled after an identifier keeps its backticks: this is a Markdown
# file, and the title is Markdown wherever else it appears.
func testLlmsKeepsMarkdownInATitle() {
    def outline as list of summary.Entry init [page("`io.printf`", "io.html", 0, "")];
    testing.assertContains(llms(book(), $outline, resolved($outline)), "- [`io.printf`](io.html)");
}

func testLlmsOfAnEmptyOutlineIsStillAFile() {
    def none as list of summary.Entry;
    def got as list of string init lines(llms(book(), $none, $none));
    testing.assertEqual($got[0], "# The Book");
    testing.assertFalse(lists.contains($got, "## Chapters"));
}

# --- the two paths ---------------------------------------------------

# `llms.txt` is the discoverable entry point, so it is the one file whose name
# the convention fixes; the index sits beside its JavaScript twin because it is
# the same data.
func testTheFilePaths() {
    testing.assertEqual(llmsFile(), "llms.txt");
    testing.assertEqual(indexFile(), "assets/search-index.json");
}
