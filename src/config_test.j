# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `config.j`, run by `jennifer test src/config_test.j`.
 *
 * The module's whole stance is that a configuration file is user input: an
 * unknown key is ignored, a key of the wrong type keeps its default, and an
 * enumerated setting outside its allowed set falls back rather than reaching the
 * renderer. Those three are what most of the cases below are about - each one is
 * a build that succeeds instead of a build that aborts, so a regression in any of
 * them would be silent.
 * @module config_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use fs;
use os;
use path;

# --- defaults --------------------------------------------------------

func testDefaultsBuildDocsIntoSite() {
    def c as Config init defaults();
    testing.assertEqual($c.srcDir, "docs");
    testing.assertEqual($c.outDir, "site");
    testing.assertEqual($c.theme, "grimoire");
    testing.assertEqual($c.defaultMode, "auto");
    testing.assertEqual($c.language, "en");
    testing.assertEqual($c.jobs, 0);
}

# Search on, PDF off, highlighting off. The last of those is the one worth
# pinning: turning it on is a decision, not a default.
func testDefaultsHaveSearchOnAndTheRestOff() {
    def c as Config init defaults();
    testing.assertTrue($c.search);
    testing.assertTrue($c.keywords);
    testing.assertFalse($c.pdf);
    testing.assertFalse($c.highlight);
    testing.assertFalse($c.highlightJs);
}

# Off by default, and this is the one default worth being deliberate about: the
# other reading is just as reasonable, and getting it wrong deletes files. A book
# opts in; nothing opts in on its behalf.
func testTheOutputDirectoryIsNotPrunedByDefault() {
    testing.assertFalse(defaults().clean);
}

func testCleanIsReadFromTheBuildTable() {
    testing.assertTrue(apply(defaults(), '[build]
clean = true
').clean);
    testing.assertFalse(apply(defaults(), '[build]
clean = false
').clean);
    testing.assertFalse(apply(defaults(), '[build]
clean = "yes"
').clean);
}

func testDefaultsPlaceTheColumnsWhereTheyHaveAlwaysBeen() {
    def c as Config init defaults();
    testing.assertEqual($c.navPosition, "left");
    testing.assertEqual($c.tocPosition, "right");
    testing.assertEqual($c.tocDepth, 3);
}

# --- apply: the happy path -------------------------------------------

func testApplyLayersEveryTable() {
    def toml as string init '[book]
title = "My Book"
language = "de"
src = "chapters"

[build]
out = "public"
jobs = 4

[html]
theme = "nordic"
tocDepth = 2

[search]
enabled = false

[pdf]
enabled = true
paper = "letter"
';
    def c as Config init apply(defaults(), $toml);
    testing.assertEqual($c.title, "My Book");
    testing.assertEqual($c.language, "de");
    testing.assertEqual($c.srcDir, "chapters");
    testing.assertEqual($c.outDir, "public");
    testing.assertEqual($c.jobs, 4);
    testing.assertEqual($c.theme, "nordic");
    testing.assertEqual($c.tocDepth, 2);
    testing.assertFalse($c.search);
    testing.assertTrue($c.pdf);
    testing.assertEqual($c.pdfPaper, "letter");
}

func testApplyReadsStringLists() {
    def c as Config init apply(defaults(), '[book]
authors = ["Ada", "Grace"]
');
    testing.assertEqual(len($c.authors), 2);
    testing.assertEqual($c.authors[0], "Ada");
}

# --- apply: user input is not to be trusted --------------------------

func testApplyIgnoresUnknownKeys() {
    def c as Config init apply(
        defaults(),
        '[html]
theme = "nordic"
noSuchKey = "whatever"

[nosuchtable]
x = 1
');
    testing.assertEqual($c.theme, "nordic");
}

# A key of the wrong type keeps the base value rather than aborting a build that
# would otherwise have succeeded.
func testApplyKeepsTheDefaultForAWrongType() {
    def c as Config init apply(
        defaults(),
        '[html]
tocDepth = "three"

[search]
enabled = "yes"

[book]
title = 42
');
    testing.assertEqual($c.tocDepth, 3);
    testing.assertTrue($c.search);
    testing.assertEqual($c.title, "Documentation");
}

func testApplyDropsNonStringsFromAStringList() {
    def c as Config init apply(defaults(), '[book]
authors = ["Ada", 7, "Grace"]
');
    testing.assertEqual(len($c.authors), 2);
    testing.assertEqual($c.authors[1], "Grace");
}

func testApplyOfAnEmptyDocumentChangesNothing() {
    def c as Config init apply(defaults(), "");
    testing.assertEqual($c.title, defaults().title);
    testing.assertEqual($c.theme, defaults().theme);
}

# --- apply: enumerated settings --------------------------------------

func testApplyClampsTheColourMode() {
    testing.assertEqual(apply(defaults(), '[html]
mode = "dark"
').defaultMode, "dark");
    testing.assertEqual(apply(defaults(), '[html]
mode = "chartreuse"
').defaultMode, "auto");
}

func testApplyClampsThePaperSize() {
    testing.assertEqual(apply(defaults(), '[pdf]
paper = "letter"
').pdfPaper, "letter");
    testing.assertEqual(apply(defaults(), '[pdf]
paper = "a3"
').pdfPaper, "a4");
}

func testApplyAcceptsEveryColumnPosition() {
    def c as Config init apply(defaults(), '[html]
navPosition = "right"
tocPosition = "off"
');
    testing.assertEqual($c.navPosition, "right");
    testing.assertEqual($c.tocPosition, "off");
}

func testApplyClampsAnUnknownColumnPosition() {
    def c as Config init apply(
        defaults(),
        '[html]
navPosition = "sideways"
tocPosition = "middle"
');
    testing.assertEqual($c.navPosition, "left");
    testing.assertEqual($c.tocPosition, "right");
}

# --- apply: numeric bounds -------------------------------------------

func testApplyClampsTocDepthToItsRange() {
    testing.assertEqual(apply(defaults(), '[html]
tocDepth = 0
').tocDepth, 1);
    testing.assertEqual(apply(defaults(), '[html]
tocDepth = 9
').tocDepth, 6);
    testing.assertEqual(apply(defaults(), '[html]
tocDepth = -5
').tocDepth, 1);
}

func testApplyEnforcesASearchBodyFloor() {
    testing.assertEqual(apply(defaults(), '[search]
bodyChars = 10
').searchBodyChars, 120);
    testing.assertEqual(apply(defaults(), '[search]
bodyChars = 400
').searchBodyChars, 400);
}

# --- the interface language follows the book -------------------------

# A German book gets a German interface without being told twice, and a book that
# says otherwise is taken at its word.
func testUiLanguageFollowsTheBookLanguage() {
    testing.assertEqual(apply(defaults(), '[book]
language = "de"
').uiLanguage, "de");
}

func testUiLanguageCanDifferFromTheBook() {
    def c as Config init apply(defaults(), '[book]
language = "de"

[html]
uiLanguage = "en"
');
    testing.assertEqual($c.language, "de");
    testing.assertEqual($c.uiLanguage, "en");
}

# --- apply: malformed input ------------------------------------------

func decodeBrokenToml() {
    return apply(defaults(), "[unclosed\nkey = ");
}

# The `toml` module raises a plain runtime error rather than a kinded one - its
# message carries the `toml:` prefix instead. Worth pinning: the docblocks on
# `apply` and `load` said "kind toml" until this test disagreed with them.
func testApplyThrowsOnADocumentThatDoesNotParse() {
    testing.assertThrows("decodeBrokenToml", "runtime");
}

# --- load ------------------------------------------------------------

func testLoadOfAMissingFileIsTheDefaults() {
    def c as Config init load(path.join(os.tempDir(), "grimoire-no-such-config.toml"));
    testing.assertEqual($c.title, defaults().title);
    testing.assertEqual($c.srcDir, defaults().srcDir);
}

func testLoadReadsAFile() {
    def dir as string init fs.makeTempDir(os.tempDir(), "grimoire-config-");
    def file as string init path.join($dir, "grimoire.toml");
    fs.writeString($file, '[book]
title = "From disk"
');
    testing.assertEqual(load($file).title, "From disk");
    fs.removeAll($dir);
}

# --- validPosition, showsNav, showsToc -------------------------------

func testValidPositionAcceptsExactlyThreeValues() {
    testing.assertTrue(validPosition("left"));
    testing.assertTrue(validPosition("right"));
    testing.assertTrue(validPosition("off"));
    testing.assertFalse(validPosition("middle"));
    testing.assertFalse(validPosition(""));
    testing.assertFalse(validPosition("Left"));
}

func testShowsNavAndShowsTocFollowThePositions() {
    def c as Config init defaults();
    testing.assertTrue(showsNav($c));
    testing.assertTrue(showsToc($c));
    $c.navPosition = "right";
    testing.assertTrue(showsNav($c));
    $c.navPosition = "off";
    testing.assertFalse(showsNav($c));
    $c.tocPosition = "off";
    testing.assertFalse(showsToc($c));
}

# --- the highlighting pair -------------------------------------------

# `highlight` is the master switch. A book that says "no highlighting" must not
# start making third-party requests because a second table was left enabled.
func testHighlightJsNeedsHighlightOn() {
    def c as Config init defaults();
    $c.highlightJs = true;
    testing.assertFalse(usesHighlightJs($c));
    testing.assertTrue(highlightJsIgnored($c));
    $c.highlight = true;
    testing.assertTrue(usesHighlightJs($c));
    testing.assertFalse(highlightJsIgnored($c));
}

func testHighlightJsNeedsACdn() {
    def c as Config init defaults();
    $c.highlight = true;
    $c.highlightJs = true;
    $c.highlightCdn = "";
    testing.assertFalse(usesHighlightJs($c));
}

func testBuiltInHighlightingAloneMakesNoRequests() {
    def c as Config init defaults();
    $c.highlight = true;
    testing.assertFalse(usesHighlightJs($c));
    testing.assertFalse(highlightJsIgnored($c));
}

# --- the author lines ------------------------------------------------

# Two forms, and only one of them is labelled: the meta tag and the PDF Info
# dictionary are read by software and want the names alone.
func testAuthorLineIsTheBareNames() {
    def c as Config init defaults();
    $c.authors = ["Ada Lovelace", "Grace Hopper"];
    testing.assertEqual(authorLine($c), "Ada Lovelace, Grace Hopper");
}

func testAuthorCreditIsLabelled() {
    def c as Config init defaults();
    $c.authors = ["Ada Lovelace"];
    testing.assertEqual(authorCredit($c), "Written by Ada Lovelace");
    $c.authorsLabel = "Built with love by";
    testing.assertEqual(authorCredit($c), "Built with love by Ada Lovelace");
}

func testAnEmptyLabelPrintsTheNamesAlone() {
    def c as Config init defaults();
    $c.authors = ["Ada Lovelace"];
    $c.authorsLabel = "";
    testing.assertEqual(authorCredit($c), "Ada Lovelace");
    $c.authorsLabel = "   ";
    testing.assertEqual(authorCredit($c), "Ada Lovelace");
}

func testBothAuthorFormsAreEmptyWithNoAuthors() {
    def c as Config init defaults();
    testing.assertEqual(authorLine($c), "");
    testing.assertEqual(authorCredit($c), "");
}
