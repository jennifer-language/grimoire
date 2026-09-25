# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `epub.j`, run by `jennifer test epub_test.j`.
 *
 * Two things here are worth more than the rest. The archive is written by hand,
 * so the byte order, the checksum and the stored first entry are tested against
 * fixed values rather than against the code that produced them. And the same
 * book has to give the same bytes, which is checked by building one twice.
 * @module epub_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use os;

# A minimal book on disk: one chapter, one picture, one link between them.
func bookTree() {
    def root as string init fs.makeTempDir(os.tempDir(), "epub-");
    fs.mkdirAll(path.join($root, "src/img"));
    fs.mkdirAll(path.join($root, "out"));
    fs.writeString(path.join($root, "src/index.md"), "# Intro\n\nSee [syntax](guide/syntax.md).\n");
    fs.mkdirAll(path.join($root, "src/guide"));
    fs.writeString(
        path.join($root, "src/guide/syntax.md"),
        "# Syntax\n\n![logo](../img/logo.png)\n");
    fs.writeBytes(path.join($root, "src/img/logo.png"), convert.bytesFromString("PNG", "utf-8"));
    return $root;
}

# The request Grimoire would send for that book. Raw strings throughout: a
# cooked one would read the JSON braces as interpolations.
func requestFor(root as string) {
    return '{"api":1,"kind":"renderer","book":{"title":"A Book","description":"d",' +
        '"authors":["Ada"],"language":"en","src":' + json.encode(path.join($root, "src")) +
        ',"out":' + json.encode(path.join($root, "out")) + '},' +
        '"plugin":{"name":"epub","settings":{}},' +
        '"entries":[{"kind":"page","title":"Intro","src":"index.md","out":"index.html",' +
        '"level":0,"number":"1"},' +
        '{"kind":"page","title":"Syntax","src":"guide/syntax.md","out":"guide/syntax.html",' +
        '"level":0,"number":"2"}],' +
        '"chapters":[{"src":"index.md","content":"# Intro\n\nSee [syntax](guide/syntax.md).\n"},' +
        '{"src":"guide/syntax.md","content":"# Syntax\n\n![logo](../img/logo.png)\n"}]}';
}

func digestOf(data as bytes) {
    return encoding.toText(hash.compute($data, "sha256"), "hex");
}

func testLittleEndianFieldsAreWrittenLowByteFirst() {
    def small as bytes init le16(0x0201);
    testing.assertEqual(len($small), 2);
    testing.assertEqual($small[0], 1);
    testing.assertEqual($small[1], 2);
    def wide as bytes init le32(0x04030201);
    testing.assertEqual(len($wide), 4);
    testing.assertEqual($wide[0], 1);
    testing.assertEqual($wide[3], 4);
}

# The check value every crc32 implementation is published with.
func testTheChecksumMatchesTheKnownCheckValue() {
    testing.assertEqual(crcOf(bytesOf("123456789")), 0xcbf43926);
    testing.assertEqual(crcOf(bytesOf("")), 0);
}

func testTheArchiveOpensWithAStoredMimetype() {
    def z as bytes init zipOf([
        File{name: "mimetype", data: bytesOf(MIMETYPE)},
        File{name: "OEBPS/style.css", data: bytesOf(CSS)}
    ]);
    testing.assertTrue(binary.startsWith($z, le32(0x04034b50)));
    # Bytes 8 and 9 are the compression method: 0 is stored, 8 is deflate.
    testing.assertEqual($z[8], 0);
    testing.assertEqual($z[9], 0);
    testing.assertEqual(convert.stringFromBytes(binary.slice($z, 30, 38), "utf-8"), "mimetype");
    testing.assertEqual(
        convert.stringFromBytes(binary.slice($z, 38, 38 + len(MIMETYPE)), "utf-8"),
        MIMETYPE);
}

# Stored, not deflated, for every entry: a payload that would certainly compress
# is in the archive verbatim.
func testEntriesAreNotCompressed() {
    def payload as string init strings.repeat("a", 400);
    def z as bytes init zipOf([File{name: "long.txt", data: bytesOf($payload)}]);
    testing.assertTrue(binary.contains($z, bytesOf($payload)));
}

func testTheDirectoryCountsEveryEntry() {
    def z as bytes init zipOf([
        File{name: "a", data: bytesOf("1")},
        File{name: "b", data: bytesOf("2")},
        File{name: "c", data: bytesOf("3")}
    ]);
    def end as int init len($z) - 22;
    testing.assertTrue(binary.startsWith(binary.slice($z, $end, len($z)), le32(0x06054b50)));
    testing.assertEqual($z[$end + 10], 3);
}

# The whole point of a content document: it has to be XML, not HTML5. The
# renderer writes it that way and this parses the result back rather than
# grepping for a closing slash, because "well formed" is a parser's judgement.
func testAChapterIsAWellFormedXmlDocument() {
    def out as string init document(
        "en",
        "Intro",
        markdown.toXhtml("# T\n\nA line,\n\n---\n\n![p](x.png) and `code`.\n"));
    testing.assertContains($out, '<?xml version="1.0" encoding="utf-8"?>');
    testing.assertContains($out, "<!DOCTYPE html>");
    testing.assertContains($out, '<img src="x.png" alt="p"/>');
    testing.assertContains($out, "<hr/>");
    testing.assertEqual(xml.tag(xml.decode($out)), "html");
}

# Whitespace inside a `<pre>` is content, so the document is not pretty-printed:
# an indented one would put spaces into every code block in the book.
func testCodeBlocksKeepTheirWhitespace() {
    def out as string init document(
        "en",
        "Intro",
        markdown.toXhtml("```sh\nls -l\n\n    indented\n```\n"));
    testing.assertContains($out, "<pre><code>ls -l\n\n    indented</code></pre>");
}

# A chapter that is not XML would reach a reader as a file it refuses to open,
# with a message about the file rather than about the book.
func chapterThatIsNotXml() {
    document("en", "Intro", "<p>unclosed");
}

func testAChapterThatIsNotXmlIsRefused() {
    testing.assertThrows("chapterThatIsNotXml", "plugin");
}

# Escaping is the library's, not this plugin's. What is tested is that the text
# reaching markup goes through it: a title with an ampersand in it used to be one
# careless concatenation away from a file no reader will open.
func testTextThatLooksLikeMarkupIsEscaped() {
    def out as string init document("en", 'Tom & Jerry <"quoted">', "<p>body</p>");
    testing.assertFalse(strings.contains($out, "<title>Tom & Jerry"));
    testing.assertContains($out, "Tom &amp; Jerry");
    testing.assertEqual(xml.tag(xml.decode($out)), "html");
    def opf as string init contentOpf(
        "Tom & Jerry",
        "en",
        "A <description>",
        ["Ada & Grace"],
        [],
        [],
        "");
    testing.assertContains($opf, "<dc:title>Tom &amp; Jerry</dc:title>");
    testing.assertContains($opf, "<dc:creator>Ada &amp; Grace</dc:creator>");
    testing.assertEqual(xml.tag(xml.decode($opf)), "package");
}

func testChapterNamesAreFlattened() {
    testing.assertEqual(fileFor("index.md"), "index.xhtml");
    testing.assertEqual(fileFor("guide/Syntax Rules.md"), "guide-syntax-rules.xhtml");
    testing.assertEqual(fileFor("a/b/c.md"), "a-b-c.xhtml");
}

func testMediaTypesComeFromTheExtension() {
    testing.assertEqual(mediaOf("img/logo.PNG"), "image/png");
    testing.assertEqual(mediaOf("photo.jpeg"), "image/jpeg");
    testing.assertEqual(mediaOf("notes.txt"), "");
    testing.assertEqual(mediaOf("README"), "");
}

func testLinksToChaptersBecomeArchiveNames() {
    def chapters as list of string init ["index.md", "guide/syntax.md"];
    testing.assertContains(
        relinked('<a href="guide/syntax.md">s</a>', "index.md", $chapters),
        'href="guide-syntax.xhtml"');
    testing.assertContains(
        relinked('<a href="../index.md#top">i</a>', "guide/syntax.md", $chapters),
        'href="index.xhtml#top"');
}

func testLinksThatAreNotChaptersAreLeftAlone() {
    def chapters as list of string init ["index.md"];
    def external as string init '<a href="https://example.com/a.md">x</a>';
    testing.assertEqual(relinked($external, "index.md", $chapters), $external);
    def missing as string init '<a href="gone.md">x</a>';
    testing.assertEqual(relinked($missing, "index.md", $chapters), $missing);
}

func testPicturesKeepTheirExtension() {
    testing.assertEqual(pictureName("img/logo.png"), "img-logo.png");
    testing.assertEqual(pictureName("A Logo.PNG"), "a-logo.png");
}

func testPicturesAreFoundRelativeToTheirChapter() {
    def root as string init bookTree();
    def found as list of Picture init pictures(
        '<img src="../img/logo.png">',
        path.join($root, "src"),
        "guide/syntax.md");
    testing.assertEqual(len($found), 1);
    testing.assertEqual($found[0].src, "img/logo.png");
    testing.assertEqual($found[0].name, "img-logo.png");
    testing.assertEqual(
        repictured('<img src="../img/logo.png">', path.join($root, "src"), "guide/syntax.md"),
        '<img src="img-logo.png">');
    fs.removeAll($root);
}

# No clock and no random source: the identifier is the book's own title and
# language, which is what makes a rebuild produce the same file.
func testTheIdentifierIsStableAndShaped() {
    def id as string init identifier("A Book", "en");
    testing.assertEqual($id, identifier("A Book", "en"));
    testing.assertNotEqual($id, identifier("A Book", "de"));
    testing.assertTrue(strings.startsWith($id, "urn:uuid:"));
    testing.assertEqual(len($id), 45);
}

func testTitlesComeFromTheOutline() {
    def root as string init bookTree();
    def titles as map of string to string init titlesOf(json.decode(requestFor($root)));
    testing.assertEqual($titles["index.md"], "Intro");
    testing.assertEqual($titles["guide/syntax.md"], "Syntax");
    fs.removeAll($root);
}

func testTheSameBookGivesTheSameBytes() {
    def root as string init bookTree();
    def req as json.Value init json.decode(requestFor($root));
    testing.assertEqual(digestOf(epubFor($req)), digestOf(epubFor($req)));
    fs.removeAll($root);
}

# The chapter titles the outline gives, not the file names, and the link between
# the two chapters resolved to an archive name.
func testTheBookCarriesItsChaptersAndPicture() {
    def root as string init bookTree();
    def archive as bytes init epubFor(json.decode(requestFor($root)));
    testing.assertTrue(binary.contains($archive, bytesOf("OEBPS/index.xhtml")));
    testing.assertTrue(binary.contains($archive, bytesOf("OEBPS/guide-syntax.xhtml")));
    testing.assertTrue(binary.contains($archive, bytesOf("OEBPS/img-logo.png")));
    testing.assertTrue(binary.contains($archive, bytesOf("<title>Intro</title>")));
    testing.assertTrue(binary.contains($archive, bytesOf('href="guide-syntax.xhtml"')));
    fs.removeAll($root);
}

func coverIsMissing() {
    def root as string init bookTree();
    def text as string init strings.replace(
        requestFor($root),
        '"settings":{}',
        '"settings":{"cover":"img/nope.png"}');
    try {
        epubFor(json.decode($text));
    } catch (e) {
        fs.removeAll($root);
        throw $e;
    }
}

func testAMissingCoverIsRefused() {
    testing.assertThrows("coverIsMissing", "plugin");
}

func testRunWritesTheArchiveWhereTheSettingsSay() {
    def root as string init bookTree();
    def text as string init strings.replace(
        requestFor($root),
        '"settings":{}',
        '"settings":{"output":"dist/book.epub"}');
    testing.assertEqual(run($text), 0);
    testing.assertTrue(fs.isFile(path.join($root, "out/dist/book.epub")));
    fs.removeAll($root);
}

func testRunRefusesARequestItCannotAnswer() {
    def root as string init bookTree();
    testing.assertEqual(run(strings.replace(requestFor($root), '"api":1', '"api":2')), 1);
    testing.assertEqual(run(strings.replace(requestFor($root), '"renderer"', '"preprocessor"')), 1);
    testing.assertEqual(run(""), 1);
    fs.removeAll($root);
}
