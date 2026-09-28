# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `feed.j`, run by `jennifer test feed_test.j`.
 *
 * Two halves. The ordering and the escaping are pure and are tested directly -
 * a feed whose items are in the wrong order is a feed nobody notices is wrong.
 * The rest needs a repository, so the tests build one: three chapters committed
 * on three dates, which is the only way to prove that the dates come from git
 * rather than from the filesystem.
 * @module feed_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;

# A checkout with `commits` applied in order: each is a file, its text, and the
# date to commit it on.

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
# plugin does without one: no feed, and a warning that says why.
func withoutGit() {
    if (gitAvailable()) {
        return false;
    }
    testing.assertFalse(isCheckout(os.tempDir()));
    return true;
}

func repoWith(files as list of string, texts as list of string, dates as list of string) {
    def root as string init fs.makeTempDir(os.tempDir(), "feed-");
    os.run(["git", "-C", $root, "init", "-q"]);
    os.run(["git", "-C", $root, "config", "user.email", "t@example.com"]);
    os.run(["git", "-C", $root, "config", "user.name", "Test"]);
    def i as int init 0;
    while ($i < len($files)) {
        fs.writeString(path.join($root, $files[$i]), $texts[$i]);
        os.run(["git", "-C", $root, "add", "-A"]);
        os.run([
            "git",
            "-C",
            $root,
            "-c",
            "user.email=t@example.com",
            "commit",
            "-q",
            "--date=" + $dates[$i],
            "-m",
            "change " + $files[$i]
        ]);
        $i = $i + 1;
    }
    return $root;
}

func entryJson(src as string, title as string) {
    return '{"kind":"page","title":' + json.encode($title) + ',"src":' + json.encode($src) +
        ',"out":' + json.encode(strings.replace($src, ".md", ".html")) +
        ',"level":0,"number":""}';
}

func requestFor(root as string, entries as list of string, settings as string) {
    return '{"api":1,"kind":"renderer","book":{"title":"B","description":"d",' +
        '"authors":[],"language":"en","src":' + json.encode($root) + ',"out":"site"},' +
        '"plugin":{"name":"feed","settings":' + $settings + '},"entries":[' +
        strings.join($entries, ",") + '],"chapters":[]}';
}

# --- ordering and escaping -------------------------------------------

# Newest first, which is what a feed reader shows at the top.
func testNewestSortsFirst() {
    testing.assertTrue(sortKey(2000, "a.md") < sortKey(1000, "a.md"));
    testing.assertTrue(sortKey(1000, "a.md") < sortKey(999, "z.md"));
}

# Two chapters committed in the same second keep a fixed order, or the feed
# changes between builds that changed nothing.
func testATieBreaksByPath() {
    testing.assertTrue(sortKey(1000, "a.md") < sortKey(1000, "b.md"));
}

func testTheKeyIsFixedWidth() {
    testing.assertEqual(
        len(strings.split(sortKey(1, "x"), "|")[0]),
        len(strings.split(sortKey(1000000000, "x"), "|")[0]));
}

# The book half of a request, which is all `channel` reads from it.
func bookOf(title as string, description as string) {
    return json.decode('{"book":{"title":' + json.encode($title) + ',"description":' +
        json.encode($description) + ',"language":"en"}}');
}

# Escaping is the `xml` library's, not this plugin's. What is worth testing is
# that everything a person wrote goes through it: a chapter title and a commit
# subject are prose, and one ampersand against a hand-written `<title>` is a feed
# no reader will parse.
func testProseThatLooksLikeMarkupIsEscaped() {
    def items as list of Item init [
        Item{
            key: "k",
            title: "Tom & Jerry",
            href: "https://example.com/a.html?x=1&y=2",
            date: "Sun, 1 Mar 2026 10:00:00 +0000",
            subject: "fixed <the> thing"
        }
    ];
    def req as json.Value init bookOf("A & B", "<em>no</em>");
    def out as string init channel($req, "https://example.com/", "feed.xml", $items);
    testing.assertContains($out, "<title>Tom &amp; Jerry</title>");
    testing.assertContains($out, "<description>fixed &lt;the&gt; thing</description>");
    testing.assertContains($out, "<title>A &amp; B</title>");
    testing.assertContains($out, "x=1&amp;y=2");
    # And the whole thing is a document a parser accepts, which is the property
    # the escaping exists for.
    testing.assertEqual(xml.tag(xml.decode($out)), "rss");
}

# The newest item dates the channel, and the date comes from the item rather than
# from the markup the item was rendered into.
func testTheChannelIsDatedByItsNewestItem() {
    def items as list of Item init [
        Item{
            key: "a",
            title: "New",
            href: "h",
            date: "Tue, 3 Mar 2026 10:00:00 +0000",
            subject: "s"
        },
        Item{
            key: "b",
            title: "Old",
            href: "h",
            date: "Mon, 2 Mar 2026 10:00:00 +0000",
            subject: "s"
        }
    ];
    def req as json.Value init bookOf("T", "d");
    def out as string init channel($req, "https://example.com/", "feed.xml", $items);
    testing.assertContains($out, "<lastBuildDate>Tue, 3 Mar 2026 10:00:00 +0000</lastBuildDate>");
}

# A book with no chapters git knows about writes no feed at all, so the channel
# is never built - but the function has to survive the empty case rather than
# index into nothing.
func testAChannelWithNoItemsHasNoBuildDate() {
    def none as list of Item;
    def req as json.Value init bookOf("T", "d");
    def out as string init channel($req, "https://example.com/", "feed.xml", $none);
    testing.assertFalse(strings.contains($out, "lastBuildDate"));
    testing.assertEqual(xml.tag(xml.decode($out)), "rss");
}

func testJoinKeepsOneSlash() {
    testing.assertEqual(join("https://x.dev/", "a.html"), "https://x.dev/a.html");
    testing.assertEqual(join("https://x.dev", "a.html"), "https://x.dev/a.html");
}

# --- against a repository --------------------------------------------

func testTheDatesComeFromGit() {
    if (withoutGit()) {
        return;
    }
    def root as string init repoWith(
        ["one.md", "two.md"],
        ["# One\n", "# Two\n"],
        ["2026-01-01T10:00:00+0000", "2026-02-02T10:00:00+0000"]);
    def req as json.Value init json.decode(requestFor(
        $root,
        [entryJson("one.md", "One"), entryJson("two.md", "Two")],
        '{"baseUrl":"https://x.dev/"}'));
    def feed as string init feedFor($req);
    testing.assertContains($feed, "Jan 2026");
    testing.assertContains($feed, "Feb 2026");
    # Newest first: the February item opens the list.
    testing.assertTrue(strings.indexOf($feed, "Feb 2026") < strings.indexOf($feed, "Jan 2026"));
    fs.removeAll($root);
}

# `lastBuildDate` is the newest item's own date. The clock would make every
# build a different file.
func testLastBuildDateIsTheNewestItem() {
    if (withoutGit()) {
        return;
    }
    def root as string init repoWith(["one.md"], ["# One\n"], ["2026-01-01T10:00:00+0000"]);
    def req as json.Value init json.decode(requestFor(
        $root,
        [entryJson("one.md", "One")],
        '{"baseUrl":"https://x.dev/"}'));
    def feed as string init feedFor($req);
    def at as int init strings.indexOf($feed, "<lastBuildDate>");
    testing.assertContains(strings.substring($feed, $at, $at + 60), "Jan 2026");
    fs.removeAll($root);
}

func testTheLimitHolds() {
    if (withoutGit()) {
        return;
    }
    def root as string init repoWith(
        ["a.md", "b.md", "c.md"],
        ["# A\n", "# B\n", "# C\n"],
        ["2026-01-01T10:00:00+0000", "2026-01-02T10:00:00+0000", "2026-01-03T10:00:00+0000"]);
    def req as json.Value init json.decode(requestFor(
        $root,
        [entryJson("a.md", "A"), entryJson("b.md", "B"), entryJson("c.md", "C")],
        '{"baseUrl":"https://x.dev/","limit":2}'));
    testing.assertEqual(len(strings.split(feedFor($req), "<item>")), 3);
    fs.removeAll($root);
}

# A chapter git has never seen has no date to publish, and is left out until it
# is committed.
func testAnUncommittedChapterIsLeftOut() {
    if (withoutGit()) {
        return;
    }
    def root as string init repoWith(["one.md"], ["# One\n"], ["2026-01-01T10:00:00+0000"]);
    fs.writeString(path.join($root, "new.md"), "# New\n");
    def req as json.Value init json.decode(requestFor(
        $root,
        [entryJson("one.md", "One"), entryJson("new.md", "New")],
        '{"baseUrl":"https://x.dev/"}'));
    def feed as string init feedFor($req);
    testing.assertEqual(len(strings.split($feed, "<item>")), 2);
    testing.assertFalse(strings.contains($feed, "New"));
    fs.removeAll($root);
}

# --- nothing to publish ----------------------------------------------

# A book does not know where it is published, so a feed of relative links would
# be useless. No baseUrl means no feed, and a warning rather than a failure.
func testWithoutABaseUrlThereIsNoFeed() {
    if (withoutGit()) {
        return;
    }
    def root as string init repoWith(["one.md"], ["# One\n"], ["2026-01-01T10:00:00+0000"]);
    def req as json.Value init json.decode(requestFor($root, [entryJson("one.md", "One")], '{}'));
    testing.assertEqual(feedFor($req), "");
    testing.assertContains(whyNot($req), "baseUrl");
    fs.removeAll($root);
}

# A book built from a tarball has no history. Inventing dates would be worse
# than publishing nothing.
func testWithoutACheckoutThereIsNoFeed() {
    def root as string init fs.makeTempDir(os.tempDir(), "feed-norepo-");
    fs.writeString(path.join($root, "one.md"), "# One\n");
    def req as json.Value init json.decode(requestFor(
        $root,
        [entryJson("one.md", "One")],
        '{"baseUrl":"https://x.dev/"}'));
    testing.assertEqual(feedFor($req), "");
    testing.assertContains(whyNot($req), "no git checkout");
    fs.removeAll($root);
}

# --- run -------------------------------------------------------------

func testRunRefusesAnEmptyRequest() {
    testing.assertEqual(run("  "), 1);
}

func testRunRefusesAPreprocessorRequest() {
    testing.assertEqual(run('{"api":1,"kind":"preprocessor","book":{}}'), 1);
}

# Nothing to publish is a reply with a warning, not a failed build.
func testRunSucceedsWithNothingToPublish() {
    def root as string init fs.makeTempDir(os.tempDir(), "feed-norepo-");
    testing.assertEqual(run(requestFor($root, [], '{"baseUrl":"https://x.dev/"}')), 0);
    fs.removeAll($root);
}
