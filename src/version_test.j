# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `version.j`, run by `jennifer test src/version_test.j`.
 *
 * Whether the number is the *right* one is not a question a unit test can
 * answer - that is CI comparing this file against `deck.toml` and the tag. What
 * is checked here is the shape the rest of that comparison assumes: a bare
 * dotted SemVer number, no leading "v", nothing else on the line.
 * @module version_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use strings;
use convert;

# The registry parses `deck.toml` as SemVer and a release tag is the same
# string, so a number that is not three dotted fields fails a publish rather
# than a test - somewhere much further from the edit that caused it.
func testTheNumberIsSemver() {
    def parts as list of string init strings.split(number(), ".");
    testing.assertEqual(len($parts), 3);
    for (def part in $parts) {
        testing.assertNotEqual($part, "");
        for (def ch in strings.chars($part)) {
            testing.assertTrue(convert.toCodepoint($ch) >= 48);
            testing.assertTrue(convert.toCodepoint($ch) <= 57);
        }
    }
}

# CI strips a leading "v" from the tag before comparing, and compares nothing
# else. A "v" written here would be compared against a tag that no longer has
# one and would look like drift.
func testTheNumberCarriesNoPrefix() {
    testing.assertFalse(strings.startsWith(number(), "v"));
    testing.assertEqual(strings.trim(number()), number());
}

# `--version` prints this, and a bug report quotes it. The command name belongs
# in exactly one place, which is why `line()` exists rather than every caller
# concatenating its own.
func testTheLineNamesTheCommand() {
    testing.assertEqual(line(), "grimoire " + number());
    testing.assertTrue(strings.startsWith(line(), "grimoire "));
}
