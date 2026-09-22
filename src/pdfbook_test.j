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
use fs;
use os;
use path;

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
# both dashes and a bullet all encode, so they reach the page as themselves. A
# book's own content is where those turn up, and it is right that they print as
# written - which is also why the table holds no reading for any of them.
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

# WinAnsi has the French and German and Spanish letters and stops, so before
# these readings existed a Polish book printed as `Zwyk?y tekst` and a Czech,
# Hungarian, Turkish, Romanian or Baltic one the same way. The reading is the
# letter without its diacritic: not the word the author wrote, but their book
# rather than a page of question marks.
func testSanitizeReadsTheEuropeanAlphabets() {
    for (def sample in [
        "Zwykły tekst z zachętą",
        "Příliš žluťoučký kůň úpěl",
        "Árvíztűrő tükörfúrógép",
        "Pijamalı hasta yağız şoföre",
        "Țara și București",
        "Ēdiet vēl šīs mīkstās karameles",
        "Įlinkdama fechtuotojo špaga",
        "Đurđevak i ćevapi"
    ]) {
        testing.assertFalse(strings.contains(sanitize($sample), "?"));
    }
    testing.assertEqual(sanitize("Zwykły tekst z zachętą"), "Zwykly tekst z zacheta");
    testing.assertEqual(sanitize("Țara și București"), "Tara si Bucuresti");
    # What WinAnsi already draws stays as the author wrote it: only the two
    # Hungarian letters it lacks are reduced.
    testing.assertEqual(sanitize("Árvíztűrő tükörfúrógép"), "Árvízturo tükörfúrógép");
}

# Four entries are not a letter plus a mark, so the reading is not simply the
# letter under it.
func testTheReadingsThatAreNotJustADroppedMark() {
    testing.assertEqual(sanitize("Đurđevak"), "Durdevak");
    testing.assertEqual(sanitize(convert.fromCodepoint(0x0132)), "IJ");
    testing.assertEqual(sanitize(convert.fromCodepoint(0x0149)), "'n");
    testing.assertEqual(sanitize(convert.fromCodepoint(0x014B)), "ng");
}

# A reading that is not ASCII would be a character the fonts cannot draw
# standing in for a character the fonts cannot draw.
func testEveryReadingIsAscii() {
    for (def key in maps.keys(TRANSLITERATIONS)) {
        def reading as string init TRANSLITERATIONS[$key];
        testing.assertNotEqual($reading, "");
        for (def ch in strings.chars($reading)) {
            testing.assertTrue(convert.toCodepoint($ch) < 128);
        }
    }
}

# An entry for a character WinAnsi draws is never consulted, and reading the
# table would suggest otherwise. `sanitize` asks `encodable` first.
func testTheTableHoldsNothingTheFontsCanDraw() {
    for (def key in maps.keys(TRANSLITERATIONS)) {
        testing.assertFalse(encodable($key));
    }
}

# The boundary, stated: an alphabet that is not Latin has no letter to fall back
# to, so it is still question marks. Romanising one is a different job.
func testANonLatinAlphabetIsStillLost() {
    testing.assertEqual(sanitize("Примечание"), "??????????");
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
    testing.assertEqual(printLine("see [the guide](guide/x.md)", ""), "see the guide");
    testing.assertEqual(printLine("see [the guide](guide/x.md#anchor)", ""), "see the guide");
    testing.assertEqual(printLine("see [above](#anchor)", ""), "see above");
}

# An external URL is worth keeping in parentheses, because the URL is the only
# way a reader on paper can follow it.
func testPrintLineKeepsAnExternalUrl() {
    testing.assertEqual(
        printLine("see [the site](https://example.com)", ""),
        "see the site (https://example.com)");
}

func testPrintLineDropsATitle() {
    testing.assertEqual(printLine('see [x](y.md "a title")', ""), "see x");
    testing.assertEqual(
        printLine('see [x](https://example.com "a title")', ""),
        "see x (https://example.com)");
}

# An image is left exactly as written, for the layout to draw. Both link patterns
# match the `[alt](url)` inside it otherwise - an image target is never a `.md`
# file, so it falls through to the general pattern and prints
# `alt (diagram.png)`, a file path in the middle of the prose.
func testPrintLineLeavesAnImageWhole() {
    testing.assertEqual(printLine("![alt](diagram.png)", ""), "![alt](diagram.png)");
    testing.assertEqual(
        printLine('![alt](diagram.png "a title")', ""),
        '![alt](diagram.png "a title")');
    testing.assertEqual(printLine("![](bare.png)", ""), "![](bare.png)");
}

# A chapter writes its image targets relative to itself, and the printable book is
# one document built from every chapter, so a target is resolved against the
# chapter's own directory: two chapters that each write `images/plot.png` mean two
# different files, and the layout is handed one map keyed by these strings.
func testPrintLineResolvesAnImageAgainstItsChapter() {
    testing.assertEqual(printLine("![a](images/plot.png)", "guide"), "![a](guide/images/plot.png)");
    testing.assertEqual(
        printLine("![a](../shared/x.png)", "guide/deep"),
        "![a](guide/shared/x.png)");
    testing.assertEqual(printLine('![a](x.png "t")', "guide"), '![a](guide/x.png "t")');
}

# Anything that does not name a file inside the book is left as it is - there is
# nothing to resolve it against, and nothing will be fetched to find out.
func testPrintLineLeavesForeignImageTargetsAlone() {
    testing.assertEqual(
        printLine("![a](https://e.com/i.png)", "guide"),
        "![a](https://e.com/i.png)");
    testing.assertEqual(printLine("![a](/logo.png)", "guide"), "![a](/logo.png)");
    testing.assertEqual(printLine("![a](x.png)", ""), "![a](x.png)");
}

# The links around an image are still rewritten; the image spans are stepped over
# rather than matched, so two of them back to back do not lose the boundary.
func testPrintLineRewritesLinksAroundImages() {
    testing.assertEqual(
        printLine("text ![a](i.png) and [b](https://e.com) end", ""),
        "text ![a](i.png) and b (https://e.com) end");
    testing.assertEqual(printLine("[x](y.md) ![a](i.png) [z](w.md)", ""), "x ![a](i.png) z");
    testing.assertEqual(printLine("![one](1.png)![two](2.png)", ""), "![one](1.png)![two](2.png)");
    testing.assertEqual(printLine("**![bold img](c.png)**", ""), "**![bold img](c.png)**");
}

func testPrintLineLeavesOrdinaryProseAlone() {
    testing.assertEqual(printLine("no links here", ""), "no links here");
    testing.assertEqual(printLine("brackets [but] no target", ""), "brackets [but] no target");
    testing.assertEqual(printLine("", ""), "");
}

func testPrintLineRewritesEveryLinkOnALine() {
    testing.assertEqual(printLine("[a](a.md) and [b](b.md)", ""), "a and b");
}

# --- pictures --------------------------------------------------------

# An 8x8 PNG, so a test can hand `pictures` a file that `pdf.loadImage` really
# reads rather than a name that happens to end in `.png`. Base64 because a test
# file is a module top level: a fixture is a function, and this one has to be
# bytes.
func tinyPng() {
    return encoding.fromText(
        "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEElEQVR4nGNgOMCAHQ0tCQDB" +
            "1jAB4smq5AAAAABJRU5ErkJggg==",
        "base64");
}

func testImageTargetsReadsInOrder() {
    def md as string init "![a](one.png)\n\ntext\n\n![b](two.jpg) and ![c](three.png)\n";
    def urls as list of string init imageTargets($md);
    testing.assertEqual(len($urls), 3);
    testing.assertEqual($urls[0], "one.png");
    testing.assertEqual($urls[1], "two.jpg");
    testing.assertEqual($urls[2], "three.png");
}

# A chapter that documents the syntax writes an image inside a fence. Loading it
# would put bytes in the PDF that nothing ever draws.
func testImageTargetsSkipsFencedExamples() {
    def md as string init "![real](r.png)\n\n```md\n![example](e.png)\n```\n";
    def urls as list of string init imageTargets($md);
    testing.assertEqual(len($urls), 1);
    testing.assertEqual($urls[0], "r.png");
}

# The formats `pdf.loadImage` accepts, tested on the name so a book of SVG
# diagrams is not read into memory to find out.
func testDrawableAcceptsRastersOnly() {
    testing.assertTrue(drawable("a.png"));
    testing.assertTrue(drawable("shots/A.JPG"));
    testing.assertTrue(drawable("a.jpeg"));
    testing.assertFalse(drawable("a.svg"));
    testing.assertFalse(drawable("a.png.gz"));
    testing.assertFalse(drawable("png"));
}

# What is drawable and present is loaded once and keyed by the target as the
# document writes it; everything else is left out, and the layout falls back to
# the alt text for those.
func testPicturesLoadsWhatItCanDraw() {
    def root as string init fs.makeTempDir(os.tempDir(), "grimoire-pdf-pictures-");
    fs.mkdirAll(path.join($root, "shots"));
    fs.writeBytes(path.join($root, "shots/a.png"), tinyPng());
    fs.writeString(path.join($root, "shots/d.svg"), "<svg></svg>");
    def c as config.Config init book();
    $c.srcDir = $root;
    def md as string init "![a](shots/a.png)\n\n![again](shots/a.png)\n\n" +
        "![d](shots/d.svg)\n\n![gone](shots/missing.png)\n\n![x](https://e.com/x.png)\n";
    def imgs as map of string to pdf.Image init pictures($c, $md);
    testing.assertEqual(len(maps.keys($imgs)), 1);
    testing.assertTrue(maps.has($imgs, "shots/a.png"));
    testing.assertEqual($imgs["shots/a.png"].width, 8);
    testing.assertEqual($imgs["shots/a.png"].height, 8);
    fs.removeAll($root);
}

# The resource names follow reading order, because the layout registers one PDF
# resource per entry as it iterates the map: a name that moved between runs would
# break the promise that `--jobs` cannot change a byte of the output.
func testPicturesNamesInReadingOrder() {
    def root as string init fs.makeTempDir(os.tempDir(), "grimoire-pdf-order-");
    fs.writeBytes(path.join($root, "first.png"), tinyPng());
    fs.writeBytes(path.join($root, "second.png"), tinyPng());
    def c as config.Config init book();
    $c.srcDir = $root;
    def imgs as map of string to pdf.Image init pictures(
        $c,
        "![b](second.png)\n\n![a](first.png)\n");
    testing.assertEqual($imgs["second.png"].name, "img0");
    testing.assertEqual($imgs["first.png"].name, "img1");
}

# --- prepare ---------------------------------------------------------

func testPrepareDemotesHeadings() {
    def out as string init prepare("# Title\n\n## Section\n", 1, "");
    testing.assertContains($out, "## Title");
    testing.assertContains($out, "### Section");
}

func testPrepareDemotesNothingAtZero() {
    testing.assertContains(prepare("# Title\n", 0, ""), "# Title");
}

func testPrepareClampsAtSix() {
    testing.assertContains(prepare("###### Deep\n", 1, ""), "###### Deep");
}

# Headings and rules inside a fence are content, not structure.
func testPrepareLeavesFencedContentAlone() {
    def src as string init "# Real\n\n```sh\n# not a heading\n[not](a.md) link\n```\n";
    def out as string init prepare($src, 1, "");
    testing.assertContains($out, "## Real");
    testing.assertContains($out, "# not a heading");
    testing.assertContains($out, "[not](a.md) link");
}

# "Exactly as written" is load-bearing: an indented continuation that loses its
# indent stops belonging to its list item and becomes a stranded paragraph.
func testPrepareKeepsIndentation() {
    def src as string init "- item\n  continuation\n    deeper\n";
    def out as string init prepare($src, 0, "");
    testing.assertContains($out, "  continuation");
    testing.assertContains($out, "    deeper");
}

func testPrepareResolvesLinksOutsideFences() {
    testing.assertContains(prepare("see [x](y.md)\n", 0, ""), "see x");
}

func testPrepareSanitisesFirst() {
    testing.assertContains(
        prepare(convert.fromCodepoint(0x2192) + " onward\n", 0, ""),
        "-> onward");
}

# --- callouts --------------------------------------------------------

# The marker is the parser's to read, so this pass leaves it alone: it used to
# rewrite the line into a bold label, which is what `markdown.j` does for itself
# now.
func testPrepareLeavesTheMarkerToTheParser() {
    def out as string init prepare("> [!NOTE]\n> mind the gap\n", 0, "");
    testing.assertContains($out, "> [!NOTE]");
    testing.assertContains($out, "> mind the gap");
}

# The layout draws the label, and the words are Grimoire's, so the book's
# language reaches the layout as a table. Without it a German book would print
# "Note" over a panel whose page says "Hinweis".
func testPdfOptionsCarryTheTranslatedLabels() {
    locale.install("de");
    def c as config.Config init config.defaults();
    def labels as map of string to string init pdfOptions($c).admonitionLabels;
    testing.assertEqual($labels["note"], "Hinweis");
    testing.assertEqual($labels["caution"], "Achtung");
    locale.install("en");
    testing.assertEqual(pdfOptions($c).admonitionLabels["note"], "Note");
}

# Every other word on the page went through `prepare`; a label is handed to the
# layout as an option and never passes that way. Left raw it would be one `?`
# per character, so a Polish book would print a transliterated sentence under a
# label full of question marks.
func testTheLabelsAreTransliteratedLikeEverythingElse() {
    locale.install("pl");
    def labels as map of string to string init pdfOptions(config.defaults()).admonitionLabels;
    # Only what WinAnsi lacks is reduced: the `z` with a dot goes, the `o` with
    # an acute stays, because the fonts can draw that one.
    testing.assertEqual($labels["warning"], "Ostrzezenie");
    testing.assertEqual($labels["tip"], "Wskazówka");
    locale.install("en");
    testing.assertEqual(pdfOptions(config.defaults()).admonitionLabels["note"], "Note");
}

func testEveryKindReachesTheLayout() {
    locale.install("en");
    def labels as map of string to string init pdfOptions(config.defaults()).admonitionLabels;
    for (def kind in ["note", "tip", "important", "warning", "caution"]) {
        testing.assertTrue(maps.has($labels, $kind));
    }
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

# The dpi the layout reads a drawn picture's pixels at, which is the one control
# a book has over how big its screenshots come out on the page.
func testPdfOptionsFollowTheImageDpi() {
    def c as config.Config init book();
    testing.assertEqual(pdfOptions($c).imageDpi, 96);
    $c.pdfImageDpi = 192;
    testing.assertEqual(pdfOptions($c).imageDpi, 192);
}

# A visible marker beats a silent hole for anything `sanitize` did not already
# reach.
func testPdfOptionsMarkAnUnencodableCharacter() {
    testing.assertEqual(pdfOptions(book()).unencodable, "?");
}

# --- combine: where a part ends --------------------------------------
#
# A separator ends a part, and it is the only mark a `SUMMARY.md` has for saying
# so. Without one the state that demotes a chapter stays set from the first part
# onwards, and an appendix listed after the parts is demoted and page-broken as
# though it sat inside the last of them.

func chapters() {
    def root as string init fs.makeTempDir(os.tempDir(), "grimoire-parts-");
    fs.writeString(path.join($root, "intro.md"), "# Intro\n\nbefore the parts\n");
    fs.writeString(path.join($root, "one.md"), "# One\n\ninside the part\n");
    fs.writeString(path.join($root, "appendix.md"), "# Appendix\n\nafter the parts\n");
    return $root;
}

func partsConfig(root as string) {
    def c as config.Config init config.defaults();
    $c.srcDir = $root;
    $c.pdfTitlePage = false;
    return $c;
}

func page(title as string, src as string) {
    return summary.Entry{
        kind: summary.pageKind(),
        title: $title,
        src: $src,
        out: "",
        level: 0,
        number: ""
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

# The headings of the combined document, which is what decides the printed
# outline: a level-one heading takes a page of its own, a demoted one does not.
func headingsOf(text as string) {
    def out as list of string;
    for (def line in strings.split($text, "\n")) {
        if (strings.startsWith($line, "#")) {
            $out[] = $line;
        }
    }
    return $out;
}

func testCombineDemotesChaptersInsideAPart() {
    def root as string init chapters();
    def entries as list of summary.Entry init [
        page("Intro", "intro.md"),
        part("Part One"),
        page("One", "one.md")
    ];
    def headings as list of string init headingsOf(combine(partsConfig($root), $entries));
    testing.assertEqual($headings[0], "# Intro");
    testing.assertEqual($headings[1], "# Part One");
    testing.assertEqual($headings[2], "## One");
}

func testCombineEndsAPartAtASeparator() {
    def root as string init chapters();
    def entries as list of summary.Entry init [
        part("Part One"),
        page("One", "one.md"),
        separator(),
        page("Appendix", "appendix.md")
    ];
    def combined as string init combine(partsConfig($root), $entries);
    def headings as list of string init headingsOf($combined);
    testing.assertEqual($headings[0], "# Part One");
    testing.assertEqual($headings[1], "## One");
    testing.assertEqual($headings[2], "# Appendix");
    # A level-one heading breaks the page by itself, so the suffix chapter must
    # not also carry the directive a demoted chapter needs.
    testing.assertEqual(len(strings.split($combined, PAGE_BREAK)), 1);
}

# Without the separator the appendix belongs to the part, which is what the
# outline actually said.
func testCombineKeepsAChapterInThePartWithoutASeparator() {
    def root as string init chapters();
    def entries as list of summary.Entry init [
        part("Part One"),
        page("One", "one.md"),
        page("Appendix", "appendix.md")
    ];
    def headings as list of string init headingsOf(combine(partsConfig($root), $entries));
    testing.assertEqual($headings[2], "## Appendix");
}

# A separator before any part is not an end to anything, and must not disturb a
# book that has no parts at all.
func testCombineIgnoresASeparatorOutsideAPart() {
    def root as string init chapters();
    def entries as list of summary.Entry init [
        page("Intro", "intro.md"),
        separator(),
        page("Appendix", "appendix.md")
    ];
    def headings as list of string init headingsOf(combine(partsConfig($root), $entries));
    testing.assertEqual($headings[0], "# Intro");
    testing.assertEqual($headings[1], "# Appendix");
}
