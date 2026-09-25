# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `macros.j`, run by `jennifer test plugins/macros_test.j`.
 *
 * Three things carry the weight: what a name resolves to, where a macro is
 * **not** expanded (a fence, an escaped one), and that a name with nothing
 * behind it stops the build rather than reaching a reader.
 * @module macros_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;

# Settings tables, as constants: `{}` in a cooked string is an interpolation, and
# `fmt` rejoins a long raw string that is split by hand.
def const NO_SETTINGS as string init '{}';
def const MIXED_VARS as string init '{"vars":{"version":"1.4.0","build":42,' +
    '"beta":true,"ratio":1.5}}';

func requestFor(settings as string, content as string) {
    return '{"api":1,"kind":"preprocessor","book":{"title":"A Book",' +
        '"description":"About things","authors":["Ada","Grace"],"language":"en",' +
        '"src":"docs","out":"site"},' +
        '"plugin":{"name":"macros","settings":' + $settings + '},' +
        '"entries":[],"chapters":[{"src":"index.md","content":' +
        json.encode($content) + '}]}';
}

func valuesWith(settings as string) {
    return valuesOf(json.decode(requestFor($settings, "")));
}

func testTheBookIsAlwaysAvailable() {
    def values as map of string to string init valuesWith(NO_SETTINGS);
    testing.assertEqual($values["book.title"], "A Book");
    testing.assertEqual($values["book.description"], "About things");
    testing.assertEqual($values["book.language"], "en");
    testing.assertEqual($values["book.authors"], "Ada, Grace");
}

# A number in a manifest is a number, and a page wants it as text.
func testValuesComeThroughAsText() {
    def values as map of string to string init valuesWith(MIXED_VARS);
    testing.assertEqual($values["version"], "1.4.0");
    testing.assertEqual($values["build"], "42");
    testing.assertEqual($values["beta"], "true");
    testing.assertContains($values["ratio"], "1.5");
}

func aValueWithAShape() {
    valuesWith('{"vars":{"versions":["1.0","2.0"]}}');
}

func testAValueThatIsNotAWordOrANumberIsRefused() {
    testing.assertThrows("aValueWithAShape", "plugin");
}

# A build that can print any variable it likes is one careless page away from
# publishing a token, so the book says which ones it is willing to read.
func testOnlyNamedEnvironmentVariablesAreRead() {
    os.setEnv("GRIMOIRE_TEST_MACRO", "from-the-pipeline");
    def values as map of string to string init valuesWith('{"env":["GRIMOIRE_TEST_MACRO"]}');
    testing.assertEqual($values["env.GRIMOIRE_TEST_MACRO"], "from-the-pipeline");
    testing.assertFalse(maps.has($values, "env.PATH"));
}

func anEnvironmentVariableThatIsNotSet() {
    valuesWith('{"env":["GRIMOIRE_TEST_UNSET_MACRO"]}');
}

func testAnEnvironmentVariableThatIsNotSetIsRefused() {
    testing.assertThrows("anEnvironmentVariableThatIsNotSet", "plugin");
}

func testAMacroIsReplacedWhereverItStands() {
    def values as map of string to string init {"version": "1.4.0"};
    testing.assertEqual(
        expand('Install {{ version }} now, or {{version}}.' + "\n", $values, true, "index.md"),
        "Install 1.4.0 now, or 1.4.0.\n");
}

# A page showing what a macro looks like is a page about macros; expanding the
# example would make it a lie.
func testFencedCodeIsLeftAlone() {
    def values as map of string to string init {"version": "1.4.0"};
    def content as string init 'before {{ version }}' + "\n\n```toml\n" +
        'version = "{{ version }}"' + "\n```\n\n" + 'after {{ version }}' + "\n";
    def out as string init expand($content, $values, true, "index.md");
    testing.assertContains($out, "before 1.4.0");
    testing.assertContains($out, 'version = "{{ version }}"');
    testing.assertContains($out, "after 1.4.0");
}

func testABackslashPrintsTheMacroInstead() {
    def values as map of string to string init {"version": "1.4.0"};
    testing.assertEqual(
        expand('write \{{ version }} to show it' + "\n", $values, true, "index.md"),
        'write {{ version }} to show it' + "\n");
}

# A placeholder that reaches a reader is worse than a build that stopped.
func anUnknownName() {
    def values as map of string to string init {"version": "1.4.0"};
    expand('the {{ verison }} typo' + "\n", $values, true, "guide/install.md");
}

func testAnUnknownNameStopsTheBuild() {
    testing.assertThrows("anUnknownName", "plugin");
}

# `strict = false` is for a book that writes braces for some other reason.
func testAnUnknownNameSurvivesWhenStrictIsOff() {
    def values as map of string to string init {"version": "1.4.0"};
    testing.assertEqual(
        expand('a {{ mystery }} here' + "\n", $values, false, "index.md"),
        'a {{ mystery }} here' + "\n");
}

func testTheReplyCarriesOnlyWhatChanged() {
    def out as string init replyFor(json.decode(requestFor(
        '{"vars":{"version":"1.4.0"}}',
        'Version {{ version }}, and {{ book.title }}.' + "\n")));
    def reply as json.Value init json.decode($out);
    testing.assertEqual(json.length($reply, "/chapters"), 1);
    testing.assertEqual(
        json.asString($reply, "/chapters/0/content"),
        "Version 1.4.0, and A Book.\n");
}

func testAChapterWithNoMacroIsNotInTheReply() {
    def out as string init replyFor(json.decode(requestFor(NO_SETTINGS, "Nothing to expand.\n")));
    testing.assertEqual(json.length(json.decode($out), "/chapters"), 0);
}

func testRunExpandsTheBook() {
    def content as string init '{{ version }}' + "\n";
    testing.assertEqual(run(requestFor('{"vars":{"version":"1.4.0"}}', $content)), 0);
}

func testRunRefusesARequestItCannotAnswer() {
    def req as string init requestFor(NO_SETTINGS, "plain\n");
    testing.assertEqual(run(strings.replace($req, '"api":1', '"api":2')), 1);
    testing.assertEqual(run(strings.replace($req, '"preprocessor"', '"renderer"')), 1);
    testing.assertEqual(run(""), 1);
}
