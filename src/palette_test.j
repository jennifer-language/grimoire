# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `palette.j`, run by `jennifer test src/palette_test.j`.
 *
 * Colour parsing first, because `parseHex` is deliberately forgiving - it is used
 * to tint a PDF heading bar, where a slightly wrong bar beats a failed build -
 * and forgiving code needs its fallbacks pinned or they become accidents.
 *
 * Then the stylesheet, which is the module's real output and is checked
 * structurally: both modes define the same property names, the layout rules
 * survive, and the column-placement selectors that `layout.j` writes data
 * attributes for are actually present. Those two files can only be wrong
 * together, and nothing but a test looks at both.
 * @module palette_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use strings;
use lists;

func swatch() {
    return palette(
        "#ffffff",
        "#f5f5f5",
        "#eeeeee",
        "#dddddd",
        "#111111",
        "#666666",
        "#000000",
        "#0066cc",
        "#0055aa",
        "#ffffff",
        "#222222",
        "#f0f0f0",
        "rgba(0, 102, 204, 0.2)",
        "rgba(0, 0, 0, 0.1)");
}

func sampleTheme() {
    return Theme{
        name: "testing",
        label: "Testing",
        description: "a theme built by a test",
        light: swatch(),
        dark: swatch(),
        fontBody: sans(),
        fontHeading: serif(),
        fontMono: mono(),
        radius: 8,
        contentWidth: 760
    };
}

# --- the font stacks -------------------------------------------------

# Each ends in a generic family, so a host with none of the named faces still
# renders the intended shape.
func testEveryStackEndsInAGenericFamily() {
    testing.assertTrue(strings.endsWith(sans(), "sans-serif"));
    testing.assertTrue(strings.endsWith(serif(), "serif"));
    testing.assertTrue(strings.endsWith(mono(), "monospace"));
}

func testTheStacksAreDistinct() {
    testing.assertNotEqual(sans(), serif());
    testing.assertNotEqual(serif(), mono());
}

# --- palette ---------------------------------------------------------

# A positional builder keeps a theme file readable as a colour table, which only
# works if the positions land where the struct says they do. Fourteen arguments
# in a row is exactly the shape that gets transposed by accident.
func testPaletteAssignsItsArgumentsInOrder() {
    def p as Palette init swatch();
    testing.assertEqual($p.bg, "#ffffff");
    testing.assertEqual($p.surface, "#f5f5f5");
    testing.assertEqual($p.surfaceAlt, "#eeeeee");
    testing.assertEqual($p.border, "#dddddd");
    testing.assertEqual($p.text, "#111111");
    testing.assertEqual($p.muted, "#666666");
    testing.assertEqual($p.heading, "#000000");
    testing.assertEqual($p.accent, "#0066cc");
    testing.assertEqual($p.accentHover, "#0055aa");
    testing.assertEqual($p.onAccent, "#ffffff");
    testing.assertEqual($p.codeText, "#222222");
    testing.assertEqual($p.codeBg, "#f0f0f0");
    testing.assertContains($p.selection, "rgba(0, 102, 204");
    testing.assertContains($p.shadow, "rgba(0, 0, 0");
}

# --- hexDigit and hexPair --------------------------------------------

func testHexDigitReadsBothCases() {
    testing.assertEqual(hexDigit("0"), 0);
    testing.assertEqual(hexDigit("9"), 9);
    testing.assertEqual(hexDigit("a"), 10);
    testing.assertEqual(hexDigit("F"), 15);
}

func testHexDigitRejectsAnythingElse() {
    testing.assertEqual(hexDigit("g"), -1);
    testing.assertEqual(hexDigit("#"), -1);
    testing.assertEqual(hexDigit(" "), -1);
}

func testHexPairCombinesTwoDigits() {
    testing.assertEqual(hexPair("#ff8000", 1), 255);
    testing.assertEqual(hexPair("#ff8000", 3), 128);
    testing.assertEqual(hexPair("#ff8000", 5), 0);
}

func testHexPairRejectsANonDigit() {
    testing.assertEqual(hexPair("#zz0000", 1), -1);
}

# --- parseHex --------------------------------------------------------

func testParseHexReadsAColour() {
    def c as Rgb init parseHex("#ff8000");
    testing.assertEqual($c.r, 255);
    testing.assertEqual($c.g, 128);
    testing.assertEqual($c.b, 0);
}

func testParseHexIsCaseInsensitive() {
    testing.assertEqual(parseHex("#AABBCC").r, parseHex("#aabbcc").r);
    testing.assertEqual(parseHex("#AABBCC").g, 187);
}

func testParseHexHandlesTheExtremes() {
    testing.assertEqual(parseHex("#000000").r, 0);
    testing.assertEqual(parseHex("#ffffff").b, 255);
}

# Anything that is not `#rrggbb` - the `rgba(...)` a selection or shadow uses -
# has no single opaque colour to report, so it comes back mid grey rather than as
# an error. This is used to tint a heading bar; a slightly wrong bar beats a
# failed build.
func testParseHexFallsBackToMidGrey() {
    testing.assertEqual(parseHex("rgba(0, 0, 0, 0.1)").r, 128);
    testing.assertEqual(parseHex("#fff").g, 128);
    testing.assertEqual(parseHex("").b, 128);
    testing.assertEqual(parseHex("#gggggg").r, 128);
    testing.assertEqual(parseHex("ff8000").r, 128);
}

# --- tint ------------------------------------------------------------

func testTintKeepsAllOfTheColourAtOneHundred() {
    def c as Rgb init tint(Rgb{r: 10, g: 20, b: 30}, 100);
    testing.assertEqual($c.r, 10);
    testing.assertEqual($c.g, 20);
    testing.assertEqual($c.b, 30);
}

func testTintIsWhiteAtZero() {
    def c as Rgb init tint(Rgb{r: 10, g: 20, b: 30}, 0);
    testing.assertEqual($c.r, 255);
    testing.assertEqual($c.g, 255);
    testing.assertEqual($c.b, 255);
}

func testTintMixesTowardWhite() {
    def c as Rgb init tint(Rgb{r: 0, g: 0, b: 0}, 50);
    testing.assertEqual($c.r, 127);
}

func testTintClampsItsPercentage() {
    testing.assertEqual(tint(Rgb{r: 10, g: 10, b: 10}, 500).r, 10);
    testing.assertEqual(tint(Rgb{r: 10, g: 10, b: 10}, -50).r, 255);
}

# A tint is only useful if it lands somewhere a browser can draw.
func testTintStaysInRange() {
    for (def pct in [0, 5, 25, 50, 75, 95, 100]) {
        def c as Rgb init tint(Rgb{r: 200, g: 100, b: 3}, $pct);
        testing.assertTrue($c.r >= 0 and $c.r <= 255);
        testing.assertTrue($c.g >= 0 and $c.g <= 255);
        testing.assertTrue($c.b >= 0 and $c.b <= 255);
    }
}

# --- vars and syntaxVars ---------------------------------------------

func testVarsRendersOnePropertyPerLine() {
    def block as string init vars(swatch(), "    ");
    testing.assertContains($block, "    --gr-bg: #ffffff;");
    testing.assertContains($block, "    --gr-accent: #0066cc;");
    testing.assertEqual(len(strings.split($block, "\n")), 14);
}

func testSyntaxVarsRendersOnePropertyPerLine() {
    def block as string init syntaxVars(SYNTAX_LIGHT, "  ");
    testing.assertContains($block, "  --gr-syn-keyword: ");
    testing.assertEqual(len(strings.split($block, "\n")), len(SYNTAX_LIGHT));
}

# Nothing in the layout sheet ever has to know which mode is active, which only
# holds while both schemes define exactly the same property names.
func testBothSyntaxSchemesDefineTheSameProperties() {
    testing.assertEqual(len(SYNTAX_LIGHT), len(SYNTAX_DARK));
    def darkNames as list of string;
    for (def row in SYNTAX_DARK) {
        $darkNames[] = strings.split($row, ":")[0];
    }
    for (def row in SYNTAX_LIGHT) {
        testing.assertTrue(lists.contains($darkNames, strings.split($row, ":")[0]));
    }
}

# --- stylesheet ------------------------------------------------------

func testStylesheetNamesItsTheme() {
    testing.assertContains(stylesheet(sampleTheme()), "grimoire theme: Testing (testing)");
}

func testStylesheetCarriesTheThemeMetrics() {
    def css as string init stylesheet(sampleTheme());
    testing.assertContains($css, "--gr-radius: 8px;");
    testing.assertContains($css, "--gr-content-w: 760px;");
    testing.assertContains($css, "--gr-sidebar-w:");
    testing.assertContains($css, "--gr-toc-w:");
    testing.assertContains($css, "--gr-topbar-h:");
}

# --- the two side columns grow with the viewport ---------------------

# Both hold titles, and a title is as long as it is: at a fixed width the only
# thing that gives is the line count, which turns a list meant to be scanned into
# a paragraph. They scale with the viewport instead.
func testTheSideColumnsScaleWithTheViewport() {
    def css as string init stylesheet(sampleTheme());
    testing.assertContains($css, "--gr-sidebar-w: clamp(302px, 19vw, 400px);");
    testing.assertContains($css, "--gr-toc-w: clamp(232px, 15vw, 340px);");
}

# The floors are the widths these columns have always had, so nothing renders
# differently below the point where the viewport share overtakes them - about
# 1590px for the sidebar. A narrow screen is not what this was about.
func testTheFloorsAreTheOldFixedWidths() {
    testing.assertEqual(SIDEBAR_MIN, 302);
    testing.assertEqual(TOC_MIN, 232);
    testing.assertTrue(SIDEBAR_MAX > SIDEBAR_MIN);
    testing.assertTrue(TOC_MAX > TOC_MIN);
}

# The invariant that makes the growth free rather than borrowed: at the cap,
# both columns at their widest still leave room for the roomiest theme's measure
# and the padding around it. Without this, widening a column would only narrow
# the prose.
# 860 is the roomiest measure any shipped theme asks for, and 68 is the padding
# the text column carries either side of it. `theme_test.j` holds the other half
# of this: it fails if a theme is ever added that wants more than 860, which is
# the moment this number would go quietly wrong.
func testTheShellCapCoversBothColumnsAndTheWidestMeasure() {
    testing.assertTrue(SHELL_MAX >= SIDEBAR_MAX + TOC_MAX + 860 + 68);
}

# A column that keeps growing stops being navigation and becomes a second column
# of text, so both are capped well short of the measure beside them.
func testNeitherColumnGrowsIntoASecondTextColumn() {
    testing.assertTrue(SIDEBAR_MAX <= 460);
    testing.assertTrue(TOC_MAX <= 400);
}

# The dark palette appears three times over: once under the media query for a
# reader who chose nothing, and once under each explicit attribute so the in-page
# selector can override the system preference in either direction.
func testStylesheetCoversAllThreeWaysAModeCanBeChosen() {
    def css as string init stylesheet(sampleTheme());
    testing.assertContains($css, "@media (prefers-color-scheme: dark)");
    testing.assertContains($css, ':root:not([data-theme="light"])');
    testing.assertContains($css, ':root[data-theme="dark"]');
    testing.assertContains($css, ':root[data-theme="light"]');
}

func testStylesheetEndsWithTheLayoutRules() {
    def css as string init stylesheet(sampleTheme());
    testing.assertContains($css, ".gr-shell");
    testing.assertContains($css, ".gr-topbar");
    testing.assertContains($css, ".gr-content");
    testing.assertContains($css, "@media print");
}

# The other half of the column-placement feature: `layout.j` writes `data-nav`
# and `data-toc` onto the shell, and these selectors are the only thing that
# reads them. The two files can only be right together.
func testStylesheetPlacesBothNavigationColumns() {
    def css as string init stylesheet(sampleTheme());
    testing.assertContains($css, '.gr-shell[data-nav="left"] .gr-sidebar');
    testing.assertContains($css, '.gr-shell[data-nav="right"] .gr-sidebar');
    testing.assertContains($css, '.gr-shell[data-toc="left"] .gr-toc');
    testing.assertContains($css, '.gr-shell[data-toc="right"] .gr-toc');
    testing.assertContains($css, '.gr-shell[data-nav="off"] .gr-toc');
}

# A grid would need a column template per combination; the row is flex so that a
# column simply missing costs nothing. Undoing that quietly breaks six of the
# nine arrangements, and only in a browser.
func testTheShellIsAFlexRow() {
    def css as string init stylesheet(sampleTheme());
    testing.assertContains($css, "display: flex");
    # A raw string: a brace in a cooked one opens an interpolation slot.
    testing.assertContains($css, '.gr-main { flex: 1 1 auto; min-width: 0;');
}

func testStylesheetIsDeterministic() {
    testing.assertEqual(stylesheet(sampleTheme()), stylesheet(sampleTheme()));
}
