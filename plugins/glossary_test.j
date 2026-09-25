# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `glossary.j`, run by `jennifer test glossary_test.j`.
 *
 * Two things carry the weight here. The anchor has to be the one Grimoire wrote,
 * so `slugify` is tested against the cases that make its rule visible. And a
 * term must not be found where it is not a word: inside a longer word, inside
 * code, inside a link, in a heading, in a fence.
 * @module glossary_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use os;

func glossaryChapter() {
    return "# Glossary\n\n## Outline\n\nThe order of the book.\n\n" +
        "## Search index\n\nWhat the search box reads.\n\n" +
        "## REPL (`read-eval-print`)\n\nA prompt.\n";
}

func requestFor(chapters as string, settings as string) {
    return '{"api":1,"kind":"preprocessor","book":{"title":"A Book","description":"d",' +
        '"authors":["Ada"],"language":"en","src":"docs","out":"site"},' +
        '"plugin":{"name":"glossary","settings":' + $settings + '},' +
        '"entries":[],"chapters":[' + $chapters + ']}';
}

func chapter(src as string, content as string) {
    return '{"src":' + json.encode($src) + ',"content":' + json.encode($content) + '}';
}

# The anchor Grimoire writes drops punctuation rather than turning it into a
# separator, which is what keeps a hand-written cross-reference working.
func testAnchorsMatchTheOnesGrimoireWrites() {
    testing.assertEqual(slugify("Outline"), "outline");
    testing.assertEqual(slugify("Search index"), "search-index");
    testing.assertEqual(slugify("REPL (`cmd/jennifer/repl.go`)"), "repl-cmdjenniferreplgo");
    testing.assertEqual(slugify("M20 - System libraries"), "m20---system-libraries");
    testing.assertEqual(slugify("!!!"), "section");
}

func testTermsAreTheGlossaryHeadings() {
    def found as list of Term init termsIn(glossaryChapter(), 2);
    testing.assertEqual(len($found), 3);
    testing.assertEqual($found[0].word, "Outline");
    testing.assertEqual($found[1].word, "Search index");
    testing.assertEqual($found[1].anchor, "search-index");
}

func testAHashInsideAFenceIsNotADefinition() {
    def content as string init "## Real\n\n```sh\n## Not a heading\n```\n\n## Also real\n";
    def found as list of Term init termsIn($content, 2);
    testing.assertEqual(len($found), 2);
    testing.assertEqual($found[1].word, "Also real");
}

func testATermIsFoundOnlyAsAWholeWord() {
    testing.assertEqual(wordIndex("the index is here", "index"), 4);
    testing.assertEqual(wordIndex("it was indexed twice", "index"), -1);
    testing.assertEqual(wordIndex("reindex it", "index"), -1);
    testing.assertEqual(wordIndex("Index, capitalised", "index"), 0);
    testing.assertEqual(wordIndex("at the end: index", "index"), 12);
}

# A term inside code is usually the thing rather than the word for the thing, and
# a term already inside a link must not be linked twice.
func testATermInsideCodeOrALinkIsNotFound() {
    testing.assertEqual(wordIndex("run `grimoire index` now", "index"), -1);
    testing.assertEqual(wordIndex("see [the index](x.md) there", "index"), -1);
    testing.assertEqual(wordIndex('<a title="index">x</a>', "index"), -1);
    testing.assertEqual(wordIndex("![index](i.png)", "index"), -1);
    # An unclosed backtick is prose, not a span.
    testing.assertEqual(wordIndex("a stray ` and the index", "index"), 18);
}

func testOnlyTheFirstUseIsLinked() {
    def terms as list of Term init [Term{word: "outline", anchor: "outline"}];
    def out as string init link(
        "The outline is first.\nThe outline again.\n",
        $terms,
        "glossary.md");
    testing.assertContains($out, "The [outline](glossary.md#outline) is first.");
    testing.assertContains($out, "The outline again.");
}

func testHeadingsAndFencesAreLeftAlone() {
    def terms as list of Term init [Term{word: "outline", anchor: "outline"}];
    def content as string init "# The outline\n\n```\nthe outline in code\n```\n\n" +
        "the outline in prose\n";
    def out as string init link($content, $terms, "glossary.md");
    testing.assertContains($out, "# The outline\n");
    testing.assertContains($out, "the outline in code");
    testing.assertContains($out, "the [outline](glossary.md#outline) in prose");
}

# Longest first: otherwise "index" takes the first word of "search index" and the
# longer term never matches.
func testTheLongerTermWins() {
    def terms as list of Term init ordered(
        [
            Term{word: "index", anchor: "index"},
            Term{word: "search index", anchor: "search-index"}
        ],
        []);
    testing.assertEqual($terms[0].word, "search index");
    def out as string init link("the search index is built last", $terms, "g.md");
    testing.assertContains($out, "the [search index](g.md#search-index) is built last");
}

func testTheGlossaryIsReachedFromWhereverTheChapterIs() {
    testing.assertEqual(linkTo("index.md", "glossary.md"), "glossary.md");
    testing.assertEqual(linkTo("guide/syntax.md", "glossary.md"), "../glossary.md");
    testing.assertEqual(linkTo("a/b/c.md", "ref/glossary.md"), "../../ref/glossary.md");
    testing.assertEqual(linkTo("guide/a.md", "guide/glossary.md"), "glossary.md");
}

func testAliasesPointAtTheTermTheyName() {
    def root as string init fs.makeTempDir(os.tempDir(), "glossary-");
    def file as string init path.join($root, "terms.toml");
    fs.writeString($file, "[terms]\n\"outlines\" = \"outline\"\n\"indexes\" = \"search index\"\n");
    def found as list of Term init aliasesIn($file, termsIn(glossaryChapter(), 2));
    testing.assertEqual(len($found), 2);
    testing.assertEqual($found[0].word, "indexes");
    testing.assertEqual($found[0].anchor, "search-index");
    fs.removeAll($root);
}

func anAliasForNothing() {
    def root as string init fs.makeTempDir(os.tempDir(), "glossary-");
    def file as string init path.join($root, "terms.toml");
    fs.writeString($file, "[terms]\n\"outlines\" = \"nothing at all\"\n");
    try {
        aliasesIn($file, termsIn(glossaryChapter(), 2));
    } catch (e) {
        fs.removeAll($root);
        throw $e;
    }
}

func testAnAliasForATermTheGlossaryDoesNotDefineIsRefused() {
    testing.assertThrows("anAliasForNothing", "plugin");
}

func testRunLinksEveryChapterButTheGlossary() {
    def chapters as string init chapter("glossary.md", glossaryChapter()) + "," +
        chapter("index.md", "The outline of the book.\n") + "," +
        chapter("guide/deep.md", "A search index lives here.\n");
    testing.assertEqual(run(requestFor($chapters, '{}')), 0);
}

func testTheReplyCarriesOnlyWhatChanged() {
    def chapters as string init chapter("glossary.md", glossaryChapter()) + "," +
        chapter("index.md", "The outline of the book.\n") + "," +
        chapter("quiet.md", "Nothing to see.\n");
    def out as string init replyFor(json.decode(requestFor($chapters, '{}')));
    testing.assertContains($out, "index.md");
    testing.assertFalse(strings.contains($out, "quiet.md"));
    testing.assertContains($out, "[outline](glossary.md#outline)");
    # Decoded rather than only searched: a reply that is the right text and the
    # wrong shape - a brace short - fails the build with a parse error and
    # nothing about this plugin in it.
    def reply as json.Value init json.decode($out);
    testing.assertEqual(json.asInt($reply, "/api"), 1);
    testing.assertEqual(json.length($reply, "/chapters"), 1);
    testing.assertEqual(json.asString($reply, "/chapters/0/src"), "index.md");
}

func testAChapterDeeperInTheBookLinksBackUp() {
    def chapters as string init chapter("glossary.md", glossaryChapter()) + "," +
        chapter("guide/deep.md", "A search index lives here.\n");
    def out as string init replyFor(json.decode(requestFor($chapters, '{}')));
    testing.assertContains($out, "(../glossary.md#search-index)");
}

func aBookWithNoGlossary() {
    replyFor(json.decode(requestFor(chapter("index.md", "no glossary here"), '{}')));
}

func testABookWithNoGlossaryChapterIsRefused() {
    testing.assertThrows("aBookWithNoGlossary", "plugin");
}

func testRunRefusesARequestItCannotAnswer() {
    def req as string init requestFor(chapter("glossary.md", glossaryChapter()), '{}');
    testing.assertEqual(run(strings.replace($req, '"api":1', '"api":2')), 1);
    testing.assertEqual(run(strings.replace($req, '"preprocessor"', '"renderer"')), 1);
    testing.assertEqual(run(""), 1);
}
