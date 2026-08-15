# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `keywords.j`, run by `jennifer test src/keywords_test.j`.
 *
 * The scoring is the module's whole argument - a word in the title outranks
 * eight mentions in prose - so the tests assert the *ordering* the weights
 * produce rather than the weights themselves, which is what would actually be
 * wrong if a weight were changed by accident.
 *
 * The rest is the two rules that keep the tag honest: a term is anchored at both
 * ends so `join,` and `(spawn` never appear, and the ranking breaks ties
 * alphabetically so the same page produces the same tag on every build. That
 * last one is part of the byte-identical-output promise, not a nicety.
 * @module keywords_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
# `content` is not imported here: an overlay shares the module's own imports, and
# binding the alias a second time is an error.
use testing;
use lists;
use maps;
use strings;

# A page built by hand, so a test can put a term in exactly one place and see
# what that placement is worth.
func page(title as string, headings as list of content.Heading, body as string, html as string) {
    def sections as list of content.Section;
    $sections[] = content.Section{anchor: "", heading: "", text: $body};
    return content.Rendered{html: $html, title: $title, headings: $headings, sections: $sections};
}

func h(level as int, text as string) {
    return content.Heading{level: $level, text: $text, id: "x"};
}

func plain(title as string, body as string) {
    def none as list of content.Heading;
    return page($title, $none, $body, "");
}

# --- unescape --------------------------------------------------------

# Without this the tag picks up the entity *names*: a code span holding `a&b`
# arrives as `a&amp;b` and `amp` scores as though the page were about it.
func testUnescapeReversesTheFiveReferences() {
    testing.assertEqual(unescape("a&lt;b"), "a<b");
    testing.assertEqual(unescape("a&gt;b"), "a>b");
    testing.assertEqual(unescape("a&quot;b"), 'a"b');
    testing.assertEqual(unescape("a&#39;b"), "a'b");
    testing.assertEqual(unescape("a&amp;b"), "a&b");
}

# `&amp;` goes last so a literal `&amp;amp;` cannot be unescaped twice.
func testUnescapeDoesNotDoubleUnescape() {
    testing.assertEqual(unescape("&amp;amp;"), "&amp;");
    testing.assertEqual(unescape("&amp;lt;"), "&lt;");
}

# --- scoreable -------------------------------------------------------

func testScoreableNeedsLength() {
    testing.assertFalse(scoreable("a"));
    testing.assertFalse(scoreable("ab"));
    testing.assertTrue(scoreable("abc"));
}

# A term that is only digits and separators - a version number, a page count -
# names nothing on its own.
func testScoreableRejectsBareNumbers() {
    testing.assertFalse(scoreable("1234"));
    testing.assertFalse(scoreable("0.24.0"));
    testing.assertFalse(scoreable("1-2-3"));
    testing.assertTrue(scoreable("0x1f"));
    testing.assertTrue(scoreable("utf-8"));
}

# --- terms -----------------------------------------------------------

# Anchoring both ends is what keeps `join,` and `(spawn` and `module.` out
# without a separate trimming pass.
func testTermsAnchorAtBothEnds() {
    testing.assertTrue(lists.contains(terms("call join, then spawn"), "join"));
    testing.assertFalse(lists.contains(terms("call join, then spawn"), "join,"));
    testing.assertTrue(lists.contains(terms("(spawn) and module."), "spawn"));
    testing.assertFalse(lists.contains(terms("(spawn) and module."), "module."));
}

func testTermsKeepInnerSeparators() {
    testing.assertTrue(lists.contains(terms("read the utf-8 spec"), "utf-8"));
    testing.assertTrue(lists.contains(terms("call io.printf now"), "io.printf"));
    testing.assertTrue(lists.contains(terms("a snake_case name"), "snake_case"));
}

func testTermsLowercases() {
    testing.assertTrue(lists.contains(terms("Spawn And Task"), "spawn"));
    testing.assertFalse(lists.contains(terms("Spawn And Task"), "Spawn"));
}

# --- stopSet ---------------------------------------------------------

func testStopSetCarriesTheBuiltInList() {
    def none as list of string;
    def stops as map of string to int init stopSet($none);
    testing.assertTrue(maps.has($stops, "the"));
    testing.assertTrue(maps.has($stops, "and"));
    testing.assertFalse(maps.has($stops, "spawn"));
}

# The built-in list can only know about English. A book knows what is furniture
# in its own subject - the keywords of the language it documents, its own name on
# every page - and those describe every chapter equally, so they describe none.
func testStopSetTakesTheBooksOwnAdditions() {
    def stops as map of string to int init stopSet(["Spawn", "  task  ", ""]);
    testing.assertTrue(maps.has($stops, "spawn"));
    testing.assertTrue(maps.has($stops, "task"));
    testing.assertFalse(maps.has($stops, ""));
}

# --- foldPlurals -----------------------------------------------------

# Only an exact trailing `s`, and only when the singular is a term the page
# actually used - cheap and safe where a stemmer would be neither.
func testFoldPluralsMergesWhenBothFormsAppear() {
    def scores as map of string to int init {"module": 3, "modules": 2};
    def folded as map of string to int init foldPlurals($scores);
    testing.assertEqual($folded["module"], 5);
    testing.assertFalse(maps.has($folded, "modules"));
}

func testFoldPluralsLeavesALonePluralAlone() {
    def scores as map of string to int init {"strings": 4};
    def folded as map of string to int init foldPlurals($scores);
    testing.assertEqual($folded["strings"], 4);
    testing.assertFalse(maps.has($folded, "string"));
}

func testFoldPluralsWillNotStripTheTermToNothing() {
    def scores as map of string to int init {"as": 1, "ass": 2};
    def folded as map of string to int init foldPlurals($scores);
    testing.assertTrue(maps.has($folded, "ass"));
}

# --- ranked ----------------------------------------------------------

func testRankedPutsTheHighestScoreFirst() {
    def scores as map of string to int init {"low": 1, "high": 9, "middle": 5};
    def order as list of string init ranked($scores);
    testing.assertEqual($order[0], "high");
    testing.assertEqual($order[1], "middle");
    testing.assertEqual($order[2], "low");
}

# The tie-break is what makes a keyword tag reproducible, which the byte-identical
# output promise depends on: chapters render in parallel and a map has no order.
func testRankedBreaksTiesAlphabetically() {
    def scores as map of string to int init {"zebra": 5, "alpha": 5, "mango": 5};
    def order as list of string init ranked($scores);
    testing.assertEqual($order[0], "alpha");
    testing.assertEqual($order[1], "mango");
    testing.assertEqual($order[2], "zebra");
}

func testRankedIsStableAcrossCalls() {
    def scores as map of string to int init {"a-term": 2, "b-term": 2, "c-term": 2, "d-term": 2};
    testing.assertEqual(strings.join(ranked($scores), ","), strings.join(ranked($scores), ","));
}

# --- extract: the weighting ------------------------------------------

# The module's central claim: a word in the title outranks eight mentions in
# prose. Asserted as an ordering rather than as a number, because the ordering is
# what a changed weight would actually break.
func testATitleWordOutranksRepeatedProse() {
    def r as content.Rendered init plain(
        "Concurrency",
        "spawn spawn spawn spawn spawn spawn spawn");
    def out as list of string init extract($r, 10, []);
    testing.assertEqual($out[0], "concurrency");
}

func testAHeadingOutranksProse() {
    def r as content.Rendered init page("", [h(2, "Marshalling")], "buffer buffer", "");
    def out as list of string init extract($r, 10, []);
    testing.assertEqual($out[0], "marshalling");
}

func testALevelTwoHeadingOutranksADeeperOne() {
    def r as content.Rendered init page("T", [h(2, "shallow"), h(3, "deeper")], "", "");
    def out as list of string init extract($r, 10, []);
    testing.assertEqual($out[0], "shallow");
}

# A level-one heading is the page title, already scored as such; counting it
# again would double every title word.
func testALevelOneHeadingIsNotCountedTwice() {
    def withH1 as content.Rendered init page("Subject", [h(1, "Subject")], "", "");
    def withoutH1 as content.Rendered init plain("Subject", "");
    testing.assertEqual(
        strings.join(extract($withH1, 10, []), ","),
        strings.join(extract($withoutH1, 10, []), ","));
}

func testCodeSpansAreRead() {
    def r as content.Rendered init page("T", [], "", "<p>see <code>marshalling</code></p>");
    testing.assertTrue(lists.contains(extract($r, 10, []), "marshalling"));
}

func testCodeSpansAreUnescapedBeforeScoring() {
    def r as content.Rendered init page("T", [], "", "<code>alpha&amp;beta</code>");
    def out as list of string init extract($r, 10, []);
    testing.assertFalse(lists.contains($out, "amp"));
}

# --- extract: the filters --------------------------------------------

func testExtractDropsStopWords() {
    def r as content.Rendered init plain("The And Of", "the and of but with");
    testing.assertEqual(len(extract($r, 10, [])), 0);
}

func testExtractHonoursTheBooksStopWords() {
    def r as content.Rendered init plain("Grimoire", "grimoire builds books");
    testing.assertTrue(lists.contains(extract($r, 10, []), "grimoire"));
    testing.assertFalse(lists.contains(extract($r, 10, ["grimoire"]), "grimoire"));
}

func testExtractHonoursTheLimit() {
    def r as content.Rendered init plain("", "alpha beta gamma delta epsilon zeta");
    testing.assertEqual(len(extract($r, 3, [])), 3);
    testing.assertEqual(len(extract($r, 0, [])), 0);
}

func testExtractOfAnEmptyPageIsEmpty() {
    testing.assertEqual(len(extract(plain("", ""), 10, [])), 0);
}

# --- line ------------------------------------------------------------

func testLineJoinsWithCommas() {
    def r as content.Rendered init plain("Concurrency", "spawn and channel");
    def value as string init line($r, 10, []);
    testing.assertContains($value, "concurrency");
    testing.assertContains($value, ", ");
}

func testLineOfAnEmptyPageIsEmpty() {
    testing.assertEqual(line(plain("", ""), 10, []), "");
}

func testLineAgreesWithExtract() {
    def r as content.Rendered init plain("Modules", "module module spawn");
    testing.assertEqual(line($r, 5, []), strings.join(extract($r, 5, []), ", "));
}
