# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `pdfbook.j`, run by `jennifer test src/pdfbook_test.j`.
 *
 * The printed book is assembled by rewriting Markdown as text before anything
 * parses it, and text rewriting is where a book quietly comes out wrong rather
 * than failing. Three groups carry most of the weight.
 *
 * Sanitising, because the standard-14 fonts encode WinAnsi and a character
 * outside it reaches the page as `?` unless `TRANSLITERATIONS` has a reading for
 * it. `render` cannot report this - a question mark is a perfectly valid glyph.
 *
 * Fence tracking, because every transform has to know where the fences are.
 * A heading inside a code block is content, and a fence written inside a
 * blockquote carries the quote marker on every line including the fences: miss
 * that and the code inside gets rewritten as if it were prose.
 *
 * And the cover, where `mplx <jennifer@mplx.dev>` parses as an email autolink and
 * loses its brackets unless the angle brackets are turned into character
 * references first.
 * @module pdfbook_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use strings;

func book() {
    def c as config.Config init config.defaults();
    $c.title = "A Book";
    return $c;
}

# --- encodable and the transliterations ------------------------------

func testEncodableAcceptsWhatTheFontsCarry() {
    testing.assertTrue(encodable("plain ASCII"));
    testing.assertTrue(encodable("accented: aeiou"));
    testing.assertTrue(encodable(""));
}

func testInvisibleCharactersAreDropped() {
    testing.assertEqual(asciiFor(convert.fromCodepoint(0xFE0F)), "");
    testing.assertEqual(asciiFor(convert.fromCodepoint(0x200B)), "");
    testing.assertEqual(asciiFor(convert.fromCodepoint(0x200D)), "");
    testing.assertEqual(asciiFor(convert.fromCodepoint(0xFEFF)), "");
}

# A visible character with no reading gets a question mark, which is a marker
# rather than a silent hole.
func testAnUnknownCharacterBecomesAQuestionMark() {
    testing.assertEqual(asciiFor(convert.fromCodepoint(0x1F600)), "?");
}

# --- sanitize --------------------------------------------------------

func testSanitizeLeavesEncodableTextAlone() {
    testing.assertEqual(sanitize("Ordinary prose."), "Ordinary prose.");
    testing.assertEqual(sanitize(""), "");
}

# The reading is what the arrow *said*; the module's own fallback would print a
# question mark instead.
func testSanitizeTransliteratesRatherThanDropping() {
    testing.assertEqual(sanitize(convert.fromCodepoint(0x2192)), "->");
    testing.assertEqual(sanitize(convert.fromCodepoint(0x2764)), "<3");
    testing.assertEqual(sanitize(convert.fromCodepoint(0x03B1)), "alpha");
}

# Only what the codec cannot carry is rewritten, and WinAnsi carries more than
# the repository's own punctuation rule allows: an ellipsis, the curly quotes,
# both dashes and a bullet all encode, so they reach the page as themselves. The
# readings `TRANSLITERATIONS` holds for those are unreachable - harmless, but not
# doing anything either. A book's own content is where they turn up, and it is
# right that they print as written.
func testSanitizeLeavesWinAnsiPunctuationAsItIs() {
    for (def cp in [0x2026, 0x2018, 0x2019, 0x201C, 0x201D, 0x2013, 0x2014, 0x2022]) {
        def ch as string init convert.fromCodepoint($cp);
        testing.assertEqual(sanitize($ch), $ch);
    }
}

func testSanitizeKeepsLineStructure() {
    def out as string init sanitize("one\n" + convert.fromCodepoint(0x2192) + "\nthree");
    testing.assertEqual(len(strings.split($out, "\n")), 3);
    testing.assertEqual(strings.split($out, "\n")[1], "->");
}

func testSanitizeKeepsTheEncodableCharactersAroundIt() {
    def arrow as string init convert.fromCodepoint(0x2192);
    testing.assertEqual(sanitize("a" + $arrow + "b"), "a->b");
}

# Every string on the cover page goes through this, so a title carrying a
# character the fonts cannot draw must not abort the render.
func testSanitizeNeverThrows() {
    testing.assertNotEqual(sanitize(convert.fromCodepoint(0x1F600)), "");
    testing.assertNotEqual(sanitize("mixed " + convert.fromCodepoint(0x4E2D)), "");
}

# --- quotePrefix and fenceAt -----------------------------------------

func testQuotePrefixFindsTheMarkers() {
    testing.assertEqual(quotePrefix("> quoted"), "> ");
    testing.assertEqual(quotePrefix("> > deep"), "> > ");
}

func testQuotePrefixIsEmptyWithoutAMarker() {
    testing.assertEqual(quotePrefix("plain"), "");
    testing.assertEqual(quotePrefix("   indented"), "");
    testing.assertEqual(quotePrefix(""), "");
}

func testFenceAtSpotsBothFenceCharacters() {
    testing.assertTrue(fenceAt("```"));
    testing.assertTrue(fenceAt("```sh"));
    testing.assertTrue(fenceAt("~~~"));
    testing.assertFalse(fenceAt("plain"));
    testing.assertFalse(fenceAt("`inline`"));
}

# A fenced block written inside a blockquote carries the marker on every line,
# the fences included. Miss that and the code inside is rewritten as prose.
func testFenceAtSeesThroughABlockquote() {
    testing.assertTrue(fenceAt("> ```"));
    testing.assertTrue(fenceAt("> > ```sh"));
}

# --- headingLevel ----------------------------------------------------

func testHeadingLevelCountsHashes() {
    testing.assertEqual(headingLevel("# One"), 1);
    testing.assertEqual(headingLevel("### Three"), 3);
    testing.assertEqual(headingLevel("###### Six"), 6);
}

func testHeadingLevelRejectsNonHeadings() {
    testing.assertEqual(headingLevel("####### Seven"), 0);
    testing.assertEqual(headingLevel("#NoSpace"), 0);
    testing.assertEqual(headingLevel("plain"), 0);
    testing.assertEqual(headingLevel(""), 0);
}

func testABareHashIsAHeading() {
    testing.assertEqual(headingLevel("#"), 1);
}

# --- printLine -------------------------------------------------------

# A cross-reference to another chapter is not clickable on paper, so it reads as
# its label alone.
func testPrintLineDropsAnInternalTarget() {
    testing.assertEqual(printLine("see [the guide](guide/x.md)"), "see the guide");
    testing.assertEqual(printLine("see [the guide](guide/x.md#anchor)"), "see the guide");
    testing.assertEqual(printLine("see [above](#anchor)"), "see above");
}

# An external URL is worth keeping in parentheses, because the URL is the only
# way a reader on paper can follow it.
func testPrintLineKeepsAnExternalUrl() {
    testing.assertEqual(
        printLine("see [the site](https://example.com)"),
        "see the site (https://example.com)");
}

func testPrintLineHandlesTitlesAndImages() {
    testing.assertEqual(printLine('see [x](y.md "a title")'), "see x");
    testing.assertEqual(printLine("![alt](diagram.png)"), "alt (diagram.png)");
}

func testPrintLineLeavesOrdinaryProseAlone() {
    testing.assertEqual(printLine("no links here"), "no links here");
    testing.assertEqual(printLine("brackets [but] no target"), "brackets [but] no target");
    testing.assertEqual(printLine(""), "");
}

func testPrintLineRewritesEveryLinkOnALine() {
    testing.assertEqual(printLine("[a](a.md) and [b](b.md)"), "a and b");
}

# --- prepare ---------------------------------------------------------

func testPrepareDemotesHeadings() {
    def out as string init prepare("# Title\n\n## Section\n", 1);
    testing.assertContains($out, "## Title");
    testing.assertContains($out, "### Section");
}

func testPrepareDemotesNothingAtZero() {
    testing.assertContains(prepare("# Title\n", 0), "# Title");
}

func testPrepareClampsAtSix() {
    testing.assertContains(prepare("###### Deep\n", 1), "###### Deep");
}

# Headings and rules inside a fence are content, not structure.
func testPrepareLeavesFencedContentAlone() {
    def src as string init "# Real\n\n```sh\n# not a heading\n[not](a.md) link\n```\n";
    def out as string init prepare($src, 1);
    testing.assertContains($out, "## Real");
    testing.assertContains($out, "# not a heading");
    testing.assertContains($out, "[not](a.md) link");
}

# "Exactly as written" is load-bearing: an indented continuation that loses its
# indent stops belonging to its list item and becomes a stranded paragraph.
func testPrepareKeepsIndentation() {
    def src as string init "- item\n  continuation\n    deeper\n";
    def out as string init prepare($src, 0);
    testing.assertContains($out, "  continuation");
    testing.assertContains($out, "    deeper");
}

func testPrepareResolvesLinksOutsideFences() {
    testing.assertContains(prepare("see [x](y.md)\n", 0), "see x");
}

func testPrepareSanitisesFirst() {
    testing.assertContains(prepare(convert.fromCodepoint(0x2192) + " onward\n", 0), "-> onward");
}

# --- hasTitle --------------------------------------------------------

func testHasTitleFindsALevelOne() {
    testing.assertTrue(hasTitle("# The Chapter\n\nbody\n"));
    testing.assertTrue(hasTitle("intro\n\n# Later\n"));
}

func testHasTitleIgnoresDeeperHeadings() {
    testing.assertFalse(hasTitle("## Only a two\n"));
    testing.assertFalse(hasTitle("body with no headings\n"));
    testing.assertFalse(hasTitle(""));
}

# A `#` comment on the first line of a shell block is not a chapter title, and a
# chapter that appears to have one gets no title inserted - so it lands in the
# printed book unlabelled.
func testHasTitleIgnoresAHashInsideAFence() {
    testing.assertFalse(hasTitle("```sh\n# echo hi\n```\n"));
    testing.assertTrue(hasTitle("```sh\n# echo hi\n```\n\n# Real Title\n"));
}

# --- coverText -------------------------------------------------------

# `mplx <jennifer@mplx.dev>` is the conventional way to write a name and an
# address, and it is also a CommonMark email autolink: left alone the brackets
# vanish and the title page reads `mplx jennifer@mplx.dev`.
func testCoverTextProtectsAnEmailInAngleBrackets() {
    def out as string init coverText("mplx <jennifer@mplx.dev>");
    testing.assertEqual($out, "mplx &lt;jennifer@mplx.dev&gt;");
}

# `&` goes first, or escaping it afterwards would corrupt the `&lt;` just written.
func testCoverTextEscapesAmpersandFirst() {
    testing.assertEqual(coverText("a & <b>"), "a &amp; &lt;b&gt;");
    testing.assertEqual(coverText("&amp;"), "&amp;amp;");
}

func testCoverTextLeavesOrdinaryTextAlone() {
    testing.assertEqual(coverText("An Ordinary Title"), "An Ordinary Title");
}

# --- cover -----------------------------------------------------------

func testCoverCarriesTheTitle() {
    testing.assertContains(cover(book()), "# A Book");
}

func testCoverOmitsWhatIsNotConfigured() {
    def out as string init cover(book());
    testing.assertFalse(strings.contains($out, "*"));
    testing.assertFalse(strings.contains($out, "**"));
}

func testCoverCarriesDescriptionAndAuthors() {
    def c as config.Config init book();
    $c.description = "What it is about";
    $c.authors = ["Ada"];
    def out as string init cover($c);
    testing.assertContains($out, "*What it is about*");
    testing.assertContains($out, "**Written by Ada**");
}

# The build date, and only the build date: the tool credit belongs in the
# document metadata, not on the reader's title page.
func testCoverCarriesNoToolCredit() {
    def out as string init cover(book());
    testing.assertFalse(strings.contains($out, "Grimoire"));
    testing.assertFalse(strings.contains($out, "grimoire"));
}

# --- excluded --------------------------------------------------------

func testNothingIsExcludedByDefault() {
    testing.assertFalse(excluded(book(), "index.md"));
}

func testAnExactPathIsExcluded() {
    def c as config.Config init book();
    $c.pdfExclude = ["technical/coverage.md"];
    testing.assertTrue(excluded($c, "technical/coverage.md"));
    testing.assertFalse(excluded($c, "technical/other.md"));
}

# A pattern ending in `/` excludes everything beneath it - the case this exists
# for is a generated API reference worth having on the site and not on paper.
func testATrailingSlashExcludesADirectory() {
    def c as config.Config init book();
    $c.pdfExclude = ["api/"];
    testing.assertTrue(excluded($c, "api/index.md"));
    testing.assertTrue(excluded($c, "api/deep/x.md"));
    testing.assertFalse(excluded($c, "apiary.md"));
    testing.assertFalse(excluded($c, "guide/api/x.md"));
}

func testExcludeNormalisesSeparators() {
    def c as config.Config init book();
    $c.pdfExclude = ["api/"];
    testing.assertTrue(excluded($c, "api\\x.md"));
}

func testAnEmptyPatternExcludesNothing() {
    def c as config.Config init book();
    $c.pdfExclude = ["", "api/"];
    testing.assertFalse(excluded($c, "index.md"));
}

# --- footerText ------------------------------------------------------

func testFooterTextFillsTheSlots() {
    def c as config.Config init book();
    # A raw string: the slots are template placeholders, not Jennifer
    # interpolation.
    $c.pdfFooterLeft = 'My Book {version} {commit}';
    def out as string init footerText($c);
    testing.assertFalse(strings.contains($out, '{version}'));
    testing.assertFalse(strings.contains($out, '{commit}'));
    testing.assertContains($out, "My Book");
}

# Exactly one of the two slots is ever filled, so the result is squeezed to close
# the gap the empty one leaves.
func testFooterTextLeavesNoDoubleSpace() {
    def c as config.Config init book();
    # A raw string: the slots are template placeholders, not Jennifer
    # interpolation.
    $c.pdfFooterLeft = 'My Book {version} {commit}';
    testing.assertFalse(strings.contains(footerText($c), "  "));
}

func testAnEmptyTemplateStaysEmpty() {
    def c as config.Config init book();
    $c.pdfFooterLeft = "";
    testing.assertEqual(footerText($c), "");
}

# --- pdfOptions ------------------------------------------------------

func testPdfOptionsFollowThePaperSize() {
    def c as config.Config init book();
    $c.pdfPaper = "a4";
    def a4 as int init pdfOptions($c).pageWidth;
    $c.pdfPaper = "letter";
    testing.assertNotEqual(pdfOptions($c).pageWidth, $a4);
}

func testPdfOptionsFollowTheBookmarkLevel() {
    def c as config.Config init book();
    $c.pdfBookmarkLevel = 2;
    testing.assertEqual(pdfOptions($c).bookmarkLevel, 2);
    $c.pdfBookmarkLevel = 0;
    testing.assertEqual(pdfOptions($c).bookmarkLevel, 0);
}

# A visible marker beats a silent hole for anything `sanitize` did not already
# reach.
func testPdfOptionsMarkAnUnencodableCharacter() {
    testing.assertEqual(pdfOptions(book()).unencodable, "?");
}
