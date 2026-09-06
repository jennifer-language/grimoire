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
 *
 * Two of the tests below are a bug report in the shape of an assertion. A German
 * book tagged its chapters `und, die, das, ist, der` because the stop list was
 * English, and no book in any accented language had whole words to tag at all,
 * because the term pattern was `[a-z0-9]`. Both are named after what went wrong.
 * This file is ASCII like the rest of the repository, so the words that need an
 * umlaut are spelled with escapes and the comment above them says which.
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

# Everything below the CJK boundary separates its words, so a Cyrillic or Greek
# term is a term - the two here are Russian `dannye` and Greek `logos`. At or
# above it a run of letters is a clause rather than a word, and splitting it
# needs a segmenter Grimoire does not have; the two rejected here are Japanese.
func testScoreableSkipsTheUnsegmentedScripts() {
    testing.assertTrue(scoreable("\u0434\u0430\u043d\u043d\u044b\u0435"));
    testing.assertTrue(scoreable("\u03bb\u03cc\u03b3\u03bf\u03c2"));
    testing.assertFalse(scoreable("\u65e5\u672c\u8a9e"));
    testing.assertFalse(scoreable("\u3059\u3054\u3044\u3067\u3059"));
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

# `[a-z]` does not match an umlaut, so a word carrying one used to arrive as two
# fragments. The escape spells the German for compensation, `Verg` + u-umlaut +
# `tung`: nine runes, one term, and not the `verg` and `tung` it scored as
# before.
func testTermsKeepAnAccentedWordWhole() {
    def word as string init "Verg\u00fctung";
    testing.assertEqual(len($word), 9);
    testing.assertTrue(lists.contains(terms($word), strings.lower($word)));
    testing.assertFalse(lists.contains(terms($word), "verg"));
    testing.assertFalse(lists.contains(terms($word), "tung"));
}

# The scripts that separate their words all pass through the same pattern. These
# are Russian `dannye`, Greek `logos`, and French `cafe` with its accent.
func testTermsReadTheOtherAlphabets() {
    def ru as string init "\u0434\u0430\u043d\u043d\u044b\u0435";
    def gr as string init "\u03bb\u03cc\u03b3\u03bf\u03c2";
    def sample as string init $ru + " " + $gr + " caf\u00e9";
    testing.assertEqual(len(terms($sample)), 3);
    testing.assertTrue(lists.contains(terms($sample), "caf\u00e9"));
}

# --- stopSet ---------------------------------------------------------

func testStopSetCarriesTheBuiltInList() {
    def none as list of string;
    def stops as map of string to int init stopSet("en", $none);
    testing.assertTrue(maps.has($stops, "the"));
    testing.assertTrue(maps.has($stops, "and"));
    testing.assertFalse(maps.has($stops, "spawn"));
}

# The built-in list can only know about English. A book knows what is furniture
# in its own subject - the keywords of the language it documents, its own name on
# every page - and those describe every chapter equally, so they describe none.
func testStopSetTakesTheBooksOwnAdditions() {
    def stops as map of string to int init stopSet("en", ["Spawn", "  task  ", ""]);
    testing.assertTrue(maps.has($stops, "spawn"));
    testing.assertTrue(maps.has($stops, "task"));
    testing.assertFalse(maps.has($stops, ""));
}

# The book's language adds a second list on top of the English one, which every
# book gets because technical writing quotes identifiers whatever it is written
# in.
func testStopSetAddsTheBooksOwnLanguage() {
    def none as list of string;
    def de as map of string to int init stopSet("de", $none);
    testing.assertTrue(maps.has($de, "und"));
    testing.assertTrue(maps.has($de, "der"));
    testing.assertTrue(maps.has($de, "the"));
    testing.assertFalse(maps.has(stopSet("en", $none), "und"));
}

# `de-AT` is German; an unknown tag is not an error and keeps the English list.
func testStopSetReadsTheTagLoosely() {
    def none as list of string;
    testing.assertTrue(maps.has(stopSet("de-AT", $none), "und"));
    testing.assertTrue(maps.has(stopSet("xx", $none), "the"));
    testing.assertFalse(maps.has(stopSet("xx", $none), "und"));
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
    def out as list of string init extract($r, 10, "en", []);
    testing.assertEqual($out[0], "concurrency");
}

func testAHeadingOutranksProse() {
    def r as content.Rendered init page("", [h(2, "Marshalling")], "buffer buffer", "");
    def out as list of string init extract($r, 10, "en", []);
    testing.assertEqual($out[0], "marshalling");
}

func testALevelTwoHeadingOutranksADeeperOne() {
    def r as content.Rendered init page("T", [h(2, "shallow"), h(3, "deeper")], "", "");
    def out as list of string init extract($r, 10, "en", []);
    testing.assertEqual($out[0], "shallow");
}

# A level-one heading is the page title, already scored as such; counting it
# again would double every title word.
func testALevelOneHeadingIsNotCountedTwice() {
    def withH1 as content.Rendered init page("Subject", [h(1, "Subject")], "", "");
    def withoutH1 as content.Rendered init plain("Subject", "");
    testing.assertEqual(
        strings.join(extract($withH1, 10, "en", []), ","),
        strings.join(extract($withoutH1, 10, "en", []), ","));
}

func testCodeSpansAreRead() {
    def r as content.Rendered init page("T", [], "", "<p>see <code>marshalling</code></p>");
    testing.assertTrue(lists.contains(extract($r, 10, "en", []), "marshalling"));
}

func testCodeSpansAreUnescapedBeforeScoring() {
    def r as content.Rendered init page("T", [], "", "<code>alpha&amp;beta</code>");
    def out as list of string init extract($r, 10, "en", []);
    testing.assertFalse(lists.contains($out, "amp"));
}

# --- extract: the filters --------------------------------------------

func testExtractDropsStopWords() {
    def r as content.Rendered init plain("The And Of", "the and of but with");
    testing.assertEqual(len(extract($r, 10, "en", [])), 0);
}

func testExtractHonoursTheBooksStopWords() {
    def r as content.Rendered init plain("Grimoire", "grimoire builds books");
    testing.assertTrue(lists.contains(extract($r, 10, "en", []), "grimoire"));
    testing.assertFalse(lists.contains(extract($r, 10, "en", ["grimoire"]), "grimoire"));
}

func testExtractHonoursTheLimit() {
    def r as content.Rendered init plain("", "alpha beta gamma delta epsilon zeta");
    testing.assertEqual(len(extract($r, 3, "en", [])), 3);
    testing.assertEqual(len(extract($r, 0, "en", [])), 0);
}

# The report this came from: every keyword in the tag was a German function word
# and the page's subject was nowhere in it.
func testExtractOfAGermanPageDropsTheGermanFunctionWords() {
    def r as content.Rendered init plain(
        "Steuerberatung",
        "Die Familie und das Guthaben: der Zugang ist nicht eine Ausgabe, oder?");
    def out as list of string init extract($r, 10, "de", []);
    testing.assertEqual($out[0], "steuerberatung");
    for (def word in ["und", "die", "das", "der", "ist", "eine", "oder", "nicht"]) {
        testing.assertFalse(lists.contains($out, $word));
    }
    testing.assertTrue(lists.contains($out, "familie"));
    testing.assertTrue(lists.contains($out, "guthaben"));
}

# The same page in a book that never said what language it is in keeps them,
# which is what makes the list - rather than the length floor - the thing doing
# the work. Three letters is a word in every language; `und` is not a short word,
# it is a common one.
func testTheSamePageWithoutTheLanguageKeepsThem() {
    def r as content.Rendered init plain(
        "Steuerberatung",
        "Die Familie und das Guthaben: der Zugang ist nicht eine Ausgabe, oder?");
    def out as list of string init extract($r, 20, "en", []);
    for (def word in ["und", "die", "das", "der", "ist", "eine", "oder", "nicht"]) {
        testing.assertTrue(lists.contains($out, $word));
    }
}

# A Japanese page keeps the keywords it has always had - its title, and the
# identifiers in its code spans - rather than gaining a meta tag full of clauses.
# The body is `nihongo wa sugoi` with no spaces in it, as the script is written.
func testExtractSkipsUnsegmentedProse() {
    def r as content.Rendered init plain("grimoire", "\u65e5\u672c\u8a9e\u306f\u3059\u3054\u3044");
    def out as list of string init extract($r, 10, "ja", []);
    testing.assertEqual(len($out), 1);
    testing.assertEqual($out[0], "grimoire");
}

func testExtractOfAnEmptyPageIsEmpty() {
    testing.assertEqual(len(extract(plain("", ""), 10, "en", [])), 0);
}

# --- line ------------------------------------------------------------

func testLineJoinsWithCommas() {
    def r as content.Rendered init plain("Concurrency", "spawn and channel");
    def value as string init line($r, 10, "en", []);
    testing.assertContains($value, "concurrency");
    testing.assertContains($value, ", ");
}

func testLineOfAnEmptyPageIsEmpty() {
    testing.assertEqual(line(plain("", ""), 10, "en", []), "");
}

func testLineAgreesWithExtract() {
    def r as content.Rendered init plain("Modules", "module module spawn");
    testing.assertEqual(line($r, 5, "en", []), strings.join(extract($r, 5, "en", []), ", "));
}

# --- ranked: the padded sort key -------------------------------------
#
# The key is `SCORE_SCALE - score` as text, which sorts numerically only while
# every inverted score has the same width. A score at or above the scale would go
# negative, and negative keys sort by their digits - "-9" before "-95" - putting
# the smaller score first. Clamping keeps the invariant true by construction, so
# a weight raised later cannot quietly reorder a page's keywords.

func testRankedOrdersByScoreThenAlphabetically() {
    def scores as map of string to int init {"low": 1, "high": 90, "also": 90};
    def out as list of string init ranked($scores);
    testing.assertEqual($out[0], "also");
    testing.assertEqual($out[1], "high");
    testing.assertEqual($out[2], "low");
}

func testRankedKeepsAScoreAtTheScaleOnTop() {
    def scores as map of string to int init {"ordinary": 500, "huge": SCORE_SCALE};
    def out as list of string init ranked($scores);
    testing.assertEqual($out[0], "huge");
    testing.assertEqual($out[1], "ordinary");
}

# Two terms past the scale clamp to the same key, so they tie and break
# alphabetically rather than by the digits of a negative number.
func testRankedTiesTwoScoresAboveTheScale() {
    def scores as map of string to int init {
        "beta": SCORE_SCALE + 9,
        "alpha": SCORE_SCALE + 95,
        "small": 1
    };
    def out as list of string init ranked($scores);
    testing.assertEqual($out[0], "alpha");
    testing.assertEqual($out[1], "beta");
    testing.assertEqual($out[2], "small");
}
