# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `watch.j`, run by `jennifer test src/watch_test.j`.
 *
 * `run` blocks until the process is interrupted and `rebuild` needs a book, so
 * both are left to the end-to-end checks. What is testable here is the filter,
 * and the filter is where the bug would be.
 *
 * `ignorable` is what stops the loop from rebuilding for ever on a book whose
 * output directory sits inside its source tree: the first rebuild writes into
 * the tree being watched, which is another change, which is another rebuild.
 * Draining the queue afterwards does not fix it - the write lands before the
 * scan that finds it - so this test is the only thing standing between that
 * layout and an infinite loop.
 * @module watch_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use strings;

func event(p as string, isDir as bool) {
    return fs.Event{path: $p, kind: "modified", isDir: $isDir};
}

# --- ignored ---------------------------------------------------------

func testIgnoredIsThePrefixWeWrote() {
    testing.assertEqual(ignored("site"), "site/");
    testing.assertEqual(ignored("docs/site"), "docs/site/");
}

func testIgnoredNormalisesThePath() {
    testing.assertEqual(ignored("./site/"), "site/");
    testing.assertEqual(ignored("site//"), "site/");
}

# "" for a watch with nothing of ours underneath it, which is the ordinary case.
func testIgnoredIsEmptyForNoOutputDirectory() {
    testing.assertEqual(ignored(""), "");
}

# --- ignorable -------------------------------------------------------

# Adding or removing a file bumps its directory's mtime, so every child event
# arrives with one. The child is behind it in the queue, and a directory on its
# own has nothing to render.
func testADirectoryEventIsIgnorable() {
    testing.assertTrue(ignorable(event("docs/guide", true), ""));
    testing.assertTrue(ignorable(event("docs/guide", true), "site/"));
}

func testAnOrdinarySourceChangeIsNot() {
    testing.assertFalse(ignorable(event("docs/index.md", false), ""));
    testing.assertFalse(ignorable(event("docs/index.md", false), "site/"));
}

# The reason this function exists: a book whose output directory sits inside its
# source tree would otherwise rebuild for ever.
func testOurOwnOutputIsIgnorable() {
    testing.assertTrue(ignorable(event("docs/site/index.html", false), "docs/site/"));
    testing.assertTrue(ignorable(event("docs/site/assets/grimoire.css", false), "docs/site/"));
}

func testANeighbourOfTheOutputDirectoryIsNot() {
    # `docs/site-notes.md` shares a prefix with `docs/site` but is not inside it.
    testing.assertFalse(ignorable(event("docs/site-notes.md", false), "docs/site/"));
}

func testThePathIsCleanedBeforeItIsCompared() {
    testing.assertTrue(ignorable(event("./docs/site/index.html", false), "docs/site/"));
    testing.assertTrue(ignorable(event("docs/./site/index.html", false), "docs/site/"));
}

# With no output directory underneath the watch there is nothing to filter, so
# every file event is a real change.
func testNothingIsOursWhenThePrefixIsEmpty() {
    testing.assertFalse(ignorable(event("site/index.html", false), ""));
}

# --- also ------------------------------------------------------------

# A single-file save is the usual case and gets no suffix at all.
func testAlsoIsSilentForOneChange() {
    testing.assertEqual(also(0), "");
    testing.assertEqual(also(-1), "");
}

func testAlsoCountsTheRest() {
    testing.assertEqual(also(1), " and 1 more");
    testing.assertEqual(also(12), " and 12 more");
}

# --- notice ----------------------------------------------------------

func testNoticeNamesTheDirectoryBeingWatched() {
    def c as config.Config init config.defaults();
    $c.srcDir = "chapters";
    testing.assertContains(notice($c, true), "chapters/");
    testing.assertContains(notice($c, false), "chapters/");
}

# The notice says which of the two things is happening, because the difference
# matters to whoever is about to alt-tab to a browser.
func testNoticeSaysWhetherTheBrowserFollowsAlong() {
    def c as config.Config init config.defaults();
    testing.assertContains(notice($c, true), "the page reloads itself");
    testing.assertContains(notice($c, false), "reload the page to see them");
    testing.assertNotEqual(notice($c, true), notice($c, false));
}

# --- the constants -----------------------------------------------------

# Fast enough that a save and a reload feel connected, slow enough to stay
# invisible on a battery.
func testThePollIntervalIsInteractive() {
    testing.assertTrue(POLL_MS >= 100 and POLL_MS <= 1000);
}

# Far below the poll interval, so it is invisible; far above the gap between two
# pushes onto a queue. A settle as long as the poll would drop the next save.
func testTheSettleIsWellInsideThePoll() {
    testing.assertTrue(SETTLE_MS > 0);
    testing.assertTrue(SETTLE_MS < POLL_MS // 2);
}
