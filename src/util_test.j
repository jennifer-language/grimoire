# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `util.j`, run by `jennifer test src/util_test.j`.
 *
 * The cases here are the ones the docblocks in `util.j` argue for: the anchor
 * shape that a book migrated from mdBook depends on, the `README` fold, and the
 * word-boundary rule in `truncate`. Each of those is a decision rather than an
 * obvious behaviour, which is exactly what a test is for.
 * @module util_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use maps;

# --- isExternal ------------------------------------------------------

func testIsExternalSpotsSchemes() {
    testing.assertTrue(isExternal("https://example.com"));
    testing.assertTrue(isExternal("http://example.com"));
    testing.assertTrue(isExternal("//cdn.example.com/x.js"));
    testing.assertTrue(isExternal("mailto:someone@example.com"));
    testing.assertTrue(isExternal("tel:+1234"));
}

func testIsExternalLeavesLocalLinks() {
    testing.assertFalse(isExternal("guide/syntax.md"));
    testing.assertFalse(isExternal("../index.md"));
    testing.assertFalse(isExternal("#a-heading"));
    testing.assertFalse(isExternal(""));
}

# --- slugify ---------------------------------------------------------

func testSlugifyLowercasesAndDashesSpaces() {
    testing.assertEqual(slugify("Getting Started"), "getting-started");
    testing.assertEqual(slugify("Two\tTabs"), "two-tabs");
}

# The rule the docblock singles out: punctuation is dropped, not folded into a
# separator. Getting this wrong breaks every hand-written cross-reference in a
# book migrated from mdBook, and it does so silently.
func testSlugifyDropsPunctuationRatherThanFoldingIt() {
    testing.assertEqual(slugify("REPL (`cmd/jennifer/repl.go`)"), "repl-cmdjenniferreplgo");
    testing.assertEqual(slugify("What's new?"), "whats-new");
}

# Runs of dashes survive for the same reason: an mdBook anchor keeps them.
func testSlugifyKeepsDashRuns() {
    testing.assertEqual(slugify("M20 - System libraries"), "m20---system-libraries");
}

func testSlugifyFoldsDiacritics() {
    testing.assertEqual(slugify("Uber Grosse"), "uber-grosse");
}

# A heading with nothing left after the fold still has to anchor somewhere, and
# it has to be the same somewhere every time.
func testSlugifyFallsBackToSection() {
    testing.assertEqual(slugify("!!!"), "section");
    testing.assertEqual(slugify(""), "section");
}

# --- uniqueSlug and remember -----------------------------------------

func testUniqueSlugPassesAnUnseenSlugThrough() {
    def seen as map of string to int;
    testing.assertEqual(uniqueSlug($seen, "intro"), "intro");
}

func testUniqueSlugDisambiguatesLikeGitHub() {
    def seen as map of string to int;
    $seen = remember($seen, "intro");
    testing.assertEqual(uniqueSlug($seen, "intro"), "intro-1");
    $seen = remember($seen, "intro");
    testing.assertEqual(uniqueSlug($seen, "intro"), "intro-2");
}

func testRememberCountsFromOne() {
    def seen as map of string to int;
    $seen = remember($seen, "a");
    testing.assertEqual($seen["a"], 1);
    $seen = remember($seen, "a");
    testing.assertEqual($seen["a"], 2);
    testing.assertFalse(maps.has($seen, "b"));
}

# --- htmlPath --------------------------------------------------------

func testHtmlPathSwapsTheExtension() {
    testing.assertEqual(htmlPath("guide/syntax.md"), "guide/syntax.html");
    testing.assertEqual(htmlPath("index.md"), "index.html");
}

func testHtmlPathFoldsReadmeOntoIndex() {
    testing.assertEqual(htmlPath("README.md"), "index.html");
    testing.assertEqual(htmlPath("guide/README.md"), "guide/index.html");
}

func testHtmlPathNormalisesBackslashes() {
    testing.assertEqual(htmlPath("guide\\syntax.md"), "guide/syntax.html");
}

func testHtmlPathIsCaseInsensitiveAboutTheExtension() {
    testing.assertEqual(htmlPath("Notes.MD"), "Notes.html");
}

# --- depthOf and relPrefix -------------------------------------------

func testDepthOfCountsDirectories() {
    testing.assertEqual(depthOf("index.html"), 0);
    testing.assertEqual(depthOf("guide/syntax.html"), 1);
    testing.assertEqual(depthOf("a/b/c/d.html"), 3);
}

func testRelPrefixWalksBackToTheRoot() {
    testing.assertEqual(relPrefix(0), "");
    testing.assertEqual(relPrefix(1), "../");
    testing.assertEqual(relPrefix(3), "../../../");
}

# The two are a pair, and the invariant that matters is that a page can always
# reach the root from wherever it sits.
func testDepthAndPrefixCompose() {
    testing.assertEqual(relPrefix(depthOf("a/b/page.html")), "../../");
}

# --- cleanPath -------------------------------------------------------

func testCleanPathCollapsesDotSegments() {
    testing.assertEqual(cleanPath("guide/./syntax.md"), "guide/syntax.md");
    testing.assertEqual(cleanPath("guide/../index.md"), "index.md");
    testing.assertEqual(cleanPath("a/b/../../c.md"), "c.md");
}

func testCleanPathStaysRelative() {
    testing.assertEqual(cleanPath("../outside.md"), "../outside.md");
    testing.assertEqual(cleanPath("../../way/out.md"), "../../way/out.md");
}

func testCleanPathDropsEmptySegments() {
    testing.assertEqual(cleanPath("a//b.md"), "a/b.md");
}

# --- dirOf -----------------------------------------------------------

func testDirOfTakesEverythingBeforeTheLastSlash() {
    testing.assertEqual(dirOf("a/b/c.html"), "a/b");
    testing.assertEqual(dirOf("a/b.html"), "a");
}

func testDirOfIsEmptyAtTheRoot() {
    testing.assertEqual(dirOf("index.html"), "");
}

# --- splitFragment ---------------------------------------------------

func testSplitFragmentKeepsTheHash() {
    def parts as list of string init splitFragment("page.md#a-heading");
    testing.assertEqual($parts[0], "page.md");
    testing.assertEqual($parts[1], "#a-heading");
}

func testSplitFragmentHandlesNoFragment() {
    def parts as list of string init splitFragment("page.md");
    testing.assertEqual($parts[0], "page.md");
    testing.assertEqual($parts[1], "");
}

func testSplitFragmentHandlesABareFragment() {
    def parts as list of string init splitFragment("#top");
    testing.assertEqual($parts[0], "");
    testing.assertEqual($parts[1], "#top");
}

# --- squeeze ---------------------------------------------------------

func testSqueezeCollapsesWhitespaceRuns() {
    testing.assertEqual(squeeze("a   b"), "a b");
    testing.assertEqual(squeeze("a\n\nb"), "a b");
    testing.assertEqual(squeeze("a\tb\r\nc"), "a b c");
}

func testSqueezeTrimsTheEnds() {
    testing.assertEqual(squeeze("   padded   "), "padded");
    testing.assertEqual(squeeze("   "), "");
}

# --- truncate --------------------------------------------------------

func testTruncateLeavesShortTextAlone() {
    testing.assertEqual(truncate("short", 20), "short");
    testing.assertEqual(truncate("exactly ten", 11), "exactly ten");
}

func testTruncateCutsAtAWordBoundary() {
    testing.assertEqual(truncate("one two three four", 12), "one two");
}

# The guard the comment argues for: honouring the word boundary on a single
# enormous token would truncate to almost nothing, so the hard cut wins instead.
func testTruncateIgnoresAUselessWordBoundary() {
    testing.assertEqual(truncate("a verylongtokenwithoutspaces", 12), "a verylongto");
}

func testTruncateWithNoSpaceAtAll() {
    testing.assertEqual(truncate("abcdefghijkl", 5), "abcde");
}

# --- stripComments ---------------------------------------------------

func testStripCommentsDropsAWholeLineComment() {
    testing.assertEqual(stripComments("# Title\n<!-- generated -->\nBody"), "# Title\nBody");
}

func testStripCommentsSpansMultipleLines() {
    def md as string init "a\n<!-- one\ntwo\nthree -->\nb";
    testing.assertEqual(stripComments($md), "a\nb");
}

func testStripCommentsLeavesInlineCommentsAlone() {
    def md as string init "text <!-- inline --> more";
    testing.assertEqual(stripComments($md), $md);
}

func testStripCommentsToleratesIndentation() {
    testing.assertEqual(stripComments("a\n   <!-- x -->\nb"), "a\nb");
}

# --- isThematicBreak -------------------------------------------------

func testIsThematicBreakAcceptsTheThreeMarkers() {
    testing.assertTrue(isThematicBreak("---"));
    testing.assertTrue(isThematicBreak("***"));
    testing.assertTrue(isThematicBreak("___"));
    testing.assertTrue(isThematicBreak("- - -"));
    testing.assertTrue(isThematicBreak("-----"));
}

func testIsThematicBreakNeedsThree() {
    testing.assertFalse(isThematicBreak("--"));
    testing.assertFalse(isThematicBreak(""));
}

func testIsThematicBreakRejectsMixedMarkers() {
    testing.assertFalse(isThematicBreak("-*-"));
}

func testIsThematicBreakRejectsAnythingElseOnTheLine() {
    testing.assertFalse(isThematicBreak("--- text"));
    testing.assertFalse(isThematicBreak("# Heading"));
}
