# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `sitemap.j`, run by `jennifer test plugins/sitemap_test.j`.
 *
 * The plugin is one loop, so most of what can go wrong is at the edges: a base
 * URL with or without its slash, an outline entry that is not a page, a URL with
 * a character XML cannot carry, and a `robots.txt` that is already somebody's.
 * @module sitemap_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use os;

func requestFor(out as string, entries as string) {
    return '{"api":1,"kind":"renderer","book":{"title":"A Book","description":"d",' +
        '"authors":["Ada"],"language":"en","src":"docs","out":' + json.encode($out) + '},' +
        '"plugin":{"name":"sitemap","settings":{"baseUrl":"https://example.com/manual/"}},' +
        '"entries":[' + $entries + '],"chapters":[]}';
}

func entry(kind as string, src as string, out as string) {
    return '{"kind":' + json.encode($kind) + ',"title":"T","src":' + json.encode($src) +
        ',"out":' + json.encode($out) + ',"level":0,"number":"1"}';
}

func siteDir() {
    return fs.makeTempDir(os.tempDir(), "sitemap-");
}

func testTheBaseAndThePageGetExactlyOneSlash() {
    testing.assertEqual(
        join("https://example.com/manual/", "a.html"),
        "https://example.com/manual/a.html");
    testing.assertEqual(
        join("https://example.com/manual", "a.html"),
        "https://example.com/manual/a.html");
}

# Parts and separators are not pages, and a page the build did not write has no
# path to list.
func testOnlyPagesWithAPathAreListed() {
    def entries as string init entry("page", "index.md", "index.html") + "," +
        entry("part", "", "") + "," +
        entry("separator", "", "") + "," +
        entry("page", "draft.md", "") + "," +
        entry("page", "guide/syntax.md", "guide/syntax.html");
    def found as list of string init urls(
        json.decode(requestFor("site", $entries)),
        "https://x.dev/");
    testing.assertEqual(len($found), 2);
    testing.assertEqual($found[0], "https://x.dev/index.html");
    testing.assertEqual($found[1], "https://x.dev/guide/syntax.html");
}

func testTheDocumentIsASitemapAParserAccepts() {
    def out as string init document(["https://example.com/a.html", "https://example.com/b.html"]);
    testing.assertContains($out, '<?xml version="1.0" encoding="utf-8"?>');
    testing.assertContains($out, 'xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"');
    testing.assertContains($out, "<loc>https://example.com/a.html</loc>");
    testing.assertEqual(xml.tag(xml.decode($out)), "urlset");
    testing.assertEqual(len(xml.children(xml.decode($out))), 2);
}

# A path can hold an ampersand, and one unescaped is a document no crawler will
# read. The escaping is the library's; this checks the text goes through it.
func testAUrlThatLooksLikeMarkupIsEscaped() {
    def out as string init document(["https://example.com/a.html?x=1&y=2"]);
    testing.assertContains($out, "x=1&amp;y=2");
    testing.assertEqual(xml.tag(xml.decode($out)), "urlset");
}

func testAnEmptyBookIsStillADocument() {
    def none as list of string;
    testing.assertEqual(xml.tag(xml.decode(document($none))), "urlset");
}

func testRobotsPointsAtTheSitemap() {
    testing.assertContains(
        robotsTxt("https://example.com/manual/"),
        "Sitemap: https://example.com/manual/sitemap.xml");
    testing.assertContains(
        robotsTxt("https://example.com/manual"),
        "Sitemap: https://example.com/manual/sitemap.xml");
}

func testWriteProducesBothFiles() {
    def site as string init siteDir();
    def req as json.Value init json.decode(requestFor(
        $site,
        entry("page", "index.md", "index.html")));
    def written as list of string init write($req, "https://example.com/manual/");
    testing.assertEqual($written, ["sitemap.xml", "robots.txt"]);
    testing.assertContains(
        fs.readString(path.join($site, "sitemap.xml")),
        "<loc>https://example.com/manual/index.html</loc>");
    testing.assertContains(fs.readString(path.join($site, "robots.txt")), "Sitemap:");
    fs.removeAll($site);
}

# A hand-written robots file is the author's. Replacing it would be this plugin
# overruling a decision it knows nothing about.
func testAnExistingRobotsFileIsNeverReplaced() {
    def site as string init siteDir();
    fs.writeString(path.join($site, "robots.txt"), "User-agent: *\nDisallow: /\n");
    def req as json.Value init json.decode(requestFor(
        $site,
        entry("page", "index.md", "index.html")));
    testing.assertEqual(write($req, "https://example.com/manual/"), ["sitemap.xml"]);
    testing.assertContains(fs.readString(path.join($site, "robots.txt")), "Disallow: /");
    fs.removeAll($site);
}

# Without a base URL there is nothing to write: a sitemap of relative paths is
# not a sitemap. It is a warning rather than a failure, because a book that has
# not published yet is not a broken book.
func testNoBaseUrlWritesNothingAndSaysSo() {
    def site as string init siteDir();
    def req as string init strings.replace(
        requestFor($site, entry("page", "index.md", "index.html")),
        '"baseUrl":"https://example.com/manual/"',
        "");
    testing.assertEqual(run($req), 0);
    testing.assertFalse(fs.exists(path.join($site, "sitemap.xml")));
    fs.removeAll($site);
}

func testRunWritesTheSitemap() {
    def site as string init siteDir();
    testing.assertEqual(run(requestFor($site, entry("page", "index.md", "index.html"))), 0);
    testing.assertTrue(fs.isFile(path.join($site, "sitemap.xml")));
    fs.removeAll($site);
}

func testRunRefusesARequestItCannotAnswer() {
    def site as string init siteDir();
    def req as string init requestFor($site, entry("page", "index.md", "index.html"));
    testing.assertEqual(run(strings.replace($req, '"api":1', '"api":2')), 1);
    testing.assertEqual(run(strings.replace($req, '"renderer"', '"preprocessor"')), 1);
    testing.assertEqual(run(""), 1);
    fs.removeAll($site);
}
