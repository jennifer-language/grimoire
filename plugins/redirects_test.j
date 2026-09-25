# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `redirects.j`, run by `jennifer test redirects_test.j`.
 *
 * The interesting part is the arithmetic of a relative path, and the two
 * refusals: a stub that would leave the site, and a stub that would overwrite a
 * real page with a redirect away from itself.
 * @module redirects_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use os;

# A built site with one real page in it, and the request a build would send.
func siteTree() {
    def root as string init fs.makeTempDir(os.tempDir(), "redirects-");
    fs.mkdirAll(path.join($root, "site/guide"));
    fs.writeString(path.join($root, "site/index.html"), "<p>the book</p>");
    fs.writeString(path.join($root, "site/guide/syntax.html"), "<p>syntax</p>");
    return $root;
}

# The same request, with the outline a real book would carry.
func requestWithOutline(root as string, settings as string) {
    return strings.replace(
        requestFor($root, $settings),
        '"entries":[]',
        '"entries":[{"kind":"page","title":"Start","src":"index.md","out":"index.html",' +
            '"level":0,"number":"1"}]');
}

func requestFor(root as string, settings as string) {
    return '{"api":1,"kind":"renderer","book":{"title":"A Book","description":"d",' +
        '"authors":["Ada"],"language":"en","src":"docs","out":' +
        json.encode(path.join($root, "site")) + '},' +
        '"plugin":{"name":"redirects","settings":' + $settings + '},' +
        '"entries":[],"chapters":[]}';
}

func testAPathIsRelativeToTheStubThatHoldsIt() {
    testing.assertEqual(relativeTo("old.html", "index.html"), "index.html");
    testing.assertEqual(relativeTo("guide/old.html", "guide/new.html"), "new.html");
    testing.assertEqual(relativeTo("guide/old.html", "index.html"), "../index.html");
    testing.assertEqual(
        relativeTo("guide/old.html", "reference/new.html"),
        "../reference/new.html");
    testing.assertEqual(relativeTo("a/b/c/old.html", "a/new.html"), "../../new.html");
}

# A full URL, an absolute path and a fragment are the author's own and are used
# as written: a book may move to another site entirely.
func testATargetThatIsNotAPathIsLeftAlone() {
    testing.assertEqual(
        relativeTo("old.html", "https://example.com/new"),
        "https://example.com/new");
    testing.assertEqual(relativeTo("guide/old.html", "/new.html"), "/new.html");
}

func testTheStubRefreshesAndSaysWhereTo() {
    def out as string init stub(Move{from: "guide/old.html", target: "index.html"}, "de");
    testing.assertContains($out, '<html lang="de">');
    testing.assertContains($out, 'content="0; url=../index.html"');
    testing.assertContains($out, '<link rel="canonical" href="../index.html">');
    testing.assertContains($out, '<a href="../index.html">its new address</a>');
    # Nothing should index a page whose only content is a link away from it.
    testing.assertContains($out, 'name="robots" content="noindex"');
}

# The target reaches an attribute, so a hostile table cannot put a script in it.
func testAJavascriptTargetIsNeutralised() {
    def out as string init stub(Move{from: "old.html", target: "javascript:alert(1)"}, "en");
    testing.assertFalse(strings.contains($out, "javascript:alert"));
}

func testMovesAreSortedAndReservedKeysAreSkipped() {
    def root as string init siteTree();
    def settings as string init '{"command":"./grimoire-redirects","args":[],' +
        '"z.html":"index.html","a.html":"index.html"}';
    def req as json.Value init json.decode(requestFor($root, $settings));
    def found as list of Move init moves($req);
    testing.assertEqual(len($found), 2);
    testing.assertEqual($found[0].from, "a.html");
    testing.assertEqual($found[1].from, "z.html");
    fs.removeAll($root);
}

func testWritesEveryStubAndReportsIt() {
    def root as string init siteTree();
    def req as json.Value init json.decode(requestFor(
        $root,
        '{"old.html":"index.html","guide/old-name.html":"guide/syntax.html"}'));
    def result as list of string init write($req);
    testing.assertEqual($result[0], "guide/old-name.html\nold.html");
    testing.assertEqual($result[1], "");
    testing.assertTrue(fs.isFile(path.join($root, "site/old.html")));
    testing.assertContains(
        fs.readString(path.join($root, "site/guide/old-name.html")),
        'url=syntax.html');
    fs.removeAll($root);
}

# The stub would replace the page it is named after. That is a configuration
# mistake, and a silent one: the page still exists, and now redirects away from
# itself.
func testAChapterOfTheBookIsNeverReplaced() {
    def root as string init siteTree();
    def req as json.Value init json.decode(requestWithOutline(
        $root,
        '{"index.html":"guide/syntax.html"}'));
    def result as list of string init write($req);
    testing.assertEqual($result[0], "");
    testing.assertContains($result[1], "is a page of this book, not replaced");
    testing.assertEqual(fs.readString(path.join($root, "site/index.html")), "<p>the book</p>");
    fs.removeAll($root);
}

# Anything else already sitting there is somebody's file too - an asset, a
# hand-written page - and is refused on the evidence rather than on the outline.
func testAFileThisPluginDidNotWriteIsNeverReplaced() {
    def root as string init siteTree();
    def req as json.Value init json.decode(requestFor($root, '{"guide/syntax.html":"index.html"}'));
    def result as list of string init write($req);
    testing.assertEqual($result[0], "");
    testing.assertContains($result[1], "already exists and is not a redirect");
    testing.assertEqual(fs.readString(path.join($root, "site/guide/syntax.html")), "<p>syntax</p>");
    fs.removeAll($root);
}

# A build that is not `--clean` finds the last build's stubs in place. They are
# this plugin's own, they are rewritten, and nothing is reported: otherwise every
# redirect would be a warning from the second build on.
func testItsOwnStubsAreRewrittenWithoutComplaint() {
    def root as string init siteTree();
    def req as json.Value init json.decode(requestFor($root, '{"old.html":"index.html"}'));
    testing.assertEqual(write($req)[0], "old.html");
    def again as list of string init write($req);
    testing.assertEqual($again[0], "old.html");
    testing.assertEqual($again[1], "");
    fs.removeAll($root);
}

func testAStubOutsideTheSiteIsRefused() {
    def root as string init siteTree();
    def req as json.Value init json.decode(requestFor(
        $root,
        '{"../escaped.html":"index.html","/tmp/absolute.html":"index.html"}'));
    def result as list of string init write($req);
    testing.assertEqual($result[0], "");
    testing.assertContains($result[1], "is outside the site, not written");
    testing.assertFalse(fs.isFile(path.join($root, "escaped.html")));
    fs.removeAll($root);
}

func testTheReplyCarriesOnlyTheListsItHas() {
    testing.assertEqual(reply("", ""), '{"api":1}');
    testing.assertEqual(reply("a.html", ""), '{"api":1,"written":["a.html"]}');
    testing.assertContains(reply("a.html", "careful"), '"warnings":["careful"]');
}

func aRedirectThatIsNotAString() {
    def root as string init siteTree();
    def req as json.Value init json.decode(requestFor($root, '{"old.html":["a","b"]}'));
    try {
        moves($req);
    } catch (e) {
        fs.removeAll($root);
        throw $e;
    }
}

func testARedirectHasToBeOneStringToAnother() {
    testing.assertThrows("aRedirectThatIsNotAString", "plugin");
}

func testRunWritesTheStubs() {
    def root as string init siteTree();
    testing.assertEqual(run(requestFor($root, '{"old.html":"index.html"}')), 0);
    testing.assertTrue(fs.isFile(path.join($root, "site/old.html")));
    fs.removeAll($root);
}

func testRunRefusesARequestItCannotAnswer() {
    def root as string init siteTree();
    def req as string init requestFor($root, '{}');
    testing.assertEqual(run(strings.replace($req, '"api":1', '"api":2')), 1);
    testing.assertEqual(run(strings.replace($req, '"renderer"', '"preprocessor"')), 1);
    testing.assertEqual(run(""), 1);
    fs.removeAll($root);
}
