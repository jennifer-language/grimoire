# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `content.j`, run by `jennifer test src/content_test.j`.
 *
 * This module decides what reaches a reader's browser, so escaping gets the most
 * attention: every path out of here escapes exactly once, `html_block` is the one
 * deliberate exception, and `javascript:` has to die at `href` no matter how it
 * is written. Those cases are security behaviour rather than formatting, and a
 * regression in them would look like nothing at all.
 *
 * The page walk is the other half - anchors assigned in document order and
 * disambiguated the way GitHub does, sections sliced at headings - because the
 * search index and the contents column are both built from what it returns.
 * @module content_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use strings;

# The interface strings are library state, and a code block carries a translated
# label on its copy button. Selecting English here keeps the expectations below
# readable whatever ran before.
func english() {
    locale.install("en");
}

# --- attrEsc ---------------------------------------------------------

# Attribute values are rendered inside double quotes, so the quote needs escaping
# on top of what `html.escape` does for text.
func testAttrEscCoversTheQuote() {
    testing.assertContains(attrEsc('say "hi"'), "&quot;");
    testing.assertFalse(strings.contains(attrEsc('say "hi"'), '"hi"'));
}

func testAttrEscStillEscapesMarkup() {
    testing.assertContains(attrEsc("a <b> & c"), "&lt;");
    testing.assertContains(attrEsc("a <b> & c"), "&amp;");
}

# --- href ------------------------------------------------------------

func testHrefRewritesAMarkdownTarget() {
    testing.assertEqual(href("guide/syntax.md"), "guide/syntax.html");
    testing.assertEqual(href("README.md"), "index.html");
}

func testHrefKeepsAFragmentOnTheRewrittenTarget() {
    testing.assertEqual(href("guide/syntax.md#lists"), "guide/syntax.html#lists");
}

func testHrefLeavesFragmentsAndExternalsAlone() {
    testing.assertEqual(href("#top"), "#top");
    testing.assertEqual(href("https://example.com/x"), "https://example.com/x");
    testing.assertEqual(href("mailto:a@b.c"), "mailto:a@b.c");
    testing.assertEqual(href(""), "");
}

func testHrefLeavesANonMarkdownTargetAlone() {
    testing.assertEqual(href("assets/diagram.png"), "assets/diagram.png");
}

# Everything is finally gated by `html.safeUrl`, so a script scheme can never
# survive - however it is spelled.
func testHrefDefusesAScriptScheme() {
    for (def url in ["javascript:alert(1)", "JaVaScRiPt:alert(1)", "  javascript:alert(1)"]) {
        testing.assertFalse(strings.contains(strings.lower(href($url)), "javascript:"));
    }
    testing.assertFalse(strings.contains(strings.lower(href("data:text/html,x")), "data:"));
}

# --- inline ----------------------------------------------------------

# Outline titles are Markdown but must not become block elements in a sidebar row.
func testInlineRendersSpansWithoutABlockWrapper() {
    testing.assertEqual(inline("plain"), "plain");
    testing.assertEqual(inline("`code`"), "<code>code</code>");
    testing.assertEqual(inline("**bold**"), "<strong>bold</strong>");
    testing.assertFalse(strings.contains(inline("plain"), "<p>"));
}

# Inline spans nest, which is what keeps a bold code span both bold and
# monospaced rather than one or the other.
func testInlineNestsSpans() {
    testing.assertEqual(inline("**`json.Value`**"), "<strong><code>json.Value</code></strong>");
}

func testInlineEscapes() {
    testing.assertContains(inline("a < b"), "&lt;");
}

func testInlineOfNothingIsNothing() {
    testing.assertEqual(inline(""), "");
}

# --- render: the body ------------------------------------------------

func testRenderWrapsParagraphs() {
    english();
    testing.assertContains(render("Some prose.", false, true).html, "<p>Some prose.</p>");
}

func testRenderBuildsLists() {
    english();
    def html as string init render("- one\n- two\n", false, true).html;
    testing.assertContains($html, "<ul>");
    testing.assertContains($html, "<li>one</li>");
    def ordered as string init render("1. one\n2. two\n", false, true).html;
    testing.assertContains($ordered, "<ol>");
}

func testRenderBuildsTables() {
    english();
    def html as string init render("| A | B |\n| - | - |\n| 1 | 2 |\n", false, true).html;
    testing.assertContains($html, '<div class="gr-tablewrap">');
    testing.assertContains($html, "<th>A</th>");
    testing.assertContains($html, "<td>1</td>");
}

func testRenderMarksCellAlignment() {
    english();
    def html as string init render("| A | B |\n| - | --: |\n| 1 | 2 |\n", false, true).html;
    testing.assertContains($html, 'data-align="right"');
    def centred as string init render("| A |\n| :-: |\n| 1 |\n", false, true).html;
    testing.assertContains($centred, 'data-align="center"');
}

# The attribute is emitted only for the two alignments the stylesheet can act on.
# The `markdown` module spells an unaligned cell "none" now and spelled it ""
# before; an exclusion list let the new spelling through and stamped
# `data-align="none"` onto every cell of every table in the book.
func testRenderLeavesAnUnalignedCellBare() {
    english();
    def html as string init render("| A | B |\n| - | - |\n| 1 | 2 |\n", false, true).html;
    testing.assertFalse(strings.contains($html, "data-align"));
    testing.assertContains($html, "<th>A</th>");
    testing.assertContains($html, "<td>1</td>");
}

func testRenderBuildsQuotesAndRules() {
    english();
    testing.assertContains(render("> quoted\n", false, true).html, "<blockquote>");
    testing.assertContains(render("---\n", false, true).html, "<hr>");
}

func testRenderGivesEveryCodeBlockACopyButton() {
    english();
    def html as string init render("```sh\necho hi\n```\n", false, true).html;
    testing.assertContains($html, '<div class="gr-codeblock">');
    testing.assertContains($html, '<button class="gr-copy"');
    testing.assertContains($html, '<span class="gr-lang">sh</span>');
    testing.assertContains($html, 'class="language-sh"');
}

func testRenderHighlightsOnlyWhenAsked() {
    english();
    def src as string init "```jennifer\ndef x as int init 1;\n```\n";
    testing.assertFalse(strings.contains(render($src, false, true).html, "hljs-keyword"));
    testing.assertContains(render($src, true, true).html, "hljs-keyword");
}

# The `hljs` class marks a block as already highlighted, so the highlight.js
# runtime leaves it alone instead of repainting work that is already on the page.
func testAHighlightedBlockIsMarkedForTheRuntime() {
    english();
    def html as string init render("```jennifer\ndef x;\n```\n", true, true).html;
    testing.assertContains($html, "hljs");
}

func testRenderDoesNotHighlightAnUnknownLanguage() {
    english();
    def html as string init render("```go\nvar x = 1\n```\n", true, true).html;
    testing.assertFalse(strings.contains($html, "hljs-keyword"));
}

# --- render: escaping ------------------------------------------------

func testRenderEscapesProse() {
    english();
    def html as string init render("a < b & c", false, true).html;
    testing.assertContains($html, "&lt;");
    testing.assertContains($html, "&amp;");
}

func testRenderEscapesCodeExactlyOnce() {
    english();
    def html as string init render("```\n<script>\n```\n", false, true).html;
    testing.assertContains($html, "&lt;script&gt;");
    testing.assertFalse(strings.contains($html, "&amp;lt;"));
}

# --- the one thing that reaches the page unescaped -------------------

# A hand-written block goes to the page verbatim - that is the point of writing
# it, and it comes from the book's own source. Everything else on the page is
# escaped, so this is the one exception, it is deliberate, and `rawHtml` is the
# only thing that changes it.
func testAHtmlBlockIsVerbatimByDefault() {
    english();
    testing.assertContains(
        render('<div class="custom">x</div>\n', false, true).html,
        '<div class="custom">');
}

func testAHtmlBlockIsEscapedWhenRawHtmlIsOff() {
    english();
    def html as string init render('<div class="custom">x</div>\n', false, false).html;
    testing.assertContains($html, "&lt;div");
    testing.assertFalse(strings.contains($html, '<div class="custom">'));
}

# The case the setting exists for: a book assembled from Markdown its author did
# not write. The markup is shown rather than run.
func testRawHtmlOffDefusesAScriptBlock() {
    english();
    def hostile as string init "<script>alert(1)</script>\n\n<img src=x onerror=alert(2)>\n";
    testing.assertContains(render($hostile, false, true).html, "<script>");
    # The angle brackets are the whole of it. `onerror=alert(2)` survives as
    # text and is inert there; what must not survive is a tag to hang it on.
    def safe as string init render($hostile, false, false).html;
    testing.assertFalse(strings.contains($safe, "<script>"));
    testing.assertFalse(strings.contains($safe, "<img"));
    testing.assertContains($safe, "&lt;script&gt;");
    testing.assertContains($safe, "&lt;img");
}

# A quote renders its children through the block path, so the setting has to
# reach that far down - it is the one nesting that could have been missed.
func testRawHtmlReachesInsideAQuote() {
    english();
    def src as string init "> quoted\n>\n> <script>alert(1)</script>\n";
    testing.assertContains(render($src, false, true).html, "<script>");
    testing.assertFalse(strings.contains(render($src, false, false).html, "<script>"));
}

# Inline HTML needs no setting and never did: the parser hands `a <b>x</b> c`
# back as one text node, so the inline path escapes it like any other text. Worth
# pinning, because it is the reason `rawHtml` threads through three functions
# rather than through the whole renderer.
func testInlineHtmlIsAlwaysEscaped() {
    english();
    def src as string init "a <b>bold</b> and <img src=x onerror=alert(1)> c";
    for (def raw in [true, false]) {
        def html as string init render($src, false, $raw).html;
        testing.assertContains($html, "&lt;b&gt;");
        testing.assertContains($html, "&lt;img");
        testing.assertFalse(strings.contains($html, "<b>bold</b>"));
        testing.assertFalse(strings.contains($html, "<img"));
    }
}

# Turning it off must not touch anything else: prose, lists, tables, code and
# links render the same either way.
func testRawHtmlOffChangesNothingElse() {
    english();
    def src as string init "# T\n\n- one\n- two\n\n| A | B |\n| - | - |\n| 1 | 2 |\n\n" +
        "```sh\necho hi\n```\n\n[a link](x.md) and `code`.\n";
    testing.assertEqual(render($src, false, true).html, render($src, false, false).html);
}

func testRenderMarksExternalLinks() {
    english();
    def html as string init render("[out](https://example.com)", false, true).html;
    testing.assertContains($html, 'rel="noopener noreferrer"');
    testing.assertFalse(strings.contains(render("[in](x.md)", false, true).html, "noopener"));
}

func testRenderLazyLoadsImages() {
    english();
    testing.assertContains(render("![alt](x.png)", false, true).html, 'loading="lazy"');
}

# --- render: headings, anchors, and the title ------------------------

func testRenderTakesTheTitleFromTheFirstLevelOne() {
    english();
    testing.assertEqual(render("# The Title\n\nBody\n", false, true).title, "The Title");
    testing.assertEqual(render("## Only a two\n", false, true).title, "");
}

func testRenderIgnoresALaterLevelOne() {
    english();
    testing.assertEqual(render("# First\n\n# Second\n", false, true).title, "First");
}

func testRenderCollectsHeadingsInOrder() {
    english();
    def r as Rendered init render("# One\n\n## Two\n\n### Three\n", false, true);
    testing.assertEqual(len($r.headings), 3);
    testing.assertEqual($r.headings[0].level, 1);
    testing.assertEqual($r.headings[1].text, "Two");
    testing.assertEqual($r.headings[2].level, 3);
}

func testRenderAnchorsEveryHeading() {
    english();
    def r as Rendered init render("## Getting Started\n", false, true);
    testing.assertEqual($r.headings[0].id, "getting-started");
    testing.assertContains($r.html, 'id="getting-started"');
    testing.assertContains($r.html, '<a class="gr-anchor" href="#getting-started"');
}

# A repeated heading still gets a stable, distinct link, the way GitHub does it.
func testRenderDisambiguatesRepeatedHeadings() {
    english();
    def r as Rendered init render("## Notes\n\n## Notes\n\n## Notes\n", false, true);
    testing.assertEqual($r.headings[0].id, "notes");
    testing.assertEqual($r.headings[1].id, "notes-1");
    testing.assertEqual($r.headings[2].id, "notes-2");
}

func testRenderIsDeterministic() {
    english();
    def src as string init "# A\n\ntext\n\n## B\n\nmore\n";
    testing.assertEqual(render($src, false, true).html, render($src, false, true).html);
}

# --- render: the sections the search index is built from -------------

func testRenderSlicesAtHeadings() {
    english();
    def r as Rendered init render("# One\n\nfirst body\n\n## Two\n\nsecond body\n", false, true);
    testing.assertEqual(len($r.sections), 2);
    testing.assertEqual($r.sections[0].heading, "One");
    testing.assertContains($r.sections[0].text, "first body");
    testing.assertEqual($r.sections[1].anchor, "two");
    testing.assertContains($r.sections[1].text, "second body");
}

func testRenderKeepsALeadInSection() {
    english();
    def r as Rendered init render("intro prose\n\n## A heading\n\nbody\n", false, true);
    testing.assertEqual($r.sections[0].heading, "");
    testing.assertEqual($r.sections[0].anchor, "");
    testing.assertContains($r.sections[0].text, "intro prose");
}

# Nobody searches for a `<div>`: raw markup and a rule are structure rather than
# prose, so neither reaches the index.
func testRenderKeepsMarkupAndRulesOutOfTheIndex() {
    english();
    def r as Rendered init render("# T\n\n<div>raw</div>\n\n---\n\nreal prose\n", false, true);
    testing.assertContains($r.sections[0].text, "real prose");
    testing.assertFalse(strings.contains($r.sections[0].text, "raw"));
}

# --- admonitions -----------------------------------------------------

# The five GitHub kinds, each labelled in the interface language and each
# carrying the class the theme's ramp reads.
func testEveryKindRendersItsOwnPanel() {
    english();
    for (def kind in ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"]) {
        def html as string init render("> [" + "!" + $kind + "]\n> body\n", false, true).html;
        testing.assertContains($html, 'class="gr-adm gr-adm-' + strings.lower($kind) + '"');
        testing.assertContains($html, '<p class="gr-adm-label">');
        testing.assertContains($html, "<p>body</p>");
        testing.assertFalse(strings.contains($html, "<blockquote>"));
    }
}

# The label is Grimoire's word, not the author's, so it follows the book rather
# than the source.
func testTheLabelIsTranslated() {
    english();
    testing.assertContains(render("> [!NOTE]\n> x\n", false, true).html, ">Note</p>");
    locale.install("de");
    testing.assertContains(render("> [!NOTE]\n> x\n", false, true).html, ">Hinweis</p>");
    english();
}

# GitHub writes the marker in capitals; a book that lowercases it means the same
# thing.
func testTheMarkerIsCaseInsensitive() {
    english();
    testing.assertContains(render("> [!note]\n> x\n", false, true).html, "gr-adm-note");
    testing.assertContains(render("> [!Warning]\n> x\n", false, true).html, "gr-adm-warning");
}

# Everything the quote holds belongs to the callout, not just its first
# paragraph.
func testTheWholeQuoteIsTheCallout() {
    english();
    def html as string init render("> [!TIP]\n> first\n>\n> - a\n> - b\n", false, true).html;
    testing.assertContains($html, "<p>first</p>");
    testing.assertContains($html, "<ul><li>a</li><li>b</li></ul>");
    testing.assertEqual(len(strings.split($html, "<div class=")), 2);
}

# The marker comes off the front of the rendered paragraph, so the markup in it
# has to survive the cut.
func testInlineMarkupSurvivesTheMarker() {
    english();
    def html as string init render("> [!NOTE]\n> a **b** `c`\n", false, true).html;
    testing.assertContains($html, "<p>a <strong>b</strong> <code>c</code></p>");
}

# A marker with nothing after it is a callout with no body rather than one with
# an empty paragraph in it.
func testAMarkerAloneHasNoEmptyParagraph() {
    english();
    def html as string init render("> [!NOTE]\n", false, true).html;
    testing.assertContains($html, 'class="gr-adm gr-adm-note"');
    testing.assertFalse(strings.contains($html, "<p></p>"));
}

# Everything that is not one of the five is a quotation, which is what every
# other renderer makes of the same source.
func testWhatIsNotACalloutStaysAQuote() {
    english();
    for (def md in [
        "> [!NOTES]\n> x\n",
        "> [!NOTE]: x\n",
        "> [!]\n> x\n",
        "> quoted\n",
        "> **[!NOTE]** x\n"
    ]) {
        def html as string init render($md, false, true).html;
        testing.assertContains($html, "<blockquote>");
        testing.assertFalse(strings.contains($html, "gr-adm"));
    }
}

# A callout is prose and belongs in the index; its marker is machinery and does
# not. Indexed, `[!NOTE]` would be findable text on every page that warns about
# anything.
func testTheMarkerIsNotIndexed() {
    english();
    def r as Rendered init render("# T\n\n> [!WARNING]\n> mind the gap\n", false, true);
    testing.assertContains($r.sections[0].text, "mind the gap");
    testing.assertFalse(strings.contains($r.sections[0].text, "[!"));
    testing.assertFalse(strings.contains($r.sections[0].text, "WARNING"));
}

# The label is chrome. It is drawn on the page in the reader's language and has
# no business in a search record.
func testTheLabelIsNotIndexed() {
    english();
    def r as Rendered init render("# T\n\n> [!NOTE]\n> body\n", false, true);
    testing.assertFalse(strings.contains($r.sections[0].text, "Note"));
}

# A callout holds blocks, not just paragraphs: what is inside the quotation is
# inside the panel.
func testACalloutHoldsWholeBlocks() {
    english();
    def md as string init "> [!IMPORTANT]\n> lead\n>\n> ```sh\n> echo hi\n> ```\n";
    def html as string init render($md, false, true).html;
    testing.assertContains($html, "gr-adm-important");
    testing.assertContains($html, '<div class="gr-codeblock">');
    testing.assertContains($html, "echo hi");
}

# A quotation nested in a callout is read the same way the outer one was, so a
# callout can hold a callout. Nothing needs it, but the alternative is a panel
# with a stray `[!TIP]` in it.
func testACalloutCanHoldACallout() {
    english();
    def md as string init "> [!WARNING]\n> outer\n>\n> > [!TIP]\n> > inner\n";
    def html as string init render($md, false, true).html;
    testing.assertContains($html, "gr-adm-warning");
    testing.assertContains($html, "gr-adm-tip");
    testing.assertContains($html, "<p>inner</p>");
    testing.assertFalse(strings.contains($html, "[!TIP]"));
}

# --- admonition titles -----------------------------------------------

# A callout nested in a quotation, or in another callout, prints its title on
# the page like any other - and a title is an attribute rather than a child, so
# nothing else in the walk would have found it. Unfindable words that are
# visible on the page is the worst shape a search index has.
func testANestedTitleIsIndexed() {
    english();
    def md as string init "# T\n\n> quoting\n>\n> > [!TIP] SentinelTitle\n> > inner\n";
    testing.assertContains(render($md, false, true).sections[0].text, "SentinelTitle");
}

func testATitleInsideACalloutIsIndexed() {
    english();
    def md as string init "# T\n\n> [!NOTE] Outer\n> a\n>\n> > [!WARNING] Inner\n> > b\n";
    def text as string init render($md, false, true).sections[0].text;
    testing.assertContains($text, "Outer");
    testing.assertContains($text, "Inner");
}

# The titles lead, because the body is truncated to `searchBodyChars` and a
# title that went in at its own position could be cut off the end of the long
# section it was announcing.
func testTitlesLeadTheRecord() {
    english();
    def r as Rendered init render("# T\n\n> [!NOTE] TheTitle\n> the body\n", false, true);
    def text as string init $r.sections[0].text;
    testing.assertTrue(strings.indexOf($text, "TheTitle") < strings.indexOf($text, "the body"));
}

# A page with no callouts pays nothing and reads the same as it always did.
func testAPageWithoutCalloutsIsUnchanged() {
    english();
    def r as Rendered init render("# T\n\n> quoted\n\n- a\n- b\n\npara\n", false, true);
    testing.assertEqual($r.sections[0].text, "quoted ab para");
}

# A marker can carry a title, and a title is the author speaking: it is used as
# written, and marked so the sheet does not put it in small capitals the way it
# does a standing label.
func testATitleBecomesTheLabel() {
    english();
    def html as string init render("> [!NOTE] Mind the gap\n> body\n", false, true).html;
    testing.assertContains($html, '<p class="gr-adm-label gr-adm-titled">Mind the gap</p>');
    testing.assertFalse(strings.contains($html, ">Note</p>"));
    testing.assertContains($html, "<p>body</p>");
}

func testATitleIsEscaped() {
    english();
    testing.assertContains(
        render("> [!TIP] a <b> & c\n> body\n", false, true).html,
        "a &lt;b&gt; &amp; c");
}

# Without a title the standing label stands, and it follows the book rather than
# the source.
func testWithoutATitleTheLabelIsTranslated() {
    english();
    testing.assertContains(render("> [!NOTE]\n> x\n", false, true).html, ">Note</p>");
    locale.install("de");
    testing.assertContains(render("> [!NOTE]\n> x\n", false, true).html, ">Hinweis</p>");
    english();
}

# The parser keeps the marker out of the text, so nothing has to strip it. The
# title is an attribute rather than a child, so it would be missed instead -
# and a title is the author's words, which belong in the index the way a heading
# does.
func testTheTitleIsIndexedAndTheLabelIsNot() {
    english();
    def r as Rendered init render("# T\n\n> [!WARNING] Mind the gap\n> body\n", false, true);
    testing.assertContains($r.sections[0].text, "Mind the gap");
    testing.assertContains($r.sections[0].text, "body");
    testing.assertFalse(strings.contains($r.sections[0].text, "[!"));
    def plain as Rendered init render("# T\n\n> [!NOTE]\n> body\n", false, true);
    testing.assertFalse(strings.contains($plain.sections[0].text, "Note"));
}

func testRenderOfNothingIsEmpty() {
    english();
    def r as Rendered init render("", false, true);
    testing.assertEqual($r.html, "");
    testing.assertEqual($r.title, "");
    testing.assertEqual(len($r.headings), 0);
    testing.assertEqual(len($r.sections), 0);
}

# --- tocHtml ---------------------------------------------------------

func testTocHtmlListsLevelTwoAndDeeper() {
    english();
    def r as Rendered init render("# One\n\n## Two\n\n### Three\n", false, true);
    def toc as string init tocHtml($r.headings, 3);
    testing.assertContains($toc, "<ol>");
    testing.assertContains($toc, 'href="#two"');
    testing.assertContains($toc, 'data-level="3"');
    testing.assertFalse(strings.contains($toc, 'href="#one"'));
}

func testTocHtmlHonoursTheDepth() {
    english();
    def r as Rendered init render("## A\n\n### B\n\n#### C\n", false, true);
    testing.assertFalse(strings.contains(tocHtml($r.headings, 2), 'href="#b"'));
    testing.assertContains(tocHtml($r.headings, 3), 'href="#b"');
    testing.assertFalse(strings.contains(tocHtml($r.headings, 3), 'href="#c"'));
}

# A single entry is noise, not navigation.
func testTocHtmlNeedsTwoEntries() {
    english();
    testing.assertEqual(tocHtml(render("## Only one\n", false, true).headings, 3), "");
    testing.assertEqual(tocHtml(render("# Just a title\n", false, true).headings, 3), "");
    testing.assertNotEqual(tocHtml(render("## A\n\n## B\n", false, true).headings, 3), "");
}

func testTocHtmlEscapesHeadingText() {
    english();
    def r as Rendered init render("## a < b\n\n## c & d\n", false, true);
    def toc as string init tocHtml($r.headings, 3);
    testing.assertContains($toc, "&lt;");
    testing.assertContains($toc, "&amp;");
}
