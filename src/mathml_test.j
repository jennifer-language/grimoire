# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.28.0

/**
 * White-box tests for `mathml.j`, run by `jennifer test src/mathml_test.j`.
 *
 * The check that lets an element through is the part worth the most cases:
 * whatever it accepts reaches the site and the EPUB as markup.
 * @module mathml_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;

import "markdown.j" as markdown;

def const OPEN as string init '<math xmlns="http://www.w3.org/1998/Math/MathML">';

# An inline element the way a preprocessor writes it: Markdown punctuation in
# the text as numeric entities, so the parser leaves it as text.
def const INLINE as string init '<math xmlns="http://www.w3.org/1998/Math/MathML"><semantics>' +
    '<mrow><mi>a</mi><mo>&#42;</mo><msub><mi>x</mi><mn>1</mn></msub></mrow>' +
    '<annotation encoding="application/x-tex">a&#42;x&#95;1 &lt; 2</annotation>' +
    '</semantics></math>';

def const DISPLAY as string init
    '<math xmlns="http://www.w3.org/1998/Math/MathML" display="block">' + "\n" +
    '<semantics><mfrac><mi>a</mi><mi>b</mi></mfrac>' +
    '<annotation encoding="application/x-tex">\frac{a}{b}</annotation></semantics></math>';

func paragraph(md as string) {
    return markdown.parse($md).children[0];
}

# --- accepted ---------------------------------------------------------

func testMathMlIsAccepted() {
    testing.assertTrue(accepted(OPEN + "<mi>x</mi></math>"));
    testing.assertTrue(accepted(DISPLAY));
    testing.assertTrue(accepted('  ' + OPEN +
        '<mstyle mathcolor="#cc0000"><mi>x</mi></mstyle></math>'));
}

# Anything that is not all MathML, or that could run or fetch something, is
# raw HTML and keeps the treatment raw HTML gets.
func testAnythingElseIsRefused() {
    testing.assertFalse(accepted("<math><mi>x</mi></math>"));
    testing.assertFalse(accepted('<math xmlns="http://www.w3.org/1999/xhtml">x</math>'));
    testing.assertFalse(accepted(
        OPEN + '<h:b xmlns:h="http://www.w3.org/1999/xhtml">x</h:b></math>'));
    testing.assertFalse(accepted(OPEN + '<mi onclick="x()">x</mi></math>'));
    testing.assertFalse(accepted(OPEN + '<mi ONMOUSEOVER="x()">x</mi></math>'));
    testing.assertFalse(accepted(OPEN + '<mi href="https://e.com">x</mi></math>'));
    testing.assertFalse(accepted(OPEN + '<mi style="color:red">x</mi></math>'));
    testing.assertFalse(accepted(
        OPEN + '<mi xmlns:xl="http://www.w3.org/1999/xlink" xl:href="x">x</mi></math>'));
    testing.assertFalse(accepted(OPEN + "<mi>x</math>"));
    testing.assertFalse(accepted('<mathx xmlns="http://www.w3.org/1998/Math/MathML"/>'));
    testing.assertFalse(accepted("text " + OPEN + "</math>"));
}

func testTheTexAndTheModeAreRead() {
    testing.assertEqual(texOf(DISPLAY), '\frac{a}{b}');
    testing.assertEqual(texOf(OPEN + "<mi>x</mi></math>"), "");
    testing.assertTrue(isDisplay(DISPLAY));
    testing.assertFalse(isDisplay(INLINE));
}

# --- finding it in a tree ---------------------------------------------

func testAnInlineElementIsPutBackTogether() {
    def p as doctree.Node init paragraph("Before " + INLINE + " after.\n");
    def found as list of Run init runs($p.children);
    testing.assertEqual(len($found), 1);
    testing.assertEqual($p.children[$found[0].first].text, OPEN);
    testing.assertEqual($p.children[$found[0].last].text, "</math>");
    # The text the parser decoded is escaped again, so the markup is XML.
    testing.assertContains($found[0].markup, "a*x_1 &lt; 2");
    testing.assertTrue(accepted($found[0].markup));
}

# Emphasis between the tags means the parser read Markdown in there, and the
# run is not the element it looks like.
func testARunWithMarkdownInItIsNotMaths() {
    def p as doctree.Node init paragraph(OPEN + "<mi>a</mi> *b* <mi>c</mi></math>\n");
    testing.assertEqual(len(runs($p.children)), 0);
    def open as doctree.Node init paragraph("x " + OPEN + "<mi>a</mi> and no end\n");
    testing.assertEqual(len(runs($open.children)), 0);
}

func testADisplayBlockIsFound() {
    def doc as doctree.Node init markdown.parse("text\n\n" + DISPLAY + "\n\nmore\n");
    testing.assertEqual(blockMarkup($doc.children[1]), DISPLAY);
    testing.assertEqual(blockMarkup($doc.children[0]), "");
    testing.assertTrue(holds($doc));
    def other as doctree.Node init markdown.parse('<div class="x">\nhi\n</div>\n');
    testing.assertEqual(blockMarkup($other.children[0]), "");
    testing.assertFalse(holds($other));
}

func testMathsInsideAListIsFound() {
    testing.assertTrue(holds(markdown.parse("- item " + INLINE + "\n")));
}

# --- rewriting --------------------------------------------------------

func testDropTakesTheMathsOut() {
    def md as string init "Before " + INLINE + " after.\n\n" + DISPLAY + "\n";
    def doc as doctree.Node init markdown.parse($md);
    def out as doctree.Node init rewrite($doc, "drop", 0).node;
    testing.assertEqual(len($out.children), 1);
    testing.assertEqual(doctree.text($out.children[0]), "Before  after.");
}

func testMarkLeavesPlaceholdersInOrder() {
    def doc as doctree.Node init markdown.parse("A " + INLINE + "\n\n" + DISPLAY + "\n");
    def r as Rewritten init rewrite($doc, "mark", 0);
    testing.assertEqual(len($r.taken), 2);
    testing.assertTrue(isDisplay($r.taken[1]));
    testing.assertEqual(doctree.text($r.node.children[0]), "A " + placeholder(0));
    testing.assertEqual($r.node.children[1].text, placeholder(1));
}

# Print gets the TeX source: a code span inline, centred lines for display.
func testTexPrintsTheSource() {
    def doc as doctree.Node init markdown.parse("A " + INLINE + "\n\n" + DISPLAY + "\n");
    def out as doctree.Node init rewrite($doc, "tex", 40).node;
    def inline as doctree.Node init $out.children[0].children[1];
    testing.assertEqual($inline.kind, "codespan");
    testing.assertEqual($inline.text, "a*x_1 < 2");
    def block as doctree.Node init $out.children[1];
    testing.assertEqual($block.kind, "paragraph");
    testing.assertEqual($block.children[0].kind, "codespan");
    # (40 - 11) // 2 no-break spaces, then a space, then the source.
    testing.assertEqual(
        $block.children[0].text,
        strings.replicate(convert.fromCodepoint(0xA0), 14) + ' \frac{a}{b}');
}

func testEachDisplayLineIsCentredOnItsOwn() {
    def lines as list of doctree.Node init centredTex("ab\nabcdef\n", 10);
    testing.assertEqual(len($lines), 3);
    testing.assertEqual($lines[0].text, strings.replicate(convert.fromCodepoint(0xA0), 4) + " ab");
    testing.assertEqual($lines[1].kind, "line_break");
    testing.assertEqual(
        $lines[2].text,
        strings.replicate(convert.fromCodepoint(0xA0), 2) + " abcdef");
    # Wider than the column: no padding, the layout wraps it.
    testing.assertEqual(centredTex("abcdefghijkl", 10)[0].text, "abcdefghijkl");
}
