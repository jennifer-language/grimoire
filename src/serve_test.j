# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `serve.j`, run by `jennifer test src/serve_test.j`.
 *
 * `run` and `loop` need a bound port and a browser, so they are left to the
 * end-to-end checks. Everything they are built out of is pure enough to test
 * here, and two of those pieces carry real weight.
 *
 * `pageFile` is the one place in Grimoire that maps a URL onto the filesystem by
 * hand rather than leaving it to `httpd.serveDir`, so it is also the one place
 * that has to refuse `..` itself. It gets the longest group below.
 *
 * `inject` is the other: the reload script never touches the disk, so a preview
 * build is the same bytes a publish would upload. A test that the splice happens
 * on the way out and not on the way in is a test that `rsync site/` is safe.
 * @module serve_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use fs;
use os;
use path;
use strings;

# A built site, near enough: an index, a nested page, an asset, and the
# stylesheet whose timestamp is the build token.
func site() {
    def root as string init fs.makeTempDir(os.tempDir(), "grimoire-serve-");
    fs.mkdirAll(path.join($root, "guide"));
    fs.mkdirAll(path.join($root, "assets"));
    fs.mkdirAll(path.join($root, "empty"));
    fs.writeString(path.join($root, "index.html"), "<html><body>home</body></html>");
    fs.writeString(path.join($root, "guide/one.html"), "<html><body>one</body></html>");
    fs.writeString(path.join($root, "guide/index.html"), "<html><body>guide</body></html>");
    fs.writeString(path.join($root, "assets/grimoire.css"), "/* css */");
    fs.writeString(path.join($root, "assets/grimoire.js"), "/* js */");
    return $root;
}

# --- token -----------------------------------------------------------

# Every successful build rewrites the stylesheet, so its timestamp moves exactly
# when there is something new to look at - and a build that failed leaves it
# alone. One `stat` answers a poll.
func testTokenReadsTheStylesheetTimestamp() {
    def root as string init site();
    def value as string init token($root);
    testing.assertNotEqual($value, "");
    testing.assertEqual($value, token($root));
    fs.removeAll($root);
}

# "" is read by the script as "nothing to say" rather than as a change, so a
# half-built directory does not send a browser into a reload loop.
func testTokenIsEmptyWithoutAStylesheet() {
    def root as string init fs.makeTempDir(os.tempDir(), "grimoire-serve-bare-");
    testing.assertEqual(token($root), "");
    fs.removeAll($root);
}

func testTokenChangesWhenTheStylesheetIsRewritten() {
    def root as string init site();
    def before as string init token($root);
    fs.writeString(path.join($root, "assets/grimoire.css"), "/* different */");
    testing.assertNotEqual(token($root), $before);
    fs.removeAll($root);
}

# --- pageFile: what it resolves --------------------------------------

func testPageFileResolvesAPage() {
    def root as string init site();
    testing.assertEqual(pageFile($root, "/index.html"), path.join($root, "index.html"));
    testing.assertEqual(pageFile($root, "/guide/one.html"), path.join($root, "guide/one.html"));
    fs.removeAll($root);
}

func testPageFileResolvesADirectoryToItsIndex() {
    def root as string init site();
    testing.assertEqual(pageFile($root, "/"), path.join($root, "index.html"));
    testing.assertEqual(pageFile($root, ""), path.join($root, "index.html"));
    testing.assertEqual(pageFile($root, "/guide/"), path.join($root, "guide/index.html"));
    fs.removeAll($root);
}

# --- pageFile: what it refuses ---------------------------------------

# Not an error - a path that does not resolve here falls through to `serveDir`,
# which handles percent-encoding and everything else this deliberately does not.
func testPageFileIgnoresAssets() {
    def root as string init site();
    testing.assertEqual(pageFile($root, "/assets/grimoire.css"), "");
    testing.assertEqual(pageFile($root, "/assets/grimoire.js"), "");
    fs.removeAll($root);
}

func testPageFileIgnoresAMissingPage() {
    def root as string init site();
    testing.assertEqual(pageFile($root, "/nope.html"), "");
    testing.assertEqual(pageFile($root, "/empty/"), "");
    fs.removeAll($root);
}

# The traversal guard. This is the only hand-written URL-to-path mapping in the
# program, so nothing else is going to catch a `..` that gets through.
func testPageFileRefusesToClimbOut() {
    def root as string init site();
    testing.assertEqual(pageFile($root, "/../secret.html"), "");
    testing.assertEqual(pageFile($root, "/guide/../../secret.html"), "");
    testing.assertEqual(pageFile($root, "/../../etc/passwd.html"), "");
    testing.assertEqual(pageFile($root, "/a/../../b.html"), "");
    fs.removeAll($root);
}

func testPageFileRefusesAnAbsolutePath() {
    def root as string init site();
    testing.assertEqual(pageFile($root, "//etc/hosts.html"), "");
    fs.removeAll($root);
}

# A `..` that stays inside the site is harmless and should still resolve, or a
# perfectly ordinary relative link would 404.
func testPageFileAllowsAnInnerDotDot() {
    def root as string init site();
    testing.assertEqual(pageFile($root, "/guide/../index.html"), path.join($root, "index.html"));
    fs.removeAll($root);
}

# --- inject ----------------------------------------------------------

func testInjectSplicesBeforeTheClosingBody() {
    def page as string init "<html><body>text</body></html>";
    def out as string init inject($page);
    testing.assertContains($out, "<script>");
    testing.assertTrue(strings.indexOf($out, "<script>") < strings.indexOf($out, "</body>"));
    testing.assertTrue(strings.endsWith($out, "</body></html>"));
}

func testInjectKeepsThePageIntact() {
    def out as string init inject("<html><body>text</body></html>");
    testing.assertContains($out, "<html><body>text");
    testing.assertContains($out, "</html>");
}

# Grimoire wrote the page being spliced, three modules away, so a page with no
# closing tag is not a case that arises - but appending is a better answer than
# losing the script.
func testInjectAppendsWhenThereIsNoBodyTag() {
    def out as string init inject("just text");
    testing.assertTrue(strings.startsWith($out, "just text"));
    testing.assertContains($out, "<script>");
}

func testInjectUsesTheReloadEndpoint() {
    def out as string init inject("<body></body>");
    testing.assertContains($out, RELOAD_PATH);
}

# The leading dot keeps the endpoint out of the way of any chapter a book might
# name, and nothing on disk carries it: the splice happens on the response.
func testTheReloadEndpointIsOutOfTheWay() {
    testing.assertTrue(strings.startsWith(RELOAD_PATH, "/."));
}

# --- displayUrl ------------------------------------------------------

func testDisplayUrlLeavesAnExplicitHostAlone() {
    testing.assertEqual(displayUrl("127.0.0.1:8080"), "http://127.0.0.1:8080/");
    testing.assertEqual(displayUrl("example.test:9000"), "http://example.test:9000/");
}

# A bare port or a wildcard host is not something a reader can click.
func testDisplayUrlMakesAWildcardClickable() {
    testing.assertEqual(displayUrl(":8080"), "http://localhost:8080/");
    testing.assertEqual(displayUrl("0.0.0.0:8080"), "http://localhost:8080/");
}
