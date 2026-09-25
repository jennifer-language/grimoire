# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * `sitemap.xml` for Grimoire: a renderer that lists every page of a built book.
 *
 * A sitemap is a list of URLs and the outline is a list of pages, so the whole
 * plugin is one loop. It exists as the reference renderer: where
 * `grimoire-include` shows a program rewriting the book before it is built, this
 * one shows a program making something out of the book after it is.
 *
 * The book does not know where it is published, so the base URL has to be
 * configured:
 *
 *     [renderer.sitemap]
 *     baseUrl = "https://example.com/manual/"
 *
 * Without one it writes nothing and says so, because a sitemap of relative paths
 * is not a sitemap. A `robots.txt` pointing at it is written too unless the
 * output directory already has one, since a hand-written robots file is the
 * author's and not this program's to replace.
 *
 * The XML is built as a tree and encoded by the `xml` library rather than
 * assembled as text. A URL can hold an ampersand, and one unescaped is a
 * document no crawler will read.
 * @module sitemap
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use fs;
use path;
use json;
use xml;
use strings;
use convert;

def const API as int init 1;

# The namespace a sitemap has to declare to be one.
def const SITEMAP_NS as string init "http://www.sitemaps.org/schemas/sitemap/0.9";

# A refusal, rather than an exit: `run` turns it into a status and a message on
# stderr, and a test can catch it. `exit` inside a module would take the test
# runner with it.
func fail(message as string) {
    throw Error{kind: "plugin", message: $message, file: "", line: 0, col: 0};
}

/**
 * The base and a page path, with exactly one slash between them.
 * @param base {string} the configured base URL
 * @param page {string} the page's path inside the site
 * @return {string} the absolute URL
 */
export func join(base as string, page as string) {
    if (strings.endsWith($base, "/")) {
        return $base + $page;
    }
    return $base + "/" + $page;
}

/**
 * Every page of the outline, as absolute URLs, in outline order.
 *
 * Parts and separators are not pages and carry no `out` path; a page whose path
 * is empty is one the build did not write.
 * @param req {json.Value} the decoded request
 * @param base {string} the configured base URL
 * @return {list of string} the URLs to list
 */
export func urls(req as json.Value, base as string) {
    def out as list of string;
    for (def i in 0..json.length($req, "/entries")) {
        def at as string init "/entries/" + convert.toString($i);
        if (json.asString($req, $at + "/kind") != "page") {
            continue;
        }
        def page as string init json.asString($req, $at + "/out");
        if ($page == "") {
            continue;
        }
        $out[] = join($base, $page);
    }
    return $out;
}

/**
 * The sitemap document for a list of URLs.
 * @param urls {list of string} the absolute URLs, in order
 * @return {string} the `sitemap.xml` document
 */
export func document(urls as list of string) {
    def root as xml.Value init xml.setAttr(xml.element("urlset"), "xmlns", SITEMAP_NS);
    for (def href in $urls) {
        def entry as xml.Value init xml.append(
            xml.element("url"),
            xml.setText(xml.element("loc"), $href));
        $root = xml.append($root, $entry);
    }
    return '<?xml version="1.0" encoding="utf-8"?>' + "\n" + xml.encodePretty($root) + "\n";
}

/**
 * The `robots.txt` that points a crawler at the sitemap.
 * @param base {string} the configured base URL
 * @return {string} the file
 */
export func robotsTxt(base as string) {
    return "User-agent: *\nAllow: /\nSitemap: " + join($base, "sitemap.xml") + "\n";
}

# The reply, as the contract spells it: what was written, and nothing else.
func reply(written as list of string) {
    def quoted as list of string;
    for (def name in $written) {
        $quoted[] = json.encode($name);
    }
    return '{"api":' + convert.toString(API) + ',"written":[' +
        strings.join($quoted, ",") + ']}';
}

/**
 * Write the sitemap, and the robots file when there is none.
 * @param req {json.Value} the decoded request
 * @param base {string} the configured base URL
 * @return {list of string} what was written, in the order it was written
 */
export func write(req as json.Value, base as string) {
    def site as string init json.asString($req, "/book/out");
    fs.writeString(path.join($site, "sitemap.xml"), document(urls($req, $base)));
    def out as list of string init ["sitemap.xml"];
    # A hand-written robots file is the author's, and a crawler reads the first
    # one it is given: replacing it would be this plugin overruling a decision it
    # knows nothing about.
    def robots as string init path.join($site, "robots.txt");
    if (not fs.exists($robots)) {
        fs.writeString($robots, robotsTxt($base));
        $out[] = "robots.txt";
    }
    return $out;
}

/**
 * Run the plugin over one request.
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
        def base as string init "";
        if (json.has($req, "/plugin/settings/baseUrl")) {
            $base = json.asString($req, "/plugin/settings/baseUrl");
        }
        if ($base == "") {
            io.printf('{"api":%d,"warnings":["no baseUrl configured, nothing written"]}', API);
            return 0;
        }
        io.printf("%s", reply(write($req, $base)));
        return 0;
    } catch (e) {
        io.eprintf("grimoire-sitemap: %s\n", $e.message);
        return 1;
    }
}
