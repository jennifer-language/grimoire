# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * An EPUB of the book, built from the same outline as the site.
 *
 * A renderer: it reads the book on stdin as JSON once the site is written, and
 * writes one `.epub` beside it. The chapters come from the request rather than
 * from the built HTML, so what it renders is what the book says.
 *
 * Nothing is installed for this. An EPUB is a zip of XHTML and two small XML
 * files, and the interpreter carries every piece that takes: `markdown.toXhtml`
 * renders the chapters as the well-formed XML a content document has to be, the
 * `xml` library builds the package and the navigation, `crc` checksums the
 * archive entries, and `hash` derives the publication identifier.
 *
 * Markup is built as a tree and encoded, never assembled as text. That is not
 * tidiness: a title with an ampersand in it, concatenated into a `<dc:title>`,
 * produces a file every reader refuses, and the failure a reader shows is not
 * one a build could have explained. Each rendered chapter is parsed back for
 * the same reason - well formed is a parser's judgement, not a regular
 * expression's.
 *
 * One detail decides most of the rest: the `mimetype` entry has to come first
 * and be **stored**, which `archive.pack` cannot express, so the zip is written
 * here - local headers, central directory, end record - with every entry stored
 * and deflate left out entirely.
 *
 * Everything is deterministic: a fixed archive timestamp, an identifier derived
 * from the title rather than a fresh UUID, chapters named after their sources.
 * The same book gives the same bytes, which is what a plugin owes a build that
 * promises byte-identical output.
 * @module epub
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use fs;
use path;
use json;
use strings;
use convert;
use lists;
use maps;
use regex;
use xml;
use crc;
use hash;
use encoding;
use binary;

import "markdown.j" as markdown;

def const API as int init 1;
def const MIMETYPE as string init "application/epub+zip";

# Every entry carries the same date, so two builds of the same book are the same
# file. 1980-01-01, the earliest a DOS timestamp can say.
def const DOS_TIME as int init 0;
def const DOS_DATE as int init 33;

# One file on its way into the archive.
def struct File {
    name as string,
    data as bytes
};

# A refusal, rather than an exit: `run` turns it into a status and a message on
# stderr, and a test can catch it. `exit` inside a module would take the test
# runner with it.
func fail(message as string) {
    throw Error{kind: "plugin", message: $message, file: "", line: 0, col: 0};
}

func bytesOf(text as string) {
    return convert.bytesFromString($text, "utf-8");
}

# --- the archive -----------------------------------------------------

# Little-endian, the order every field in a zip is written in.
func le16(n as int) {
    def out as bytes;
    $out[] = $n & 0xff;
    $out[] = ($n >> 8) & 0xff;
    return $out;
}

func le32(n as int) {
    def out as bytes;
    $out[] = $n & 0xff;
    $out[] = ($n >> 8) & 0xff;
    $out[] = ($n >> 16) & 0xff;
    $out[] = ($n >> 24) & 0xff;
    return $out;
}

# `crc.compute` hands back the checksum big-endian; a zip field wants the number.
func crcOf(data as bytes) {
    def sum as bytes init crc.compute($data, "crc32");
    return ($sum[0] << 24) + ($sum[1] << 16) + ($sum[2] << 8) + $sum[3];
}

# The local header that precedes each entry. Version 20, no flags, method 0 -
# stored. Deflate is optional in a zip and an EPUB reader does not care, and
# storing is what lets `mimetype` obey the one rule the format has about it.
func localHeader(f as File, sum as int) {
    def name as bytes init bytesOf($f.name);
    return binary.join([
        le32(0x04034b50),
        le16(20),
        le16(0),
        le16(0),
        le16(DOS_TIME),
        le16(DOS_DATE),
        le32($sum),
        le32(len($f.data)),
        le32(len($f.data)),
        le16(len($name)),
        le16(0),
        $name
    ]);
}

func centralHeader(f as File, sum as int, offset as int) {
    def name as bytes init bytesOf($f.name);
    return binary.join([
        le32(0x02014b50),
        le16(20),
        le16(20),
        le16(0),
        le16(0),
        le16(DOS_TIME),
        le16(DOS_DATE),
        le32($sum),
        le32(len($f.data)),
        le32(len($f.data)),
        le16(len($name)),
        le16(0),
        le16(0),
        le16(0),
        le16(0),
        le32(0),
        le32($offset),
        $name
    ]);
}

# zipOf lays the files out: every entry, then the central directory, then the
# end record. The order of `files` is the order of the archive, and `mimetype`
# being first is the caller's business.
func zipOf(files as list of File) {
    def body as list of bytes;
    def central as list of bytes;
    def offset as int init 0;
    for (def f in $files) {
        def sum as int init crcOf($f.data);
        def header as bytes init localHeader($f, $sum);
        $body[] = $header;
        $body[] = $f.data;
        $central[] = centralHeader($f, $sum, $offset);
        $offset = $offset + len($header) + len($f.data);
    }
    def directory as bytes init binary.join($central);
    def end as bytes init binary.join([
        le32(0x06054b50),
        le16(0),
        le16(0),
        le16(len($files)),
        le16(len($files)),
        le32(len($directory)),
        le32($offset),
        le16(0)
    ]);
    $body[] = $directory;
    $body[] = $end;
    return binary.join($body);
}

# --- XHTML -----------------------------------------------------------

# Every document in the archive opens with this, and neither `xml.encode` nor the
# Markdown renderer is responsible for it.
def const DECLARATION as string init '<?xml version="1.0" encoding="utf-8"?>' + "\n";
def const XHTML_NS as string init "http://www.w3.org/1999/xhtml";
def const OPS_NS as string init "http://www.idpf.org/2007/ops";
def const DC_NS as string init "http://purl.org/dc/elements/1.1/";
def const OPF_NS as string init "http://www.idpf.org/2007/opf";

# A package document, a container: XML that nothing reads as prose, so it is
# indented. Cheap, and it makes the file worth opening when something is wrong.
func xmlDocument(root as xml.Value) {
    return DECLARATION + xml.encodePretty($root) + "\n";
}

# A content document: XHTML, and **not** indented. Whitespace between elements
# is text, so a pretty-printer would put spaces inside a `<pre>` and line breaks
# between a word and the emphasis after it, and a reader would show both.
func xhtmlDocument(root as xml.Value) {
    return DECLARATION + "<!DOCTYPE html>\n" + xml.encode($root) + "\n";
}

# The rendered chapter, back as nodes.
#
# Parsing it is what guarantees the archive holds well-formed XML. An EPUB reader
# refuses a content document that is not, and what it shows a reader then is not
# a message any build could have explained - so the failure belongs here, where
# the chapter that caused it can be named.
func bodyOf(body as string) {
    try {
        return xml.decode("<body>" + $body + "</body>");
    } catch (e) {
        fail("a chapter did not render as XML: " + $e.message);
    }
    return xml.element("body");
}

# The XHTML wrapper every chapter and the navigation document share.
func document(lang as string, title as string, body as string) {
    def head as xml.Value init xml.element("head");
    $head = xml.append($head, xml.setAttr(xml.element("meta"), "charset", "utf-8"));
    $head = xml.append($head, xml.setText(xml.element("title"), $title));
    def link as xml.Value init xml.setAttr(xml.element("link"), "rel", "stylesheet");
    $link = xml.setAttr($link, "type", "text/css");
    $link = xml.setAttr($link, "href", "style.css");
    $head = xml.append($head, $link);
    def page as xml.Value init xml.setAttr(xml.element("html"), "xmlns", XHTML_NS);
    $page = xml.setAttr($page, "xmlns:epub", OPS_NS);
    $page = xml.setAttr($page, "xml:lang", $lang);
    $page = xml.append($page, $head);
    $page = xml.append($page, bodyOf($body));
    return xhtmlDocument($page);
}

# --- names -----------------------------------------------------------

# A chapter's file inside the archive: its source path, flattened, so that
# `guide/syntax.md` and `syntax.md` cannot collide and neither needs a directory.
func fileFor(src as string) {
    def flat as string init strings.replace($src, "/", "-");
    if (strings.endsWith($flat, ".md")) {
        $flat = strings.substring($flat, 0, len($flat) - 3);
    }
    def out as string;
    for (def ch in strings.chars(strings.lower($flat))) {
        if (regex.matches("^[a-z0-9._-]$", $ch)) {
            $out = $out + $ch;
        } else {
            $out = $out + "-";
        }
    }
    return $out + ".xhtml";
}

def const MEDIA as map of string to string init {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".svg": "image/svg+xml",
    ".webp": "image/webp"
};

# `strings` has no `lastIndexOf`, so the extension comes off the split.
func mediaOf(name as string) {
    def parts as list of string init strings.split(strings.lower($name), ".");
    if (len($parts) < 2) {
        return "";
    }
    def ext as string init "." + $parts[len($parts) - 1];
    if (not maps.has(MEDIA, $ext)) {
        return "";
    }
    return MEDIA[$ext];
}

# --- rewriting a chapter ---------------------------------------------

# Rewriting happens on the rendered text rather than on the parsed tree, which
# looks like the wrong way round now that the document is parsed anyway. It is
# not: `xml.children` hands back element children only, so a rebuilt tree would
# lose the prose between them - "before <a>link</a> after" comes back as two
# words and a link. The parse validates; the text is what carries the order.
#
# A link to another chapter points at a `.md` file, relative to the chapter it
# was written in. Inside the archive every chapter is a flat `.xhtml`, so the
# target is resolved, looked up, and replaced. Anything that does not resolve to
# a chapter of this book - an external URL, a file that is not in the outline -
# is left exactly as written.
func relinked(html as string, src as string, chapters as list of string) {
    def out as string init $html;
    def dir as string init path.dir($src);
    for (def m in regex.findAll('href="([^"#]+\.md)(#[^"]*)?"', $html)) {
        def target as string init path.clean(path.join($dir, $m.groups[0]));
        if (not lists.contains($chapters, $target)) {
            continue;
        }
        $out = strings.replace($out, $m.text, 'href="' + fileFor($target) + $m.groups[1] + '"');
    }
    return $out;
}

# One picture the book draws, on its way into the archive.
def struct Picture {
    src as string,
    name as string
};

# Images are copied in and their references rewritten, or the reader is handed a
# book with holes in it. A picture that is not under the source directory, or
# whose type has no media type here, is left alone: the reference then points
# outside the archive, which is the author's own link and not this program's to
# break.
func pictures(html as string, root as string, src as string) {
    def out as list of Picture;
    def dir as string init path.dir($src);
    for (def m in regex.findAll('<img[^>]+src="([^"]+)"', $html)) {
        def wanted as string init $m.groups[0];
        if (strings.contains($wanted, "://") or strings.startsWith($wanted, "/")) {
            continue;
        }
        def target as string init path.clean(path.join($dir, $wanted));
        if (mediaOf($target) == "" or not fs.isFile(path.join($root, $target))) {
            continue;
        }
        $out[] = Picture{src: $target, name: pictureName($target)};
    }
    return $out;
}

# The archive name for a picture: flattened like a chapter, keeping its
# extension so the media type and the file agree.
func pictureName(src as string) {
    def flat as string init strings.replace($src, "/", "-");
    def out as string;
    for (def ch in strings.chars(strings.lower($flat))) {
        if (regex.matches("^[a-z0-9._-]$", $ch)) {
            $out = $out + $ch;
        } else {
            $out = $out + "-";
        }
    }
    return $out;
}

func repictured(html as string, root as string, src as string) {
    def out as string init $html;
    def dir as string init path.dir($src);
    for (def m in regex.findAll('src="([^"]+)"', $html)) {
        def wanted as string init $m.groups[0];
        if (strings.contains($wanted, "://") or strings.startsWith($wanted, "/")) {
            continue;
        }
        def target as string init path.clean(path.join($dir, $wanted));
        if (mediaOf($target) == "" or not fs.isFile(path.join($root, $target))) {
            continue;
        }
        $out = strings.replace($out, $m.text, 'src="' + pictureName($target) + '"');
    }
    return $out;
}

# --- the package -----------------------------------------------------

def const OCF_NS as string init "urn:oasis:names:tc:opendocument:xmlns:container";

# The one file whose path is fixed by the format: it says where the package
# document is, and nothing else. Built rather than written out for the same
# reason as the rest - one way of producing XML in this file, not two.
func containerXml() {
    def root as xml.Value init xml.setAttr(
        xml.element("rootfile"),
        "full-path",
        "OEBPS/content.opf");
    $root = xml.setAttr($root, "media-type", "application/oebps-package+xml");
    def out as xml.Value init xml.setAttr(xml.element("container"), "version", "1.0");
    $out = xml.setAttr($out, "xmlns", OCF_NS);
    return xmlDocument(xml.append($out, xml.append(xml.element("rootfiles"), $root)));
}

# A reading stylesheet, deliberately small: an EPUB reader sets the type and the
# margins, and a book that fights it reads worse on every device it did not test.
def const CSS as string init 'body { margin: 0 1em; line-height: 1.5; }
h1, h2, h3, h4 { line-height: 1.25; }
pre { white-space: pre-wrap; word-wrap: break-word; background: #f4f4f4; padding: 0.6em; }
code { font-family: monospace; }
blockquote { margin: 1em 0 1em 1em; padding-left: 0.8em; border-left: 3px solid #ccc; }
table { border-collapse: collapse; }
th, td { border: 1px solid #ccc; padding: 0.3em 0.5em; }
img { max-width: 100%; }
';

# The publication identifier. EPUB wants one that is stable across builds of the
# same book, which rules out a fresh UUID: the digest of the title and language
# gives the same answer every time and a different one for a different book.
func identifier(title as string, lang as string) {
    def digest as string init encoding.toText(
        hash.compute(bytesOf($title + "/" + $lang), "sha256"),
        "hex");
    return "urn:uuid:" + strings.substring($digest, 0, 8) + "-" +
        strings.substring($digest, 8, 12) + "-5" + strings.substring($digest, 13, 16) + "-a" +
        strings.substring($digest, 17, 20) + "-" + strings.substring($digest, 20, 32);
}

# One `<item>` of the manifest: what is in the archive, and what it is.
func manifestItem(id as string, href as string, media as string, properties as string) {
    def item as xml.Value init xml.setAttr(xml.element("item"), "id", $id);
    $item = xml.setAttr($item, "href", $href);
    $item = xml.setAttr($item, "media-type", $media);
    if ($properties != "") {
        $item = xml.setAttr($item, "properties", $properties);
    }
    return $item;
}

# One Dublin Core element: `<dc:title>`, `<dc:creator>`, and the rest of what a
# book says about itself.
func dc(name as string, text as string) {
    return xml.setText(xml.element("dc:" + $name), $text);
}

# What the book is: the metadata the format requires, and the two it asks for.
func metadataNode(
    title as string,
    lang as string,
    description as string,
    authors as list of string,
    cover as string) {
    def out as xml.Value init xml.setAttr(xml.element("metadata"), "xmlns:dc", DC_NS);
    def id as xml.Value init xml.setText(xml.element("dc:identifier"), identifier($title, $lang));
    $out = xml.append($out, xml.setAttr($id, "id", "pub-id"));
    $out = xml.append($out, dc("title", $title));
    $out = xml.append($out, dc("language", $lang));
    if ($description != "") {
        $out = xml.append($out, dc("description", $description));
    }
    for (def name in $authors) {
        $out = xml.append($out, dc("creator", $name));
    }
    # Required, and fixed rather than "now": a book that rebuilds to different
    # bytes because a second passed is not reproducible.
    def modified as xml.Value init xml.setAttr(xml.element("meta"), "property", "dcterms:modified");
    $out = xml.append($out, xml.setText($modified, "2026-01-01T00:00:00Z"));
    if ($cover != "") {
        def mark as xml.Value init xml.setAttr(xml.element("meta"), "name", "cover");
        $out = xml.append($out, xml.setAttr($mark, "content", "cover-image"));
    }
    return $out;
}

# The package document: what the book is, what is in it, and in what order it is
# read.
#
# Built as a tree rather than assembled as text, so the escaping is the `xml`
# library's and a title with an ampersand in it cannot produce a file no reader
# will open.
func contentOpf(
    title as string,
    lang as string,
    description as string,
    authors as list of string,
    chapters as list of File,
    images as list of File,
    cover as string) {
    def manifest as xml.Value init xml.element("manifest");
    $manifest = xml.append(
        $manifest,
        manifestItem("nav", "nav.xhtml", "application/xhtml+xml", "nav"));
    $manifest = xml.append($manifest, manifestItem("style", "style.css", "text/css", ""));
    def spine as xml.Value init xml.element("spine");
    def n as int init 0;
    for (def f in $chapters) {
        def id as string init "ch" + convert.toString($n);
        $manifest = xml.append($manifest, manifestItem($id, $f.name, "application/xhtml+xml", ""));
        $spine = xml.append($spine, xml.setAttr(xml.element("itemref"), "idref", $id));
        $n = $n + 1;
    }
    def i as int init 0;
    for (def f in $images) {
        def properties as string init "";
        def id as string init "img" + convert.toString($i);
        if ($f.name == $cover) {
            $properties = "cover-image";
            $id = "cover-image";
        }
        $manifest = xml.append(
            $manifest,
            manifestItem($id, $f.name, mediaOf($f.name), $properties));
        $i = $i + 1;
    }
    def package as xml.Value init xml.setAttr(xml.element("package"), "xmlns", OPF_NS);
    $package = xml.setAttr($package, "version", "3.0");
    $package = xml.setAttr($package, "unique-identifier", "pub-id");
    $package = xml.setAttr($package, "xml:lang", $lang);
    $package = xml.append($package, metadataNode($title, $lang, $description, $authors, $cover));
    $package = xml.append($package, $manifest);
    $package = xml.append($package, $spine);
    return xmlDocument($package);
}

# One chapter of the navigation document: a link, by the name the archive gives
# the file.
func navLink(entries as json.Value, at as string) {
    def link as xml.Value init xml.setAttr(
        xml.element("a"),
        "href",
        fileFor(json.asString($entries, $at + "/src")));
    $link = xml.setText($link, json.asString($entries, $at + "/title"));
    return xml.append(xml.element("li"), $link);
}

# A part, once its chapters are known: the label, and the list under it.
func navPart(title as string, chapters as list of xml.Value) {
    def out as xml.Value init xml.append(
        xml.element("li"),
        xml.setText(xml.element("span"), $title));
    def nested as xml.Value init xml.element("ol");
    for (def child in $chapters) {
        $nested = xml.append($nested, $child);
    }
    return xml.append($out, $nested);
}

# The navigation document, which is both the reader's table of contents and the
# one the format requires. A part heading is a label with its chapters nested
# under it; a separator ends the part, the same rule the outline itself follows.
func navXhtml(lang as string, title as string, entries as json.Value) {
    def rows as list of xml.Value;
    def nested as list of xml.Value;
    def empty as list of xml.Value;
    def part as string init "";
    def open as bool init false;
    for (def i in 0..json.length($entries)) {
        def at as string init "/" + convert.toString($i);
        def kind as string init json.asString($entries, $at + "/kind");
        if ($kind == "part" or $kind == "separator") {
            if ($open) {
                $rows[] = navPart($part, $nested);
                $nested = $empty;
            }
            $open = $kind == "part";
            $part = "";
            if ($open) {
                $part = json.asString($entries, $at + "/title");
            }
            continue;
        }
        if ($kind != "page") {
            continue;
        }
        if ($open) {
            $nested[] = navLink($entries, $at);
            continue;
        }
        $rows[] = navLink($entries, $at);
    }
    if ($open) {
        $rows[] = navPart($part, $nested);
    }
    def toc as xml.Value init xml.element("ol");
    for (def row in $rows) {
        $toc = xml.append($toc, $row);
    }
    def nav as xml.Value init xml.setAttr(xml.element("nav"), "epub:type", "toc");
    $nav = xml.setAttr($nav, "id", "toc");
    $nav = xml.append($nav, xml.setText(xml.element("h1"), $title));
    $nav = xml.append($nav, $toc);
    return document($lang, $title, xml.encode($nav));
}

# --- building the book -----------------------------------------------

# One chapter, rendered: links to other chapters point at the files this archive
# will hold, and pictures are carried in.
#
# `markdown.toXhtml` rather than `toHtml`: the same renderer, writing the well-
# formed XML an EPUB content document has to be - void elements self-closed,
# boolean attributes expanded. It replaced a regular expression here that closed
# `<br>`, `<hr>` and `<img>` and knew about nothing else.
#
# Raw HTML in a chapter is escaped rather than passed through, which is the
# renderer's default and the right one here: a book's hand-written `<div>` need
# only be valid HTML5 to reach the site, and an EPUB reader refuses a content
# document that is not valid XML.
func chapterFile(
    req as json.Value,
    at as string,
    root as string,
    sources as list of string,
    titles as map of string to string) {
    def src as string init json.asString($req, $at + "/src");
    def body as string init markdown.toXhtml(json.asString($req, $at + "/content"));
    $body = repictured(relinked($body, $src, $sources), $root, $src);
    def heading as string init $src;
    if (maps.has($titles, $src)) {
        $heading = $titles[$src];
    }
    return File{
        name: fileFor($src),
        data: bytesOf(document(json.asString($req, "/book/language"), $heading, $body))
    };
}

# The titles the outline gives each chapter, which is where a book names them.
func titlesOf(req as json.Value) {
    def out as map of string to string;
    for (def i in 0..json.length($req, "/entries")) {
        def at as string init "/entries/" + convert.toString($i);
        if (json.asString($req, $at + "/kind") == "page") {
            $out[json.asString($req, $at + "/src")] = json.asString($req, $at + "/title");
        }
    }
    return $out;
}

/**
 * The EPUB for one book, as bytes.
 *
 * Everything comes from the request: the chapters as the preprocessors left
 * them, the outline for the navigation and the spine, the settings for the
 * cover and the stylesheet. Nothing is read from the clock, so the same book
 * gives the same bytes.
 * @param req {json.Value} the decoded request
 * @return {bytes} the archive
 * @throws {Error} kind "plugin" when a configured cover or stylesheet is missing
 */
export func epubFor(req as json.Value) {
    def root as string init json.asString($req, "/book/src");
    def lang as string init json.asString($req, "/book/language");
    def css as string init CSS;
    if (json.has($req, "/plugin/settings/stylesheet")) {
        def sheet as string init path.join(
            $root,
            json.asString($req, "/plugin/settings/stylesheet"));
        if (not fs.isFile($sheet)) {
            fail("stylesheet not found: " + $sheet);
        }
        $css = fs.readString($sheet);
    }
    def sources as list of string;
    for (def i in 0..json.length($req, "/chapters")) {
        $sources[] = json.asString($req, "/chapters/" + convert.toString($i) + "/src");
    }
    def titles as map of string to string init titlesOf($req);
    def chapters as list of File;
    def images as list of File;
    def seen as map of string to int;
    for (def i in 0..json.length($req, "/chapters")) {
        def at as string init "/chapters/" + convert.toString($i);
        def src as string init json.asString($req, $at + "/src");
        def body as string init markdown.toHtml(json.asString($req, $at + "/content"));
        for (def picture in pictures($body, $root, $src)) {
            if (maps.has($seen, $picture.name)) {
                continue;
            }
            $seen[$picture.name] = 1;
            $images[] = File{
                name: $picture.name,
                data: fs.readBytes(path.join($root, $picture.src))
            };
        }
        $chapters[] = chapterFile($req, $at, $root, $sources, $titles);
    }
    def coverName as string init "";
    if (json.has($req, "/plugin/settings/cover")) {
        def coverPath as string init json.asString($req, "/plugin/settings/cover");
        def coverFile as string init path.join($root, $coverPath);
        if (not fs.isFile($coverFile)) {
            fail("cover not found: " + $coverFile);
        }
        if (mediaOf($coverPath) == "") {
            fail("cover is not an image this can carry: " + $coverPath);
        }
        $coverName = pictureName($coverPath);
        if (not maps.has($seen, $coverName)) {
            $seen[$coverName] = 1;
            $images[] = File{name: $coverName, data: fs.readBytes($coverFile)};
        }
    }
    def authors as list of string;
    for (def i in 0..json.length($req, "/book/authors")) {
        $authors[] = json.asString($req, "/book/authors/" + convert.toString($i));
    }
    # `mimetype` first and stored, which is the one thing the container format
    # asks of the zip around it.
    def files as list of File init [File{name: "mimetype", data: bytesOf(MIMETYPE)}];
    $files[] = File{name: "META-INF/container.xml", data: bytesOf(containerXml())};
    $files[] = File{
        name: "OEBPS/content.opf",
        data: bytesOf(contentOpf(
            json.asString($req, "/book/title"),
            $lang,
            json.asString($req, "/book/description"),
            $authors,
            $chapters,
            $images,
            $coverName))
    };
    $files[] = File{
        name: "OEBPS/nav.xhtml",
        data: bytesOf(navXhtml(
            $lang,
            json.asString($req, "/book/title"),
            json.get($req, "/entries")))
    };
    $files[] = File{name: "OEBPS/style.css", data: bytesOf($css)};
    for (def f in $chapters) {
        $files[] = File{name: "OEBPS/" + $f.name, data: $f.data};
    }
    for (def f in $images) {
        $files[] = File{name: "OEBPS/" + $f.name, data: $f.data};
    }
    return zipOf($files);
}

/**
 * Run the plugin over one request: build the book and write it where the
 * settings say.
 * @param request {string} the JSON request from stdin
 * @return {int} the exit status
 */
export func run(request as string) {
    try {
        if (strings.trim($request) == "") {
            fail("no request on stdin");
        }
        def req as json.Value init json.decode($request);
        if (json.asInt($req, "/api") != API) {
            fail("this plugin speaks api " + convert.toString(API) +
                ", the request speaks " + convert.toString(json.asInt($req, "/api")));
        }
        if (json.asString($req, "/kind") != "renderer") {
            fail("this is a renderer; the request asks for a " +
                json.asString($req, "/kind"));
        }
        def output as string init "book.epub";
        if (json.has($req, "/plugin/settings/output")) {
            $output = json.asString($req, "/plugin/settings/output");
        }
        def epubPath as string init path.join(json.asString($req, "/book/out"), $output);
        def epubDir as string init path.dir($epubPath);
        if ($epubDir != "" and $epubDir != ".") {
            fs.mkdirAll($epubDir);
        }
        fs.writeBytes($epubPath, epubFor($req));
        io.printf('{"api":%d,"written":[%s]}', API, json.encode($output));
        return 0;
    } catch (e) {
        io.eprintf("grimoire-epub: %s\n", $e.message);
        return 1;
    }
}
