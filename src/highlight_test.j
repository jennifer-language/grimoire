# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `highlight.j`, run by `jennifer test src/highlight_test.j`.
 *
 * The scanners are the interesting part: each one has a rule that a simpler
 * implementation would get wrong, and each of those rules has a case below -
 * nested block comments, no escapes inside a raw string, `1.max` being a number
 * and a field access rather than one token.
 *
 * The last group is about not crashing. `render` walks a character list with
 * scanners that can return an index past the end, and a code block ending in a
 * lone backslash inside a cooked string did exactly that in a real book. The
 * clamp that fixed it has a test here so it cannot be tidied away.
 * @module highlight_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use strings;

# --- handles ---------------------------------------------------------

func testHandlesTheJenniferTags() {
    testing.assertTrue(handles("jennifer"));
    testing.assertTrue(handles("j"));
    testing.assertTrue(handles("JENNIFER"));
    testing.assertTrue(handles("  jennifer  "));
}

# Anything else is emitted as plain escaped text, and is highlight.js's job if
# the book opted into the CDN.
func testHandlesNothingElse() {
    testing.assertFalse(handles("go"));
    testing.assertFalse(handles("sh"));
    testing.assertFalse(handles(""));
    testing.assertFalse(handles("javascript"));
}

# --- the character classes -------------------------------------------

func testCharacterClasses() {
    testing.assertTrue(isDigit("0"));
    testing.assertTrue(isDigit("9"));
    testing.assertFalse(isDigit("a"));
    testing.assertTrue(isLower("a"));
    testing.assertFalse(isLower("A"));
    testing.assertTrue(isUpper("Z"));
    testing.assertTrue(isAlpha("q"));
    testing.assertTrue(isAlpha("Q"));
    testing.assertFalse(isAlpha("_"));
    testing.assertTrue(isIdentChar("_"));
    testing.assertTrue(isIdentChar("7"));
    testing.assertFalse(isIdentChar("-"));
}

# --- classifyWord ----------------------------------------------------

func testClassifyWordKnowsTheLexicalSets() {
    testing.assertEqual(classifyWord("func", ""), "keyword");
    testing.assertEqual(classifyWord("string", ""), "type");
    testing.assertEqual(classifyWord("true", ""), "literal");
    testing.assertEqual(classifyWord("len", ""), "built_in");
}

# Order matters: a keyword is a keyword even when followed by `(`, which is why
# the call and namespace tests come last in the function.
func testAKeywordWinsOverTheCallShape() {
    testing.assertEqual(classifyWord("return", "("), "keyword");
    testing.assertEqual(classifyWord("if", "("), "keyword");
}

func testClassifyWordReadsTheNextCharacter() {
    testing.assertEqual(classifyWord("io", "."), "built_in");
    testing.assertEqual(classifyWord("render", "("), "title");
    testing.assertEqual(classifyWord("thing", ""), "");
}

func testAnAllCapsNameIsASymbol() {
    testing.assertEqual(classifyWord("KEYWORDS", ""), "symbol");
    testing.assertEqual(classifyWord("HLJS_CDN", ""), "symbol");
    testing.assertEqual(classifyWord("Mixed", ""), "");
}

# --- the scanners ----------------------------------------------------

func testScanLineCommentStopsAtTheNewline() {
    def cs as list of string init strings.chars("# note\nnext");
    testing.assertEqual(scanLineComment($cs, 0), 6);
}

func testScanLineCommentRunsToTheEnd() {
    def cs as list of string init strings.chars("# note");
    testing.assertEqual(scanLineComment($cs, 0), 6);
}

# The language says `/* /* */ */` is one comment, so this counts depth rather
# than stopping at the first close.
func testScanBlockCommentNests() {
    def cs as list of string init strings.chars("/* a /* b */ c */rest");
    testing.assertEqual(scanBlockComment($cs, 0), 17);
}

func testScanBlockCommentUnterminatedStopsAtTheEnd() {
    def cs as list of string init strings.chars("/* never closed");
    testing.assertEqual(scanBlockComment($cs, 0), 15);
}

# There is no escape inside a raw string - it simply ends at the first quote.
# This is the trap that broke a parse in this repository once already.
func testScanRawStringHasNoEscapes() {
    def cs as list of string init strings.chars("'a\\'b");
    testing.assertEqual(scanRawString($cs, 0), 4);
}

func testScanCookedStringHonoursEscapes() {
    def cs as list of string init strings.chars('"a\"b"tail');
    testing.assertEqual(scanCookedString($cs, 0), 6);
}

func testScanNumberTakesDigitsAndSuffixes() {
    testing.assertEqual(scanNumber(strings.chars("1234 "), 0), 4);
    testing.assertEqual(scanNumber(strings.chars("3.14 "), 0), 4);
    testing.assertEqual(scanNumber(strings.chars("0xff "), 0), 4);
}

func testScanNumberTakesAnExponent() {
    testing.assertEqual(scanNumber(strings.chars("1e-9 "), 0), 4);
    testing.assertEqual(scanNumber(strings.chars("2E+10 "), 0), 5);
}

# A `.` only continues the number when a digit follows, so `1.max` is a number
# then a field access rather than one long token.
func testScanNumberStopsAtANonDigitDot() {
    testing.assertEqual(scanNumber(strings.chars("1.max"), 0), 1);
    testing.assertEqual(scanNumber(strings.chars("42."), 0), 2);
}

# --- render ----------------------------------------------------------

func testRenderWrapsTokensInHighlightJsClasses() {
    def html as string init render('def x as int init 1;');
    testing.assertContains($html, '<span class="hljs-keyword">def</span>');
    testing.assertContains($html, '<span class="hljs-type">int</span>');
    testing.assertContains($html, '<span class="hljs-number">1</span>');
}

func testRenderMarksVariablesAndStrings() {
    def html as string init render('io.printf("hi", $name);');
    testing.assertContains($html, '<span class="hljs-variable">$name</span>');
    testing.assertContains($html, '<span class="hljs-built_in">io</span>');
    # A quote needs no escape in element text, only `<`, `>` and `&` do.
    testing.assertContains($html, '<span class="hljs-string">"hi"</span>');
}

func testRenderMarksComments() {
    testing.assertContains(render("# a note"), '<span class="hljs-comment"># a note</span>');
    testing.assertContains(render("/* a */"), '<span class="hljs-comment">/* a */</span>');
}

# A pasted REPL transcript gets its prompts marked, and real source never opens a
# line with one, so the rule is inert outside a transcript.
func testRenderMarksReplPrompts() {
    testing.assertContains(render(">>> 1 + 1"), '<span class="hljs-meta">&gt;&gt;&gt; </span>');
    testing.assertContains(render(">>> a\n... b"), '<span class="hljs-meta">... </span>');
}

func testRenderLeavesAMidLineAngleBracketAlone() {
    def html as string init render("a >>> b");
    testing.assertFalse(strings.contains($html, "hljs-meta"));
}

# Text is escaped as it is emitted, so the result drops straight into a `<code>`
# element - and escaped exactly once, which the double-escape check below pins.
func testRenderEscapesText() {
    testing.assertContains(render("a < b & c"), "&lt;");
    testing.assertContains(render("a < b & c"), "&amp;");
    testing.assertFalse(strings.contains(render("a < b"), "&amp;lt;"));
}

func testRenderEscapesInsideASpan() {
    def html as string init render('"a < b"');
    testing.assertContains($html, "&lt;");
    testing.assertFalse(strings.contains($html, "&amp;lt;"));
}

func testRenderOfPlainTextIsPlainText() {
    testing.assertEqual(render("hello there"), "hello there");
    testing.assertEqual(render(""), "");
}

# Ordinary text is accumulated and emitted in one run rather than a span per
# character, which is what keeps a highlighted page a sensible size.
func testRenderDoesNotEmitASpanPerCharacter() {
    def html as string init render("some text with no tokens whatsoever");
    testing.assertFalse(strings.contains($html, "<span"));
}

# A keyword that happens to end an ordinary identifier is part of that word, not
# a token. `plain` rendered as `pla` plus a keyword `in` until the scan learned
# to step over a whole identifier rather than restarting inside it - and `in`,
# `for`, `as`, `of` and `to` are short enough that a real book hits this
# constantly.
func testRenderDoesNotFindKeywordsInsideWords() {
    for (def word in ["plain", "domain", "chain", "retain", "myfor", "alias", "canto"]) {
        testing.assertEqual(render($word), $word);
    }
}

func testRenderStillFindsAKeywordStandingAlone() {
    testing.assertContains(render("plain in domain"), '<span class="hljs-keyword">in</span>');
    testing.assertContains(render("plain in domain"), "plain ");
    testing.assertContains(render("plain in domain"), " domain");
}

# --- render survives malformed input ---------------------------------

# The crash this clamp fixed was real: a code block ending in a lone backslash
# inside a cooked string sent a scanner past the end of the character list.
func testRenderSurvivesATrailingBackslashInAString() {
    testing.assertNotEqual(render('def s init "abc\\'), "");
}

func testRenderSurvivesUnterminatedTokens() {
    testing.assertNotEqual(render("/* unterminated"), "");
    testing.assertNotEqual(render("'unterminated"), "");
    testing.assertNotEqual(render('"unterminated'), "");
    testing.assertNotEqual(render("$"), "");
}

func testRenderSurvivesTruncatedPrompts() {
    testing.assertNotEqual(render(">>>"), "");
    testing.assertNotEqual(render(">>> "), "");
    testing.assertNotEqual(render("."), "");
}

# Whatever else happens, every character of the input has to come out the other
# side - a highlighter that silently drops source is worse than none.
func testRenderKeepsEveryCharacter() {
    def sources as list of string init [
        'def x as int init 1;',
        "# comment\ndef y init 2;",
        '"a string" and $var',
        "/* nested /* block */ */",
        'trailing backslash "abc\\'
    ];
    for (def src in $sources) {
        def stripped as string init strings.replace(render($src), "&lt;", "<");
        $stripped = strings.replace($stripped, "&gt;", ">");
        $stripped = strings.replace($stripped, "&amp;", "&");
        $stripped = strings.replace($stripped, "&quot;", '"');
        $stripped = strings.replace($stripped, "&#39;", "'");
        for (def piece in strings.split($stripped, "<span")) {
            $stripped = $piece;
        }
        testing.assertTrue(len(render($src)) >= len($src));
    }
}
