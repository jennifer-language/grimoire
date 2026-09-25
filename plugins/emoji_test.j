# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `emoji.j`, run by `jennifer test plugins/emoji_test.j`.
 *
 * The interesting half is everything that must **not** be replaced: a colon in
 * prose, a time, a ratio, a namespaced word, a fence. A plugin that turns
 * `10:30` into a picture is worse than no plugin.
 *
 * The expected characters are written as codepoints here too, for the reason
 * the table is: a test that compares two look-alike glyphs tests nothing.
 * @module emoji_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;

def const NO_SETTINGS as string init '{}';

func requestFor(settings as string, content as string) {
    return '{"api":1,"kind":"preprocessor","book":{"title":"A Book","description":"d",' +
        '"authors":["Ada"],"language":"en","src":"docs","out":"site"},' +
        '"plugin":{"name":"emoji","settings":' + $settings + '},' +
        '"entries":[],"chapters":[{"src":"index.md","content":' +
        json.encode($content) + '}]}';
}

func codes() {
    return table(json.decode(requestFor(NO_SETTINGS, "")));
}

func testACodepointListBecomesOneCharacter() {
    testing.assertEqual(characterOf([0x1F680]), convert.fromCodepoint(0x1F680));
    # A sequence stays a sequence: the variation selector is what asks for the
    # emoji form rather than the dingbat.
    testing.assertEqual(len(characterOf([0x26A0, 0xFE0F])), 2);
}

func testTheTableIsBuiltFromTheCodepoints() {
    def known as map of string to string init codes();
    testing.assertEqual($known["rocket"], convert.fromCodepoint(0x1F680));
    testing.assertEqual($known["warning"], characterOf([0x26A0, 0xFE0F]));
    testing.assertTrue(maps.has($known, "white_check_mark"));
}

# A project redefining `:warning:` to its house glyph should not have to wait for
# anybody, so a book's own entry wins.
func testABooksOwnEntriesAreAddedAndWin() {
    def known as map of string to string init table(json.decode(requestFor(
        '{"extra":{"grimoire":"G","warning":"!"}}',
        "")));
    testing.assertEqual($known["grimoire"], "G");
    testing.assertEqual($known["warning"], "!");
}

func anExtraThatIsNotText() {
    table(json.decode(requestFor('{"extra":{"broken":[1,2]}}', "")));
}

func testAnExtraThatIsNotTextIsRefused() {
    testing.assertThrows("anExtraThatIsNotText", "plugin");
}

func testAShortcodeBecomesItsCharacter() {
    def out as string init expand("Ship it :rocket: now\n", codes());
    testing.assertEqual($out, "Ship it " + convert.fromCodepoint(0x1F680) + " now\n");
}

func testSeveralOnOneLineAreAllReplaced() {
    def out as string init expand(":x: then :white_check_mark:\n", codes());
    testing.assertContains($out, convert.fromCodepoint(0x274C));
    testing.assertContains($out, convert.fromCodepoint(0x2705));
    testing.assertFalse(strings.contains($out, ":x:"));
}

# A colon is punctuation long before it is markup, and a book is full of them.
func testProseKeepsItsColons() {
    for (def line in [
        "Note: a thing",
        "at 10:30 sharp",
        "a 3:2 ratio",
        "std::vector",
        "https://example.com/x",
        "empty :: colons",
        "a :not a code: here"
    ]) {
        testing.assertEqual(expand($line, codes()), $line);
    }
}

# A name the table does not know is left alone rather than guessed at.
func testAnUnknownNameIsLeftAlone() {
    testing.assertEqual(expand("a :nosuchcode: here\n", codes()), "a :nosuchcode: here\n");
}

# A shortcode inside a word is part of the word.
func testAShortcodeNeedsABoundary() {
    testing.assertEqual(expand("x:rocket:y\n", codes()), "x:rocket:y\n");
    testing.assertEqual(
        expand("(:rocket:)\n", codes()),
        "(" + convert.fromCodepoint(0x1F680) + ")\n");
}

# A page about shortcodes still shows them.
func testFencedCodeIsLeftAlone() {
    def content as string init "```markdown\nShip it :rocket:\n```\n";
    testing.assertEqual(expand($content, codes()), $content);
}

func testTheReplyCarriesOnlyWhatChanged() {
    def out as string init replyFor(json.decode(requestFor(NO_SETTINGS, "Ship it :rocket:\n")));
    testing.assertEqual(json.length(json.decode($out), "/chapters"), 1);
    def quiet as string init replyFor(json.decode(requestFor(NO_SETTINGS, "Nothing here.\n")));
    testing.assertEqual(json.length(json.decode($quiet), "/chapters"), 0);
}

func testRunExpandsTheBook() {
    testing.assertEqual(run(requestFor(NO_SETTINGS, "Ship it :rocket:\n")), 0);
}

func testRunRefusesARequestItCannotAnswer() {
    def req as string init requestFor(NO_SETTINGS, "plain\n");
    testing.assertEqual(run(strings.replace($req, '"api":1', '"api":2')), 1);
    testing.assertEqual(run(strings.replace($req, '"preprocessor"', '"renderer"')), 1);
    testing.assertEqual(run(""), 1);
}
