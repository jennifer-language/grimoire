# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `summary.j`, run by `jennifer test src/summary_test.j`.
 *
 * `parse` is a hand-written line reader for a format defined by another tool, so
 * most of what is checked here is compatibility with mdBook rather than internal
 * consistency: which lines are ignored, where the numbering restarts, and which
 * entries sit outside it. `fromDirectory` and `load` touch the filesystem and are
 * exercised against a fixture written under a temporary directory.
 * @module summary_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use fs;
use os;
use path;
use strings;

# --- the kind constants ----------------------------------------------

func testKindsAreDistinct() {
    testing.assertEqual(partKind(), "part");
    testing.assertEqual(pageKind(), "page");
    testing.assertEqual(draftKind(), "draft");
    testing.assertEqual(separatorKind(), "separator");
    testing.assertNotEqual(partKind(), pageKind());
}

# --- indentOf --------------------------------------------------------

func testIndentOfCountsSpaces() {
    testing.assertEqual(indentOf("no indent"), 0);
    testing.assertEqual(indentOf("  two"), 2);
    testing.assertEqual(indentOf("    four"), 4);
}

# A tab stands for four spaces, which is the unit mdBook uses when a SUMMARY
# mixes the two.
func testIndentOfTreatsATabAsFour() {
    testing.assertEqual(indentOf("\tone tab"), 4);
    testing.assertEqual(indentOf("  \tmixed"), 6);
}

func testIndentOfStopsAtTheFirstRealCharacter() {
    testing.assertEqual(indentOf("  a  b"), 2);
}

# --- stripMarker -----------------------------------------------------

func testStripMarkerHandlesEveryBulletCharacter() {
    testing.assertEqual(stripMarker("- item"), "item");
    testing.assertEqual(stripMarker("* item"), "item");
    testing.assertEqual(stripMarker("+ item"), "item");
}

func testStripMarkerHandlesOrderedMarkers() {
    testing.assertEqual(stripMarker("1. item"), "item");
    testing.assertEqual(stripMarker("12. item"), "item");
}

func testStripMarkerReturnsEmptyForAnUnmarkedLine() {
    testing.assertEqual(stripMarker("[Title](x.md)"), "");
    testing.assertEqual(stripMarker("plain text"), "");
    testing.assertEqual(stripMarker("-no space"), "");
}

# --- linkParts -------------------------------------------------------

func testLinkPartsSplitsALink() {
    def parts as list of string init linkParts("[Title](guide/x.md)");
    testing.assertEqual(len($parts), 2);
    testing.assertEqual($parts[0], "Title");
    testing.assertEqual($parts[1], "guide/x.md");
}

func testLinkPartsAcceptsAnEmptyTarget() {
    def parts as list of string init linkParts("[Not written yet]()");
    testing.assertEqual(len($parts), 2);
    testing.assertEqual($parts[1], "");
}

func testLinkPartsRejectsNonLinks() {
    testing.assertEqual(len(linkParts("plain")), 0);
    testing.assertEqual(len(linkParts("[unclosed")), 0);
    testing.assertEqual(len(linkParts("[title](unclosed")), 0);
}

# --- advance and renderNumber ----------------------------------------

func testAdvanceCountsAtOneLevel() {
    def c as list of int;
    $c = advance($c, 0);
    testing.assertEqual(renderNumber($c), "1");
    $c = advance($c, 0);
    testing.assertEqual(renderNumber($c), "2");
}

func testAdvanceDescendsAndReturns() {
    def c as list of int;
    $c = advance($c, 0);
    $c = advance($c, 1);
    testing.assertEqual(renderNumber($c), "1.1");
    $c = advance($c, 1);
    testing.assertEqual(renderNumber($c), "1.2");
    $c = advance($c, 0);
    testing.assertEqual(renderNumber($c), "2");
}

# Coming back down has to reset the deeper counter, or the second section would
# number its children 2.3, 2.4 instead of 2.1, 2.2.
func testAdvanceResetsDeeperCountersOnTheWayBack() {
    def c as list of int;
    $c = advance($c, 0);
    $c = advance($c, 1);
    $c = advance($c, 1);
    $c = advance($c, 0);
    $c = advance($c, 1);
    testing.assertEqual(renderNumber($c), "2.1");
}

# --- parse -----------------------------------------------------------

func testParseReadsASimpleOutline() {
    def entries as list of Entry init parse("# Summary\n\n- [One](one.md)\n- [Two](two.md)\n");
    testing.assertEqual(len($entries), 2);
    testing.assertEqual($entries[0].kind, pageKind());
    testing.assertEqual($entries[0].title, "One");
    testing.assertEqual($entries[0].src, "one.md");
    testing.assertEqual($entries[0].out, "one.html");
    testing.assertEqual($entries[0].number, "1");
    testing.assertEqual($entries[1].number, "2");
}

# The conventional `# Summary` heading is the document's own title, not a part of
# the book, and dropping it is the difference between a stray empty section in
# every sidebar and none.
func testParseDropsTheSummaryHeadingButKeepsOtherParts() {
    def entries as list of Entry init parse("# Summary\n# Getting started\n- [One](one.md)\n");
    testing.assertEqual(len($entries), 2);
    testing.assertEqual($entries[0].kind, partKind());
    testing.assertEqual($entries[0].title, "Getting started");
}

func testParseNestsByIndentation() {
    def src as string init "- [One](one.md)\n  - [Deep](deep.md)\n- [Two](two.md)\n";
    def entries as list of Entry init parse($src);
    testing.assertEqual($entries[0].level, 0);
    testing.assertEqual($entries[1].level, 1);
    testing.assertEqual($entries[1].number, "1.1");
    testing.assertEqual($entries[2].level, 0);
    testing.assertEqual($entries[2].number, "2");
}

# A prefix or suffix chapter is a link with no list marker, and mdBook leaves it
# outside the numbering.
func testParseLeavesUnlistedChaptersUnnumbered() {
    def entries as list of Entry init parse("[Foreword](fore.md)\n- [One](one.md)\n");
    testing.assertEqual($entries[0].kind, pageKind());
    testing.assertEqual($entries[0].number, "");
    testing.assertEqual($entries[1].number, "1");
}

func testParseRecognisesADraft() {
    def entries as list of Entry init parse("- [Not written]()\n");
    testing.assertEqual(len($entries), 1);
    testing.assertEqual($entries[0].kind, draftKind());
    testing.assertEqual($entries[0].title, "Not written");
    testing.assertEqual($entries[0].src, "");
}

func testParseRecognisesASeparator() {
    def entries as list of Entry init parse("- [One](one.md)\n---\n- [Two](two.md)\n");
    testing.assertEqual(len($entries), 3);
    testing.assertEqual($entries[1].kind, separatorKind());
}

# Anything unrecognised is ignored rather than fatal, so a hand-maintained
# SUMMARY with notes in it still parses.
func testParseIgnoresProseAndComments() {
    def src as string init "Some note.\n<!-- a comment -->\n- [One](one.md)\n";
    def entries as list of Entry init parse($src);
    testing.assertEqual(len($entries), 1);
    testing.assertEqual($entries[0].title, "One");
}

func testParseCleansTheTargetPath() {
    def entries as list of Entry init parse("- [One](./guide/../one.md)\n");
    testing.assertEqual($entries[0].src, "one.md");
}

func testParseOfNothingIsEmpty() {
    testing.assertEqual(len(parse("")), 0);
    testing.assertEqual(len(parse("# Summary\n\n\n")), 0);
}

# A SUMMARY whose list is indented throughout should still start at level 0: the
# base indent is taken from the first listed entry, not assumed to be zero.
func testParseTakesTheBaseIndentFromTheFirstEntry() {
    def entries as list of Entry init parse("  - [One](one.md)\n  - [Two](two.md)\n");
    testing.assertEqual($entries[0].level, 0);
    testing.assertEqual($entries[1].level, 0);
}

# --- pages -----------------------------------------------------------

func testPagesKeepsOnlyLinkedChapters() {
    def src as string init "# Part\n- [One](one.md)\n- [Draft]()\n---\n- [Two](two.md)\n";
    def all as list of Entry init parse($src);
    def just as list of Entry init pages($all);
    testing.assertEqual(len($all), 5);
    testing.assertEqual(len($just), 2);
    testing.assertEqual($just[0].title, "One");
    testing.assertEqual($just[1].title, "Two");
}

# --- titleFor and rankOf ---------------------------------------------

func testTitleForHumanisesAFileName() {
    testing.assertEqual(titleFor("first-program.md"), "First program");
    testing.assertEqual(titleFor("some_notes.md"), "Some notes");
}

func testTitleForNamesALandingPageAfterItsDirectory() {
    testing.assertEqual(titleFor("index.md"), "Introduction");
    testing.assertEqual(titleFor("README.md"), "Introduction");
    testing.assertEqual(titleFor("getting-started/index.md"), "Getting started");
}

func testRankOfSortsLandingPagesFirst() {
    testing.assertEqual(rankOf("index.md"), 0);
    testing.assertEqual(rankOf("README.md"), 0);
    testing.assertEqual(rankOf("other.md"), 1);
}

# --- fromDirectory and load ------------------------------------------

# A fixture book on disk, since both of these walk the filesystem. Each call gets
# its own directory under the system temporary one, and the test that made it
# removes it - so nothing here depends on the order the tests run in.
func fixture(name as string) {
    def root as string init fs.makeTempDir(os.tempDir(), "grimoire-summary-" + $name + "-");
    fs.mkdirAll(path.join($root, "guide"));
    fs.writeString(path.join($root, "index.md"), "# Home\n");
    fs.writeString(path.join($root, "alpha.md"), "# Alpha\n");
    fs.writeString(path.join($root, "guide/setup.md"), "# Setup\n");
    fs.writeString(path.join($root, "notes.txt"), "not markdown\n");
    return $root;
}

func testFromDirectoryOpensWithTheLandingPage() {
    def root as string init fixture("landing");
    def entries as list of Entry init fromDirectory($root);
    testing.assertEqual($entries[0].src, "index.md");
    testing.assertEqual($entries[0].number, "");
    fs.removeAll($root);
}

func testFromDirectoryNumbersTheRestAndSkipsNonMarkdown() {
    def root as string init fixture("numbering");
    def entries as list of Entry init fromDirectory($root);
    def found as list of string;
    for (def e in $entries) {
        if ($e.kind == pageKind()) {
            $found[] = $e.src;
        }
    }
    testing.assertEqual(len($found), 3);
    testing.assertEqual($found[1], "alpha.md");
    testing.assertEqual($entries[1].number, "1");
    fs.removeAll($root);
}

func testFromDirectoryOpensAPartForEachSubdirectory() {
    def root as string init fixture("parts");
    def entries as list of Entry init fromDirectory($root);
    def parts as int init 0;
    for (def e in $entries) {
        if ($e.kind == partKind()) {
            $parts = $parts + 1;
            testing.assertEqual($e.title, "Guide");
        }
    }
    testing.assertEqual($parts, 1);
    fs.removeAll($root);
}

func testLoadPrefersASummaryOverTheDirectoryWalk() {
    def root as string init fixture("prefers");
    fs.writeString(path.join($root, "SUMMARY.md"), "- [Only this](alpha.md)\n");
    def entries as list of Entry init load($root);
    testing.assertEqual(len($entries), 1);
    testing.assertEqual($entries[0].title, "Only this");
    fs.removeAll($root);
}

func testLoadFallsBackToTheDirectoryWalk() {
    def root as string init fixture("fallback");
    def entries as list of Entry init load($root);
    testing.assertTrue(len($entries) > 1);
    fs.removeAll($root);
}

# SUMMARY.md is the outline, not a chapter of the book, so the walk must not
# offer it as one.
func testMarkdownFilesSkipsTheSummaryItself() {
    def root as string init fixture("skips");
    fs.writeString(path.join($root, "SUMMARY.md"), "- [One](alpha.md)\n");
    for (def rel in markdownFiles($root)) {
        testing.assertFalse(strings.lower($rel) == "summary.md");
    }
    fs.removeAll($root);
}

func testMarkdownFilesIsSorted() {
    def root as string init fixture("sorted");
    def files as list of string init markdownFiles($root);
    def previous as string init "";
    for (def rel in $files) {
        testing.assertTrue($previous == "" or $previous < $rel);
        $previous = $rel;
    }
    fs.removeAll($root);
}
