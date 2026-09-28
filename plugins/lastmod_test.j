# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `lastmod.j`, run by `jennifer test lastmod_test.j`.
 *
 * The git tests build real repositories with staged commit dates, because the
 * question this plugin answers is exactly "what does git say", and a fake answer
 * would test the fake. The rest is the shape of the line it appends.
 * @module lastmod_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use fs;
use path;

# --- the machine may have no git ---------------------------------------
#
# The interpreter image carries none - it is debian-slim, the interpreter and
# ca-certificates - so the tests below cannot demand a repository. This plugin is
# specified to work both ways, and `withoutGit` asserts the half a machine without
# git can reach: nothing added, no error, no build stopped. The git half is
# covered wherever git exists, which for CI means the image `scripts/ci-git-image.sh`
# builds for exactly that job.
func gitAvailable() {
    def result as os.Result;
    try {
        $result = os.run(["git", "--version"]);
    } catch (e) {
        return false;
    }
    return $result.exitCode == 0;
}

# True when this machine cannot run a git test, having first asserted what the
# plugin does without one.
func withoutGit() {
    if (gitAvailable()) {
        return false;
    }
    testing.assertFalse(isCheckout(os.tempDir()));
    testing.assertEqual(dateOf(os.tempDir(), "index.md", "%Y-%m-%d"), "");
    return true;
}

# A checkout with two chapters committed on two different days, and one that is
# written but never committed.
func bookRepo() {
    def root as string init fs.makeTempDir(os.tempDir(), "lastmod-");
    fs.mkdirAll(path.join($root, "guide"));
    os.run(["git", "-C", $root, "init", "-q"]);
    os.run(["git", "-C", $root, "config", "user.email", "t@example.com"]);
    os.run(["git", "-C", $root, "config", "user.name", "Test"]);
    fs.writeString(path.join($root, "index.md"), "# Start\n\nA first chapter.\n");
    commit($root, "index.md", "2026-03-01T10:00:00");
    fs.writeString(path.join($root, "guide/syntax.md"), "# Syntax\n\nA second chapter.\n");
    commit($root, "guide/syntax.md", "2026-04-15T09:30:00");
    fs.writeString(path.join($root, "fresh.md"), "# Fresh\n\nNot committed.\n");
    return $root;
}

func commit(root as string, file as string, dated as string) {
    os.run(["git", "-C", $root, "add", $file]);
    os.run([
        "git",
        "-C",
        $root,
        "-c",
        "user.email=t@example.com",
        "-c",
        "user.name=Test",
        "commit",
        "-q",
        "--date=" + $dated,
        "-m",
        "wrote " + $file,
        "--",
        $file
    ]);
}

func requestFor(root as string, settings as string) {
    return '{"api":1,"kind":"preprocessor","book":{"title":"A Book","description":"d",' +
        '"authors":["Ada"],"language":"en","src":' + json.encode($root) + ',"out":"site"},' +
        '"plugin":{"name":"lastmod","settings":' + $settings + '},' +
        '"entries":[],"chapters":[' +
        '{"src":"index.md","content":"# Start\n\nA first chapter.\n"},' +
        '{"src":"guide/syntax.md","content":"# Syntax\n\nA second chapter.\n"},' +
        '{"src":"fresh.md","content":"# Fresh\n\nNot committed.\n"}]}';
}

func testTheDateIsTheLastCommitThatTouchedTheFile() {
    if (withoutGit()) {
        return;
    }
    def root as string init bookRepo();
    testing.assertEqual(dateOf($root, "index.md", "%Y-%m-%d"), "2026-03-01");
    testing.assertEqual(dateOf($root, "guide/syntax.md", "%Y-%m-%d"), "2026-04-15");
    fs.removeAll($root);
}

# The layout is git's, which is strftime, which is also what Jennifer's own
# `time.format` takes. One idea of what a date looks like, not two.
func testTheFormatIsPassedThroughToGit() {
    if (withoutGit()) {
        return;
    }
    def root as string init bookRepo();
    testing.assertEqual(dateOf($root, "index.md", "%d.%m.%Y"), "01.03.2026");
    testing.assertEqual(dateOf($root, "index.md", "%Y"), "2026");
    fs.removeAll($root);
}

# A month name is whatever the machine's locale calls it - "March" on one runner
# and "Maerz" on another - so a format that spells one out gives a book that is
# not byte-identical between machines. The numeric formats are safe, the README
# says so, and this is the test that would notice if git stopped honouring the
# locale and the advice became wrong.
func testASpelledOutMonthFollowsTheMachinesLocale() {
    if (withoutGit()) {
        return;
    }
    def root as string init bookRepo();
    def spelled as string init dateOf($root, "index.md", "%B %Y");
    testing.assertContains($spelled, "2026");
    testing.assertNotEqual($spelled, "03 2026");
    fs.removeAll($root);
}

func testAFileGitHasNeverSeenHasNoDate() {
    if (withoutGit()) {
        return;
    }
    def root as string init bookRepo();
    testing.assertEqual(dateOf($root, "fresh.md", "%Y-%m-%d"), "");
    testing.assertEqual(dateOf($root, "never-existed.md", "%Y-%m-%d"), "");
    fs.removeAll($root);
}

func testADirectoryWithNoGitAnswersNothing() {
    def root as string init fs.makeTempDir(os.tempDir(), "lastmod-bare-");
    fs.writeString(path.join($root, "index.md"), "# Start\n");
    testing.assertFalse(isCheckout($root));
    testing.assertEqual(dateOf($root, "index.md", "%Y-%m-%d"), "");
    fs.removeAll($root);
}

func testTheLineGoesOnTheEndOnce() {
    def out as string init stamped("# Start\n\nProse.\n", "Last updated", "2026-03-01");
    testing.assertEqual($out, "# Start\n\nProse.\n\n*Last updated: 2026-03-01*\n");
}

# Whatever the chapter ends with, the line is separated from it by one blank
# line: a chapter that ends mid-paragraph would otherwise swallow the date.
func testTrailingNewlinesDoNotPileUp() {
    testing.assertEqual(
        stamped("Prose.\n\n\n", "Updated", "2026-03-01"),
        "Prose.\n\n*Updated: 2026-03-01*\n");
    testing.assertEqual(
        stamped("Prose.", "Updated", "2026-03-01"),
        "Prose.\n\n*Updated: 2026-03-01*\n");
}

func testAChapterWithNoDateIsUntouched() {
    testing.assertEqual(stamped("# Fresh\n", "Last updated", ""), "# Fresh\n");
}

func testTheReplyCarriesOnlyTheChaptersGitKnows() {
    if (withoutGit()) {
        return;
    }
    def root as string init bookRepo();
    def out as string init replyFor(json.decode(requestFor($root, '{}')));
    def reply as json.Value init json.decode($out);
    testing.assertEqual(json.asInt($reply, "/api"), 1);
    testing.assertEqual(json.length($reply, "/chapters"), 2);
    testing.assertEqual(json.asString($reply, "/chapters/0/src"), "index.md");
    testing.assertContains(
        json.asString($reply, "/chapters/0/content"),
        "*Last updated: 2026-03-01*");
    fs.removeAll($root);
}

func testTheLabelAndTheFormatAreTheBooksOwn() {
    if (withoutGit()) {
        return;
    }
    def root as string init bookRepo();
    def settings as string init '{"label":"Zuletzt geaendert","format":"%d.%m.%Y"}';
    def reply as json.Value init json.decode(replyFor(json.decode(requestFor($root, $settings))));
    testing.assertContains(
        json.asString($reply, "/chapters/0/content"),
        "*Zuletzt geaendert: 01.03.2026*");
    fs.removeAll($root);
}

# A book built from a tarball gets nothing added, and is not an error: it is a
# perfectly good way to build a book, with no history to date it by.
func testABookThatIsNotACheckoutChangesNothing() {
    def root as string init fs.makeTempDir(os.tempDir(), "lastmod-bare-");
    def reply as json.Value init json.decode(replyFor(json.decode(requestFor($root, '{}'))));
    testing.assertEqual(json.length($reply, "/chapters"), 0);
    fs.removeAll($root);
}

func testRunStampsTheBook() {
    if (withoutGit()) {
        return;
    }
    def root as string init bookRepo();
    testing.assertEqual(run(requestFor($root, '{}')), 0);
    fs.removeAll($root);
}

func testRunRefusesARequestItCannotAnswer() {
    def root as string init fs.makeTempDir(os.tempDir(), "lastmod-bare-");
    def req as string init requestFor($root, '{}');
    testing.assertEqual(run(strings.replace($req, '"api":1', '"api":2')), 1);
    testing.assertEqual(run(strings.replace($req, '"preprocessor"', '"renderer"')), 1);
    testing.assertEqual(run(""), 1);
    fs.removeAll($root);
}
