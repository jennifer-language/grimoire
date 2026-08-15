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
    testing.assertContains(render("Some prose.", false).html, "<p>Some prose.</p>");
}

func testRenderBuildsLists() {
    english();
    def html as string init render("- one\n- two\n", false).html;
    testing.assertContains($html, "<ul>");
    testing.assertContains($html, "<li>one</li>");
    def ordered as string init render("1. one\n2. two\n", false).html;
    testing.assertContains($ordered, "<ol>");
}

func testRenderBuildsTables() {
    english();
    def html as string init render("| A | B |\n| - | - |\n| 1 | 2 |\n", false).html;
    testing.assertContains($html, '<div class="gr-tablewrap">');
    testing.assertContains($html, "<th>A</th>");
    testing.assertContains($html, "<td>1</td>");
}

func testRenderMarksCellAlignment() {
    english();
    def html as string init render("| A | B |\n| - | --: |\n| 1 | 2 |\n", false).html;
    testing.assertContains($html, 'data-align="right"');
    def centred as string init render("| A |\n| :-: |\n| 1 |\n", false).html;
    testing.assertContains($centred, 'data-align="center"');
}

# The attribute is emitted only for the two alignments the stylesheet can act on.
# The `markdown` module spells an unaligned cell "none" now and spelled it ""
# before; an exclusion list let the new spelling through and stamped
# `data-align="none"` onto every cell of every table in the book.
func testRenderLeavesAnUnalignedCellBare() {
    english();
    def html as string init render("| A | B |\n| - | - |\n| 1 | 2 |\n", false).html;
    testing.assertFalse(strings.contains($html, "data-align"));
    testing.assertContains($html, "<th>A</th>");
    testing.assertContains($html, "<td>1</td>");
}

func testRenderBuildsQuotesAndRules() {
    english();
    testing.assertContains(render("> quoted\n", false).html, "<blockquote>");
    testing.assertContains(render("---\n", false).html, "<hr>");
}

func testRenderGivesEveryCodeBlockACopyButton() {
    english();
    def html as string init render("```sh\necho hi\n```\n", false).html;
    testing.assertContains($html, '<div class="gr-codeblock">');
    testing.assertContains($html, '<button class="gr-copy"');
    testing.assertContains($html, '<span class="gr-lang">sh</span>');
    testing.assertContains($html, 'class="language-sh"');
}

func testRenderHighlightsOnlyWhenAsked() {
    english();
    def src as string init "```jennifer\ndef x as int init 1;\n```\n";
    testing.assertFalse(strings.contains(render($src, false).html, "hljs-keyword"));
    testing.assertContains(render($src, true).html, "hljs-keyword");
}

# The `hljs` class marks a block as already highlighted, so the highlight.js
# runtime leaves it alone instead of repainting work that is already on the page.
func testAHighlightedBlockIsMarkedForTheRuntime() {
    english();
    def html as string init render("```jennifer\ndef x;\n```\n", true).html;
    testing.assertContains($html, "hljs");
}

func testRenderDoesNotHighlightAnUnknownLanguage() {
    english();
    def html as string init render("```go\nvar x = 1\n```\n", true).html;
    testing.assertFalse(strings.contains($html, "hljs-keyword"));
}

# --- render: escaping ------------------------------------------------

func testRenderEscapesProse() {
    english();
    def html as string init render("a < b & c", false).html;
    testing.assertContains($html, "&lt;");
    testing.assertContains($html, "&amp;");
}

func testRenderEscapesCodeExactlyOnce() {
    english();
    def html as string init render("```\n<script>\n```\n", false).html;
    testing.assertContains($html, "&lt;script&gt;");
    testing.assertFalse(strings.contains($html, "&amp;lt;"));
}

# A hand-written block goes to the page verbatim - that is the point of writing
# it, and it comes from the book's own source. Everything else on the page is
# escaped, so this is the one exception and it is deliberate.
func testAHtmlBlockIsVerbatim() {
    english();
    testing.assertContains(
        render('<div class="custom">x</div>\n', false).html,
        '<div class="custom">');
}

func testRenderMarksExternalLinks() {
    english();
    def html as string init render("[out](https://example.com)", false).html;
    testing.assertContains($html, 'rel="noopener noreferrer"');
    testing.assertFalse(strings.contains(render("[in](x.md)", false).html, "noopener"));
}

func testRenderLazyLoadsImages() {
    english();
    testing.assertContains(render("![alt](x.png)", false).html, 'loading="lazy"');
}

# --- render: headings, anchors, and the title ------------------------

func testRenderTakesTheTitleFromTheFirstLevelOne() {
    english();
    testing.assertEqual(render("# The Title\n\nBody\n", false).title, "The Title");
    testing.assertEqual(render("## Only a two\n", false).title, "");
}

func testRenderIgnoresALaterLevelOne() {
    english();
    testing.assertEqual(render("# First\n\n# Second\n", false).title, "First");
}

func testRenderCollectsHeadingsInOrder() {
    english();
    def r as Rendered init render("# One\n\n## Two\n\n### Three\n", false);
    testing.assertEqual(len($r.headings), 3);
    testing.assertEqual($r.headings[0].level, 1);
    testing.assertEqual($r.headings[1].text, "Two");
    testing.assertEqual($r.headings[2].level, 3);
}

func testRenderAnchorsEveryHeading() {
    english();
    def r as Rendered init render("## Getting Started\n", false);
    testing.assertEqual($r.headings[0].id, "getting-started");
    testing.assertContains($r.html, 'id="getting-started"');
    testing.assertContains($r.html, '<a class="gr-anchor" href="#getting-started"');
}

# A repeated heading still gets a stable, distinct link, the way GitHub does it.
func testRenderDisambiguatesRepeatedHeadings() {
    english();
    def r as Rendered init render("## Notes\n\n## Notes\n\n## Notes\n", false);
    testing.assertEqual($r.headings[0].id, "notes");
    testing.assertEqual($r.headings[1].id, "notes-1");
    testing.assertEqual($r.headings[2].id, "notes-2");
}

func testRenderIsDeterministic() {
    english();
    def src as string init "# A\n\ntext\n\n## B\n\nmore\n";
    testing.assertEqual(render($src, false).html, render($src, false).html);
}

# --- render: the sections the search index is built from -------------

func testRenderSlicesAtHeadings() {
    english();
    def r as Rendered init render("# One\n\nfirst body\n\n## Two\n\nsecond body\n", false);
    testing.assertEqual(len($r.sections), 2);
    testing.assertEqual($r.sections[0].heading, "One");
    testing.assertContains($r.sections[0].text, "first body");
    testing.assertEqual($r.sections[1].anchor, "two");
    testing.assertContains($r.sections[1].text, "second body");
}

func testRenderKeepsALeadInSection() {
    english();
    def r as Rendered init render("intro prose\n\n## A heading\n\nbody\n", false);
    testing.assertEqual($r.sections[0].heading, "");
    testing.assertEqual($r.sections[0].anchor, "");
    testing.assertContains($r.sections[0].text, "intro prose");
}

# Nobody searches for a `<div>`: raw markup and a rule are structure rather than
# prose, so neither reaches the index.
func testRenderKeepsMarkupAndRulesOutOfTheIndex() {
    english();
    def r as Rendered init render("# T\n\n<div>raw</div>\n\n---\n\nreal prose\n", false);
    testing.assertContains($r.sections[0].text, "real prose");
    testing.assertFalse(strings.contains($r.sections[0].text, "raw"));
}

func testRenderOfNothingIsEmpty() {
    english();
    def r as Rendered init render("", false);
    testing.assertEqual($r.html, "");
    testing.assertEqual($r.title, "");
    testing.assertEqual(len($r.headings), 0);
    testing.assertEqual(len($r.sections), 0);
}

# --- tocHtml ---------------------------------------------------------

func testTocHtmlListsLevelTwoAndDeeper() {
    english();
    def r as Rendered init render("# One\n\n## Two\n\n### Three\n", false);
    def toc as string init tocHtml($r.headings, 3);
    testing.assertContains($toc, "<ol>");
    testing.assertContains($toc, 'href="#two"');
    testing.assertContains($toc, 'data-level="3"');
    testing.assertFalse(strings.contains($toc, 'href="#one"'));
}

func testTocHtmlHonoursTheDepth() {
    english();
    def r as Rendered init render("## A\n\n### B\n\n#### C\n", false);
    testing.assertFalse(strings.contains(tocHtml($r.headings, 2), 'href="#b"'));
    testing.assertContains(tocHtml($r.headings, 3), 'href="#b"');
    testing.assertFalse(strings.contains(tocHtml($r.headings, 3), 'href="#c"'));
}

# A single entry is noise, not navigation.
func testTocHtmlNeedsTwoEntries() {
    english();
    testing.assertEqual(tocHtml(render("## Only one\n", false).headings, 3), "");
    testing.assertEqual(tocHtml(render("# Just a title\n", false).headings, 3), "");
    testing.assertNotEqual(tocHtml(render("## A\n\n## B\n", false).headings, 3), "");
}

func testTocHtmlEscapesHeadingText() {
    english();
    def r as Rendered init render("## a < b\n\n## c & d\n", false);
    def toc as string init tocHtml($r.headings, 3);
    testing.assertContains($toc, "&lt;");
    testing.assertContains($toc, "&amp;");
}
