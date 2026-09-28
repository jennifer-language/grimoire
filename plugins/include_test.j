# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `include.j`, run by `jennifer test plugins/include_test.j`.
 *
 * The plugin reads files a chapter names, so the tests that matter are the ones
 * about **which** files: a path that climbs out of the book is refused, a
 * missing one stops the build, and a range past the end of a file is an error
 * rather than an empty page. The rest is the line arithmetic, which is 1-based
 * the way an editor is and inclusive at both ends.
 * @module include_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use os;

# A book with a file worth quoting, and a file outside it worth not quoting.
func bookTree() {
    def root as string init fs.makeTempDir(os.tempDir(), "include-");
    fs.mkdirAll(path.join($root, "book/examples"));
    fs.writeString(path.join($root, "book/examples/hello.j"), "one\ntwo\nthree\nfour\nfive\n");
    fs.writeString(path.join($root, "secret.txt"), "not part of the book\n");
    return $root;
}

func requestFor(root as string, content as string) {
    return '{"api":1,"kind":"preprocessor","book":{"title":"A Book","description":"d",' +
        '"authors":["Ada"],"language":"en","src":' + json.encode(path.join($root, "book")) +
        ',"out":"site"},' +
        '"plugin":{"name":"include","settings":{}},' +
        '"entries":[],"chapters":[{"src":"index.md","content":' +
        json.encode($content) + '}]}';
}

func testTheWholeFileIsTheDefault() {
    testing.assertEqual(slice("f", "one\ntwo\nthree\n", 0, 0), "one\ntwo\nthree");
}

# 1-based and inclusive at both ends, the way an editor counts and a reader
# reading `:3:12` expects.
func testARangeCountsFromOneAndIncludesBothEnds() {
    def text as string init "one\ntwo\nthree\nfour\nfive\n";
    testing.assertEqual(slice("f", $text, 2, 4), "two\nthree\nfour");
    testing.assertEqual(slice("f", $text, 3, 3), "three");
    testing.assertEqual(slice("f", $text, 1, 1), "one");
}

func testAnOpenRangeRunsToTheEnd() {
    def text as string init "one\ntwo\nthree\n";
    testing.assertEqual(slice("f", $text, 2, 0), "two\nthree");
    # A last line past the end is the end: that is what `:2:` means when the file
    # grows shorter.
    testing.assertEqual(slice("f", $text, 2, 99), "two\nthree");
}

# The trailing newline every text file ends with splits into an empty line that
# is not a line of the file.
func testTheTrailingNewlineIsNotALine() {
    testing.assertEqual(slice("f", "one\n", 0, 0), "one");
    testing.assertEqual(slice("f", "one\n", 1, 1), "one");
}

func aFirstLinePastTheEnd() {
    slice("examples/hello.j", "one\ntwo\n", 9, 0);
}

# The book meant to quote something, so an empty page is the wrong answer.
func testAFirstLinePastTheEndIsRefused() {
    testing.assertThrows("aFirstLinePastTheEnd", "plugin");
}

func testAPathInsideTheBookResolves() {
    def root as string init bookTree();
    def book as string init path.join($root, "book");
    testing.assertEqual(resolve($book, "examples/hello.j"), path.join($book, "examples/hello.j"));
    fs.removeAll($root);
}

# A book is a directory. A preprocessor that reads `/etc/passwd` into a page
# because a chapter says so is a hole rather than a feature.
func aPathThatClimbsOut() {
    def root as string init bookTree();
    try {
        resolve(path.join($root, "book"), "../secret.txt");
    } catch (e) {
        fs.removeAll($root);
        throw $e;
    }
}

func testAPathThatClimbsOutOfTheBookIsRefused() {
    testing.assertThrows("aPathThatClimbsOut", "plugin");
}

func aPathToNothing() {
    def root as string init bookTree();
    try {
        resolve(path.join($root, "book"), "examples/missing.j");
    } catch (e) {
        fs.removeAll($root);
        throw $e;
    }
}

func testAPathToNothingIsRefused() {
    testing.assertThrows("aPathToNothing", "plugin");
}

func testADirectiveIsReplacedByTheFile() {
    def root as string init bookTree();
    def out as string init expand(
        path.join($root, "book"),
        "Before\n\n" + '{{#include examples/hello.j}}' + "\n\nAfter\n");
    testing.assertContains($out, "Before\n\none\ntwo\nthree\nfour\nfive\n\nAfter");
    fs.removeAll($root);
}

func testADirectiveMayNameARange() {
    def root as string init bookTree();
    def book as string init path.join($root, "book");
    testing.assertContains(expand($book, '{{#include examples/hello.j:2:3}}' + "\n"), "two\nthree");
    testing.assertContains(expand($book, '{{#include examples/hello.j:4}}' + "\n"), "four\nfive");
    fs.removeAll($root);
}

# The directive has to stand alone on its line: one inside a sentence is prose
# about the syntax, which the manual documenting this plugin is full of.
func testADirectiveInASentenceIsProse() {
    def root as string init bookTree();
    def content as string init 'Write {{#include examples/hello.j}} to pull a file in.' + "\n";
    testing.assertEqual(expand(path.join($root, "book"), $content), $content);
    fs.removeAll($root);
}

# A backslash prints the directive instead of following it, which is how a book
# shows the syntax. The convention is mdBook's.
func testABackslashPrintsTheDirective() {
    def root as string init bookTree();
    def out as string init expand(
        path.join($root, "book"),
        '\{{#include examples/hello.j}}' + "\n");
    testing.assertEqual($out, '{{#include examples/hello.j}}' + "\n");
    fs.removeAll($root);
}

# Once, not recursively: a file that includes a file that includes a file is a
# knot to untangle at three in the morning.
func testAnIncludedFilesOwnDirectivesAreLeftAlone() {
    def root as string init bookTree();
    def book as string init path.join($root, "book");
    fs.writeString(path.join($book, "examples/nested.j"), '{{#include examples/hello.j}}' + "\n");
    def out as string init expand($book, '{{#include examples/nested.j}}' + "\n");
    testing.assertContains($out, '{{#include examples/hello.j}}');
    testing.assertFalse(strings.contains($out, "three"));
    fs.removeAll($root);
}

func testTheReplyCarriesOnlyWhatChanged() {
    def root as string init bookTree();
    def out as string init replyFor(json.decode(requestFor(
        $root,
        '{{#include examples/hello.j}}' + "\n")));
    testing.assertEqual(json.length(json.decode($out), "/chapters"), 1);
    def quiet as string init replyFor(json.decode(requestFor($root, "Nothing to pull in.\n")));
    testing.assertEqual(json.length(json.decode($quiet), "/chapters"), 0);
    fs.removeAll($root);
}

func testRunExpandsTheBook() {
    def root as string init bookTree();
    testing.assertEqual(run(requestFor($root, '{{#include examples/hello.j}}' + "\n")), 0);
    fs.removeAll($root);
}

# A directive naming something it may not read stops the build, with the message
# on stderr and a status the build can see.
func testRunReportsARefusedDirective() {
    def root as string init bookTree();
    testing.assertEqual(run(requestFor($root, '{{#include ../secret.txt}}' + "\n")), 1);
    fs.removeAll($root);
}

func testRunRefusesARequestItCannotAnswer() {
    def root as string init bookTree();
    def req as string init requestFor($root, "plain\n");
    testing.assertEqual(run(strings.replace($req, '"api":1', '"api":2')), 1);
    testing.assertEqual(run(strings.replace($req, '"preprocessor"', '"renderer"')), 1);
    testing.assertEqual(run(""), 1);
    fs.removeAll($root);
}
