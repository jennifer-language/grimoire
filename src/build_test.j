# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `build.j`, run by `jennifer test src/build_test.j`.
 *
 * `run` is covered by the end-to-end checks, which build a real book. What is
 * worth testing here is the scheduler and the reassembly around it, because both
 * are load-bearing for a promise that is easy to break by accident: **byte
 * identical output at any `--jobs`**.
 *
 * Anything that accumulates across chapters has to be put back in outline order
 * rather than in the order workers finish, and any ranking has to break ties
 * deterministically. `assignWork` and `placeRecords` are the two places that do
 * this today, and each has a case below that would fail if the tie-break went
 * away - a failure that a single-threaded build would never show.
 * @module build_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use fs;
use os;
use path;
use strings;
use lists;

func entry(title as string, src as string) {
    return summary.Entry{
        kind: summary.pageKind(),
        title: $title,
        src: $src,
        out: util.htmlPath($src),
        level: 0,
        number: ""
    };
}

# A book on disk, with chapters of the given sizes in KiB, so the scheduler has
# real weights to work with.
func sized(sizes as list of int) {
    def root as string init fs.makeTempDir(os.tempDir(), "grimoire-build-");
    def i as int init 0;
    while ($i < len($sizes)) {
        fs.writeString(
            path.join($root, "ch" + convert.toString($i) + ".md"),
            strings.repeat("x", $sizes[$i] * 1024));
        $i = $i + 1;
    }
    return $root;
}

func pagesOf(root as string, count as int) {
    def out as list of summary.Entry;
    for (def i in 0..$count) {
        $out[] = entry("Chapter", "ch" + convert.toString($i) + ".md");
    }
    return $out;
}

func configFor(root as string) {
    def c as config.Config init config.defaults();
    $c.srcDir = $root;
    return $c;
}

# --- plural and searchNote -------------------------------------------

# So a progress line does not say "1 jobs".
func testPluralPicksTheRightNoun() {
    testing.assertEqual(plural(1, "job", "jobs"), "1 job");
    testing.assertEqual(plural(2, "job", "jobs"), "2 jobs");
    testing.assertEqual(plural(0, "job", "jobs"), "0 jobs");
}

func testSearchNoteFollowsTheSetting() {
    def c as config.Config init config.defaults();
    testing.assertEqual(searchNote($c), ", search index");
    $c.search = false;
    testing.assertEqual(searchNote($c), "");
}

# --- editUrl ---------------------------------------------------------

func testEditUrlFillsThePathSlot() {
    def c as config.Config init config.defaults();
    # Raw strings: a cooked one would read `{path}` as an interpolation.
    $c.editUrlTemplate = 'https://example.com/edit/main/docs/{path}';
    testing.assertEqual(editUrl($c, "guide/x.md"), "https://example.com/edit/main/docs/guide/x.md");
}

func testEditUrlIsEmptyWithoutATemplate() {
    testing.assertEqual(editUrl(config.defaults(), "x.md"), "");
}

# --- titleFor and plainTitle -----------------------------------------

# The outline title wins because it is what the sidebar shows; the chapter's own
# first heading is the fallback.
func testTitleForPrefersTheOutline() {
    def r as content.Rendered init content.Rendered{
        html: "",
        title: "From the chapter",
        headings: [],
        sections: []
    };
    testing.assertEqual(titleFor(entry("From the outline", "x.md"), $r), "From the outline");
    testing.assertEqual(titleFor(entry("", "x.md"), $r), "From the chapter");
}

func testPlainTitleStripsMarkup() {
    testing.assertEqual(plainTitle("The `code` chapter"), "The code chapter");
    testing.assertEqual(plainTitle("  spaced   out  "), "spaced out");
}

# --- rendersRoot -----------------------------------------------------

# Answered from the outline rather than from the output directory: on a rebuild
# the previous run's index.html is still sitting there, so asking the filesystem
# answers a question about the last build.
func testRendersRootReadsTheOutline() {
    testing.assertTrue(rendersRoot([entry("Home", "index.md")]));
    testing.assertTrue(rendersRoot([entry("Home", "README.md")]));
    testing.assertFalse(rendersRoot([entry("Guide", "guide/x.md")]));
    testing.assertFalse(rendersRoot([]));
}

# --- resolvePages and missingPages -----------------------------------

func testResolvePagesDropsMissingSources() {
    def root as string init sized([1, 1]);
    def pages as list of summary.Entry init pagesOf($root, 2);
    $pages[] = entry("Ghost", "nope.md");
    testing.assertEqual(len(resolvePages(configFor($root), $pages)), 2);
    fs.removeAll($root);
}

# Keeping the first mention is what makes previous / next follow the position a
# reader will actually use.
func testResolvePagesKeepsTheFirstOfADuplicate() {
    def root as string init sized([1]);
    def pages as list of summary.Entry init [
        entry("First mention", "ch0.md"),
        entry("Second mention", "ch0.md")
    ];
    def out as list of summary.Entry init resolvePages(configFor($root), $pages);
    testing.assertEqual(len($out), 1);
    testing.assertEqual($out[0].title, "First mention");
    fs.removeAll($root);
}

# A broken SUMMARY is reported rather than silently skipped.
func testMissingPagesNamesWhatIsAbsent() {
    def root as string init sized([1]);
    def pages as list of summary.Entry init [entry("Real", "ch0.md"), entry("Ghost", "nope.md")];
    def missing as list of string init missingPages(configFor($root), $pages);
    testing.assertEqual(len($missing), 1);
    testing.assertEqual($missing[0], "nope.md");
    fs.removeAll($root);
}

# --- workerCount -----------------------------------------------------

func testWorkerCountHonoursTheConfiguration() {
    def c as config.Config init config.defaults();
    $c.jobs = 4;
    testing.assertEqual(workerCount($c, 100), 4);
}

func testWorkerCountDefaultsToOnePerCpu() {
    def c as config.Config init config.defaults();
    $c.jobs = 0;
    testing.assertEqual(workerCount($c, 1000), os.NCPU);
}

# Never more workers than there are chapters: the extra ones would only idle.
func testWorkerCountNeverExceedsTheChapterCount() {
    def c as config.Config init config.defaults();
    $c.jobs = 16;
    testing.assertEqual(workerCount($c, 3), 3);
}

func testWorkerCountIsNeverZero() {
    def c as config.Config init config.defaults();
    $c.jobs = 8;
    testing.assertEqual(workerCount($c, 0), 1);
    $c.jobs = -5;
    testing.assertTrue(workerCount($c, 10) >= 1);
}

# --- leastLoaded -----------------------------------------------------

func testLeastLoadedFindsTheSmallest() {
    testing.assertEqual(leastLoaded([5, 2, 9]), 1);
    testing.assertEqual(leastLoaded([1]), 0);
}

# The lowest-numbered worker on a tie, so the assignment is deterministic.
func testLeastLoadedPrefersTheLowestOnATie() {
    testing.assertEqual(leastLoaded([0, 0, 0]), 0);
    testing.assertEqual(leastLoaded([3, 1, 1]), 1);
}

# --- assignWork ------------------------------------------------------

func testAssignWorkGivesEveryChapterToExactlyOneWorker() {
    def root as string init sized([10, 3, 7, 1, 5]);
    def buckets as list of list of int init assignment(configFor($root), pagesOf($root, 5), 3);
    def seen as list of int;
    for (def bucket in $buckets) {
        for (def i in $bucket) {
            testing.assertFalse(lists.contains($seen, $i));
            $seen[] = $i;
        }
    }
    testing.assertEqual(len($seen), 5);
    fs.removeAll($root);
}

func testAssignWorkMakesOneBucketPerWorker() {
    def root as string init sized([1, 1]);
    testing.assertEqual(len(assignment(configFor($root), pagesOf($root, 2), 4)), 4);
    fs.removeAll($root);
}

# The heaviest chapter goes out first, which is the whole point of the rule: deal
# them out in outline order and one worker ends up holding far more than the rest.
func testAssignWorkPlacesTheHeaviestFirst() {
    def root as string init sized([1, 20, 1]);
    def buckets as list of list of int init assignment(configFor($root), pagesOf($root, 3), 3);
    testing.assertEqual($buckets[0][0], 1);
    fs.removeAll($root);
}

# Even chapters balance evenly, which is the case a naive scheduler also gets
# right - worth pinning so a rewrite cannot regress it.
func testAssignWorkBalancesEvenChapters() {
    def root as string init sized([5, 5, 5, 5]);
    def buckets as list of list of int init assignment(configFor($root), pagesOf($root, 4), 2);
    testing.assertEqual(len($buckets[0]), 2);
    testing.assertEqual(len($buckets[1]), 2);
    fs.removeAll($root);
}

# The promise this whole file is here for. Equal-sized chapters have to break
# their tie the same way every run, or two builds at the same `--jobs` would
# disagree - and a single-threaded build would never show it.
func testAssignWorkIsDeterministic() {
    def root as string init sized([4, 4, 4, 4, 4, 4]);
    def c as config.Config init configFor($root);
    def pages as list of summary.Entry init pagesOf($root, 6);
    def first as list of list of int init assignment($c, $pages, 3);
    for (def again in 0..5) {
        def rerun as list of list of int init assignment($c, $pages, 3);
        for (def w in 0..len($first)) {
            testing.assertEqual(
                strings.join(numbers($rerun[$w]), ","),
                strings.join(numbers($first[$w]), ","));
        }
    }
    fs.removeAll($root);
}

func numbers(xs as list of int) {
    def out as list of string;
    for (def x in $xs) {
        $out[] = convert.toString($x);
    }
    return $out;
}

func testAssignWorkCopesWithAMissingSource() {
    def root as string init sized([1]);
    def pages as list of summary.Entry init [entry("Real", "ch0.md"), entry("Ghost", "nope.md")];
    def buckets as list of list of int init assignment(configFor($root), $pages, 2);
    testing.assertEqual(len($buckets), 2);
    fs.removeAll($root);
}

# --- emptyGroups and placeRecords ------------------------------------

func testEmptyGroupsIsOnePerChapter() {
    testing.assertEqual(len(emptyGroups(5)), 5);
    testing.assertEqual(len(emptyGroups(0)), 0);
    testing.assertEqual(len(emptyGroups(3)[0]), 0);
}

# The other half of the determinism promise: a worker's results go back into
# their chapters' positions, not into the order the workers happened to finish.
func testPlaceRecordsRestoresOutlineOrder() {
    def groups as list of list of search.Record init emptyGroups(4);
    def slice as Slice init Slice{
        chapters: [2, 0],
        chapterRecords: [
            [search.record("c.html", "C", "", "", "third", 1200)],
            [search.record("a.html", "A", "", "", "first", 1200)]
        ],
        written: 0
    };
    def placed as list of list of search.Record init placeRecords($groups, $slice);
    testing.assertEqual($placed[0][0].path, "a.html");
    testing.assertEqual(len($placed[1]), 0);
    testing.assertEqual($placed[2][0].path, "c.html");
    testing.assertEqual(len($placed[3]), 0);
}

func testFlattenRecordsKeepsOrder() {
    def groups as list of list of search.Record init [
        [search.record("a.html", "A", "", "", "one", 1200)],
        [],
        [search.record("c.html", "C", "", "", "three", 1200)]
    ];
    def flat as list of search.Record init flattenRecords($groups);
    testing.assertEqual(len($flat), 2);
    testing.assertEqual($flat[0].path, "a.html");
    testing.assertEqual($flat[1].path, "c.html");
}

# --- pageRecords -----------------------------------------------------

func testPageRecordsSkipsAnEmptyLeadIn() {
    def r as content.Rendered init content.Rendered{
        html: "",
        title: "T",
        headings: [],
        sections: [
            content.Section{anchor: "", heading: "", text: ""},
            content.Section{anchor: "a", heading: "A", text: "body"}
        ]
    };
    def records as list of search.Record init pageRecords(config.defaults(), "x.html", "T", $r);
    testing.assertEqual(len($records), 1);
    testing.assertEqual($records[0].heading, "A");
}

# --- pageKeywords ----------------------------------------------------

func testPageKeywordsFollowsTheSetting() {
    def r as content.Rendered init content.Rendered{
        html: "",
        title: "Concurrency",
        headings: [],
        sections: []
    };
    def c as config.Config init config.defaults();
    testing.assertContains(pageKeywords($c, $r), "concurrency");
    $c.keywords = false;
    testing.assertEqual(pageKeywords($c, $r), "");
}

# --- redirect --------------------------------------------------------

# A meta refresh plus a plain link, so it works with scripting off and never
# leaves a reader on a blank page.
func testRedirectWorksWithoutScripting() {
    def html as string init redirect(config.defaults(), "guide/index.html");
    testing.assertContains($html, 'http-equiv="refresh"');
    testing.assertContains($html, 'href="guide/index.html"');
    testing.assertContains($html, 'rel="canonical"');
    testing.assertContains($html, "<a href=");
}

# --- stripScripts ----------------------------------------------------

# A logo is artwork. A `<script>` inside an inlined SVG would run with the page's
# own origin.
func testStripScriptsRemovesAScript() {
    testing.assertEqual(
        stripScripts("<svg><script>alert(1)</script><circle/></svg>"),
        "<svg><circle/></svg>");
}

func testStripScriptsIsCaseInsensitive() {
    testing.assertFalse(strings.contains(
        strings.lower(stripScripts("<svg><SCRIPT>x</SCRIPT></svg>")),
        "script"));
}

func testStripScriptsRemovesEveryScript() {
    def out as string init stripScripts("<svg><script>a</script><g/><script>b</script></svg>");
    testing.assertFalse(strings.contains($out, "script"));
    testing.assertContains($out, "<g/>");
}

# An unclosed tag truncates rather than leaving the opening behind, which would
# swallow the rest of the page as script source.
func testStripScriptsTruncatesAnUnclosedScript() {
    def out as string init stripScripts("<svg><circle/><script>never closed");
    testing.assertFalse(strings.contains($out, "script"));
    testing.assertContains($out, "<circle/>");
}

func testStripScriptsLeavesCleanArtworkAlone() {
    def svg as string init '<svg viewBox="0 0 24 24"><path d="M0 0h24v24H0z"/></svg>';
    testing.assertEqual(stripScripts($svg), $svg);
}

# --- resolveBrand ----------------------------------------------------

func testResolveBrandIsEmptyWithoutALogo() {
    def root as string init sized([1]);
    testing.assertEqual(resolveBrand(configFor($root)).svg, "");
    testing.assertEqual(resolveBrand(configFor($root)).image, "");
    fs.removeAll($root);
}

func testResolveBrandFallsBackWhenTheFileIsMissing() {
    def root as string init sized([1]);
    def c as config.Config init configFor($root);
    $c.logo = "nope.svg";
    testing.assertEqual(resolveBrand($c).svg, "");
    testing.assertEqual(resolveBrand($c).image, "");
    fs.removeAll($root);
}

func testResolveBrandReferencesANonSvg() {
    def root as string init sized([1]);
    fs.writeString(path.join($root, "logo.png"), "not really a png");
    def c as config.Config init configFor($root);
    $c.logo = "logo.png";
    testing.assertEqual(resolveBrand($c).image, "logo.png");
    fs.removeAll($root);
}

# An XML prolog or a DOCTYPE is legal in a standalone file but not inside an
# HTML document, so everything before the root element comes off.
func testResolveBrandDropsAnXmlProlog() {
    def root as string init sized([1]);
    fs.writeString(path.join($root, "logo.svg"), '<?xml version="1.0"?>\n<svg><circle/></svg>');
    def c as config.Config init configFor($root);
    $c.logo = "logo.svg";
    testing.assertTrue(strings.startsWith(resolveBrand($c).svg, "<svg"));
    fs.removeAll($root);
}

func testResolveBrandStripsScriptsFromAnInlinedLogo() {
    def root as string init sized([1]);
    fs.writeString(path.join($root, "logo.svg"), "<svg><script>alert(1)</script></svg>");
    def c as config.Config init configFor($root);
    $c.logo = "logo.svg";
    testing.assertFalse(strings.contains(resolveBrand($c).svg, "script"));
    fs.removeAll($root);
}

func testResolveBrandRejectsAnSvgWithNoRootElement() {
    def root as string init sized([1]);
    fs.writeString(path.join($root, "logo.svg"), "not markup at all");
    def c as config.Config init configFor($root);
    $c.logo = "logo.svg";
    testing.assertEqual(resolveBrand($c).svg, "");
    fs.removeAll($root);
}

# --- tocFor ----------------------------------------------------------

# The headings are collected either way - the search index and the PDF bookmarks
# are built from the same pass - so turning the column off skips only the list.
func testTocForFollowsTheSetting() {
    def r as content.Rendered init content.render("## A\n\n## B\n", false);
    def c as config.Config init config.defaults();
    testing.assertNotEqual(tocFor($c, $r), "");
    $c.tocPosition = "off";
    testing.assertEqual(tocFor($c, $r), "");
    testing.assertEqual(len($r.headings), 2);
}
