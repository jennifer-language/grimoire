# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `theme.j`, run by `jennifer test src/theme_test.j`.
 *
 * The registry is small, so most of what is worth asserting is about the whole
 * set rather than any one theme: that every shipped theme is complete, that no
 * two share a name, and that the two orderings the module deliberately keeps
 * apart - presentation order in `all` and alphabetical in `catalog` - stay apart.
 * This is also where a theme file added under `src/themes/` but only half wired
 * up gets caught.
 * @module theme_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use strings;
use lists;

func testFallbackIsGrimoire() {
    testing.assertEqual(fallback(), "grimoire");
}

# The fallback has to be a theme that exists, or a typo in `grimoire.toml` would
# degrade to nothing rather than to a themed site.
func testFallbackResolves() {
    testing.assertTrue(has(fallback()));
}

func testAllShipsTenThemes() {
    testing.assertEqual(len(all()), 10);
    testing.assertEqual(len(names()), 10);
}

# The shell cap in `palette.j` is sized so that both side columns at their widest
# still leave room for the roomiest theme's measure. That sum is written there as
# a number, and this is what keeps the number honest: a theme asking for more
# than 860 would silently start taking width off its own prose on a wide screen.
func testNoThemeAsksForAWiderMeasureThanTheShellAllows() {
    for (def t in all()) {
        testing.assertTrue($t.contentWidth <= 860);
    }
}

func testEveryThemeIsComplete() {
    for (def t in all()) {
        testing.assertNotEqual($t.name, "");
        testing.assertNotEqual($t.label, "");
        testing.assertNotEqual($t.description, "");
        testing.assertNotEqual($t.fontBody, "");
        testing.assertNotEqual($t.fontHeading, "");
        testing.assertNotEqual($t.fontMono, "");
        testing.assertTrue($t.contentWidth > 0);
    }
}

# Two themes sharing a name would make one of them unreachable through `byName`,
# and nothing else in the program would notice.
func testThemeNamesAreUnique() {
    def seen as list of string;
    for (def name in names()) {
        testing.assertFalse(lists.contains($seen, $name));
        $seen[] = $name;
    }
}

func testHasAcceptsEveryShippedName() {
    for (def name in names()) {
        testing.assertTrue(has($name));
    }
}

func testHasRejectsAnUnknownName() {
    testing.assertFalse(has("nosuchtheme"));
    testing.assertFalse(has(""));
    testing.assertFalse(has("Grimoire"));
}

func testByNameFindsEveryShippedTheme() {
    for (def name in names()) {
        testing.assertEqual(byName($name).name, $name);
    }
}

# An unknown name resolves to the first entry of `all`, which is why that list
# keeps presentation order rather than being sorted.
func testByNameFallsBackToTheFirstEntry() {
    testing.assertEqual(byName("nosuchtheme").name, fallback());
    testing.assertEqual(byName("").name, fallback());
}

func testStylesheetNamesTheThemeItRendered() {
    for (def name in names()) {
        def css as string init stylesheet($name);
        testing.assertContains($css, "grimoire theme: ");
        testing.assertContains($css, "(" + $name + ")");
    }
}

# Every theme has to produce a stylesheet a browser can actually use: both colour
# schemes, the metrics the layout reads, and the layout rules themselves.
func testEveryStylesheetCarriesBothPalettesAndTheLayout() {
    for (def name in names()) {
        def css as string init stylesheet($name);
        testing.assertContains($css, "--gr-bg:");
        testing.assertContains($css, "--gr-sidebar-w:");
        testing.assertContains($css, "prefers-color-scheme: dark");
        testing.assertContains($css, ':root[data-theme="dark"]');
        testing.assertContains($css, ':root[data-theme="light"]');
        testing.assertContains($css, ".gr-shell");
        testing.assertContains($css, "@media print");
    }
}

func testStylesheetOfAnUnknownNameIsTheFallback() {
    testing.assertEqual(stylesheet("nosuchtheme"), stylesheet(fallback()));
}

func testCatalogHasALinePerTheme() {
    testing.assertEqual(len(catalog()), len(all()));
}

func testCatalogLinesStartWithTheName() {
    for (def line in catalog()) {
        def name as string init strings.split($line, " ")[0];
        testing.assertTrue(has($name));
        testing.assertContains($line, " - ");
    }
}

# The catalog sorts, because someone reading `grimoire themes` is looking a name
# up; `all` does not, because `byName` falls back to its first entry.
func testCatalogIsAlphabeticalButAllIsNot() {
    def previous as string init "";
    for (def line in catalog()) {
        testing.assertTrue($previous == "" or $previous < $line);
        $previous = $line;
    }
    testing.assertEqual(names()[0], fallback());
}
