# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `themes/ivy.j`, run by
 * `jennifer test src/themes/ivy_test.j`.
 *
 * A theme file is twenty-eight colours handed to a positional builder, which is
 * the shape a copy-paste gets quietly wrong: a name still pointing at the theme
 * it was copied from, one palette pasted into both modes, or the light and dark
 * pair the wrong way round. None of those stops a build, and the first one makes
 * a theme unreachable through `byName` without anything saying so.
 *
 * `theme_test.j` checks the ten together - that they are complete, uniquely
 * named, and render. These are the checks that need to know which theme they are
 * looking at.
 * @module ivy_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use strings;

# The mean of a colour's three channels, 0-255. `parseHex` answers mid grey for
# anything that is not `#rrggbb`, so this is only asked about the opaque fields.
func brightness(hex as string) {
    def c as palette.Rgb init palette.parseHex($hex);
    return ($c.r + $c.g + $c.b) // 3;
}

# The fourteen colours of one mode, in the order `palette.palette` takes them.
func colours(p as palette.Palette) {
    return [
        $p.bg,
        $p.surface,
        $p.surfaceAlt,
        $p.border,
        $p.text,
        $p.muted,
        $p.heading,
        $p.accent,
        $p.accentHover,
        $p.onAccent,
        $p.codeText,
        $p.codeBg,
        $p.selection,
        $p.shadow
    ];
}

# The name is what `grimoire.toml` asks for and what `byName` matches on. A file
# copied from another theme and left with the old name shadows nothing and is
# reachable by nothing.
func testTheThemeNamesItself() {
    testing.assertEqual(theme().name, "ivy");
    testing.assertNotEqual(theme().label, "");
    testing.assertNotEqual(theme().description, "");
}

func testTheTwoModesAreNotTheSamePalette() {
    testing.assertNotEqual(theme().light.bg, theme().dark.bg);
    testing.assertNotEqual(theme().light.text, theme().dark.text);
}

# Which way round the two palettes go is invisible in the source - both are
# fourteen hex strings - and obvious the moment a page renders. Measuring the
# background is what tells them apart.
func testLightIsLightAndDarkIsDark() {
    testing.assertTrue(brightness(theme().light.bg) > 180);
    testing.assertTrue(brightness(theme().dark.bg) < 120);
}

# Text has to be readable against the surface it sits on, in both modes.
func testTextContrastsWithItsBackground() {
    testing.assertTrue(brightness(theme().light.text) < 120);
    testing.assertTrue(brightness(theme().dark.text) > 180);
}

# A malformed colour reaches the stylesheet as written and the browser drops the
# declaration, so the page renders with that one property missing.
func testEveryColourHasAUsableShape() {
    for (def p in [theme().light, theme().dark]) {
        for (def c in colours($p)) {
            testing.assertTrue((len($c) == 7 and strings.startsWith($c, "#")) or
                strings.startsWith($c, "rgba("));
        }
    }
}

# The shell cap in `palette.j` is sized against the roomiest measure any theme
# asks for; `theme_test.j` holds the ceiling, this holds the floor.
func testTheMetricsAreSane() {
    testing.assertTrue(theme().radius >= 0);
    testing.assertTrue(theme().contentWidth >= 600);
    testing.assertTrue(theme().contentWidth <= 860);
    testing.assertNotEqual(theme().fontBody, "");
    testing.assertNotEqual(theme().fontHeading, "");
    testing.assertNotEqual(theme().fontMono, "");
}
