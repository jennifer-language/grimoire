# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `linkcheck.j`, run by `jennifer test linkcheck_test.j`.
 *
 * The check is a walk over files, so most of it is tested against a site built
 * in a temp directory: a page that links to a page that exists, one that does
 * not, an anchor that is there and one that is not. Those are the four answers
 * the plugin gives.
 *
 * The one case worth its own test is a page **documenting** markup. A code span
 * holding `href="ghost.html"` is text, not a link, and a checker that cannot
 * tell the difference fires on every page about HTML - which is how a check ends
 * up switched off.
 * @module linkcheck_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use os;
# The module has no need for `maps`, so the overlay declares its own.
use maps;

# A site on disk. `pages` is a map of file name to markup.
func siteWith(pages as map of string to string) {
    def root as string init fs.makeTempDir(os.tempDir(), "linkcheck-");
    for (def name in maps.keys($pages)) {
        fs.writeString(path.join($root, $name), $pages[$name]);
    }
    return $root;
}

func page(body as string) {
    return "<html><body>" + $body + "</body></html>";
}

# --- what is external ------------------------------------------------

func testExternalIsAnythingWithASchemeOrAnAuthority() {
    testing.assertTrue(isExternal("https://example.com/x"));
    testing.assertTrue(isExternal("http://example.com"));
    testing.assertTrue(isExternal("//cdn.example.com/x.js"));
    testing.assertTrue(isExternal("mailto:a@example.com"));
    testing.assertTrue(isExternal("data:text/plain,x"));
    testing.assertFalse(isExternal("two.html"));
    testing.assertFalse(isExternal("../up/two.html"));
    testing.assertFalse(isExternal("#anchor"));
}

func testATargetAndAFragmentComeApart() {
    testing.assertEqual(target("two.html#here"), "two.html");
    testing.assertEqual(fragment("two.html#here"), "here");
    testing.assertEqual(target("two.html"), "two.html");
    testing.assertEqual(fragment("two.html"), "");
    testing.assertEqual(target("#here"), "");
    testing.assertEqual(fragment("#here"), "here");
}

# --- the walk --------------------------------------------------------

func testACleanSiteHasNoFindings() {
    def pages as map of string to string;
    $pages["index.html"] = page('<a href="two.html">two</a> <a href="two.html#s">deep</a>');
    $pages["two.html"] = page('<h2 id="s">S</h2>');
    def root as string init siteWith($pages);
    testing.assertEqual(len(check($root, false)), 0);
    fs.removeAll($root);
}

func testADeadFileIsFound() {
    def pages as map of string to string;
    $pages["index.html"] = page('<a href="missing.html">gone</a>');
    def root as string init siteWith($pages);
    def findings as list of string init check($root, false);
    testing.assertEqual(len($findings), 1);
    testing.assertContains($findings[0], "missing.html");
    testing.assertContains($findings[0], "no such file");
    fs.removeAll($root);
}

func testADeadAnchorIsFound() {
    def pages as map of string to string;
    $pages["index.html"] = page('<a href="two.html#nowhere">deep</a>');
    $pages["two.html"] = page('<h2 id="somewhere">S</h2>');
    def root as string init siteWith($pages);
    def findings as list of string init check($root, false);
    testing.assertEqual(len($findings), 1);
    testing.assertContains($findings[0], "no such anchor");
    fs.removeAll($root);
}

# A link to an anchor on the page it is written in needs no second file.
func testAnAnchorOnTheSamePageIsChecked() {
    def pages as map of string to string;
    $pages["index.html"] = page('<a href="#here">here</a> <a href="#gone">gone</a>' +
        '<h2 id="here">H</h2>');
    def root as string init siteWith($pages);
    def findings as list of string init check($root, false);
    testing.assertEqual(len($findings), 1);
    testing.assertContains($findings[0], "#gone");
    fs.removeAll($root);
}

# An `img` points at something that has to be there as much as an `a` does.
func testAMissingPictureIsFound() {
    def pages as map of string to string;
    $pages["index.html"] = page('<img src="nopic.png" alt="x"/>');
    def root as string init siteWith($pages);
    testing.assertEqual(len(check($root, false)), 1);
    fs.removeAll($root);
}

# The reason this check is usable: a page about HTML is full of markup as text.
func testACodeSpanIsNotALink() {
    def pages as map of string to string;
    $pages["index.html"] = page('<p>write <code>&lt;a href="ghost.html"&gt;</code> ' +
        'or <code>href="also-ghost.html"</code></p>');
    def root as string init siteWith($pages);
    testing.assertEqual(len(check($root, false)), 0);
    fs.removeAll($root);
}

# Every finding, not the first: a build that stops at one is run once per dead
# link.
func testEveryFindingIsReported() {
    def pages as map of string to string;
    $pages["index.html"] = page('<a href="a.html">a</a><a href="b.html">b</a>' +
        '<a href="c.html">c</a>');
    def root as string init siteWith($pages);
    testing.assertEqual(len(check($root, false)), 3);
    fs.removeAll($root);
}

# With the network switched off, an external link is not a finding whatever it
# points at.
func testExternalLinksAreLeftAloneByDefault() {
    def pages as map of string to string;
    $pages["index.html"] = page('<a href="https://no-such-host.invalid/x">out</a>');
    def root as string init siteWith($pages);
    testing.assertEqual(len(check($root, false)), 0);
    fs.removeAll($root);
}

func checkMissingSite() {
    check(path.join(os.tempDir(), "linkcheck-no-such-site"), false);
}

func testAMissingSiteIsRefused() {
    testing.assertThrows("checkMissingSite", "plugin");
}

# --- run -------------------------------------------------------------

func testRunRefusesAnEmptyRequest() {
    testing.assertEqual(run("   "), 1);
}

func testRunRefusesAnotherApiVersion() {
    testing.assertEqual(run('{"api":99,"kind":"renderer","book":{"out":"site"}}'), 1);
}

# One program can implement both kinds, so it has to be told which it is being
# asked for - and refuse the other.
func testRunRefusesAPreprocessorRequest() {
    testing.assertEqual(run('{"api":1,"kind":"preprocessor","book":{"out":"site"}}'), 1);
}

func testRunPassesACleanSite() {
    def pages as map of string to string;
    $pages["index.html"] = page("<p>no links at all</p>");
    def root as string init siteWith($pages);
    def request as string init '{"api":1,"kind":"renderer","book":{"out":' +
        json.encode($root) + '},"plugin":{"name":"linkcheck","settings":{}}}';
    testing.assertEqual(run($request), 0);
    fs.removeAll($root);
}

func testRunFailsOnADeadLink() {
    def pages as map of string to string;
    $pages["index.html"] = page('<a href="gone.html">gone</a>');
    def root as string init siteWith($pages);
    def request as string init '{"api":1,"kind":"renderer","book":{"out":' +
        json.encode($root) + '},"plugin":{"name":"linkcheck","settings":{}}}';
    testing.assertEqual(run($request), 1);
    fs.removeAll($root);
}
