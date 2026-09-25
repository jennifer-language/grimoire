# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0
# pragma-jennifer-capability: net

/**
 * Fails the build on a dead link.
 *
 * A renderer. A build reports a chapter whose file is missing, but nothing
 * reports a cross-reference inside one that goes nowhere - the page is written,
 * it looks right, and the link is dead until a reader finds it. This walks the
 * built site, resolves every relative `href` and `src`, checks the fragments
 * too, and exits non-zero with the whole list.
 *
 * Every finding is reported, not only the first. A build that stops at one dead
 * link is a build run once per dead link.
 *
 * **Code spans are cut out before anything is read.** A page that documents an
 * `href` puts the literal string in its own output, and a checker cannot tell
 * that from a link a reader can click. This is the one thing that makes the
 * difference between a useful check and one nobody keeps enabled.
 *
 * External links are checked only when asked. That is the part that needs the
 * network, which a Grimoire build otherwise never touches.
 * @module linkcheck
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
use regex;

import "http.j" as http;

def const API as int init 1;

# `href` and `src` both point at something that has to be there: a chapter, a
# stylesheet, a picture.
#
# Read with a regular expression rather than with `html.parse`, which was
# measured before it was ruled out: that parser walks the source a character at
# a time in Jennifer and takes **3.3 seconds** on one 42 KB page of this manual,
# against 2 ms for the scan below - a site of a hundred pages would take five
# minutes. And `html.findAll` follows a path of direct children rather than
# searching a subtree, so "every link anywhere on the page" is not a query it can
# express. Both would have to change before a tree is the better tool here.
def const LINKS as string init '(?:href|src)="([^"]*)"';

# A code span holds markup as text. Cutting the spans out first is what keeps a
# page about HTML from failing a check about HTML.
def const CODE as string init '<code[^>]*>[^<]*</code>';

# What a fragment can land on in a Grimoire page.
def const ANCHOR as string init 'id="';

# A refusal, rather than an exit: `run` turns it into a status and a message on
# stderr, and a test can catch it. `exit` inside a module would take the test
# runner with it.
func fail(message as string) {
    throw Error{kind: "plugin", message: $message, file: "", line: 0, col: 0};
}

# A scheme, a protocol-relative URL, or an anchor for something that is not a
# document: none of it resolves to a file in the site.
func isExternal(url as string) {
    return strings.contains($url, "://") or strings.startsWith($url, "//") or
        strings.startsWith($url, "mailto:") or strings.startsWith($url, "tel:") or
        strings.startsWith($url, "data:") or strings.startsWith($url, "javascript:");
}

# Every `.html` under the site, sorted, so the report reads the same twice.
func pagesUnder(root as string) {
    def out as list of string;
    for (def st in fs.walk($root)) {
        if ($st.isDir or not strings.endsWith($st.path, ".html")) {
            continue;
        }
        $out[] = $st.path;
    }
    return lists.sort($out);
}

# The part before the `#`, and the part after it.
func target(url as string) {
    def at as int init strings.indexOf($url, "#");
    if ($at < 0) {
        return $url;
    }
    return strings.substring($url, 0, $at);
}

func fragment(url as string) {
    def at as int init strings.indexOf($url, "#");
    if ($at < 0) {
        return "";
    }
    return strings.substring($url, $at + 1, len($url));
}

# --- the network, only when asked ------------------------------------

# One request per distinct URL, and a status rather than a body: a link check
# asks whether something is there, not what it says.
#
# HEAD is tried first and GET second, because a server refusing HEAD is common
# enough on static hosts and CDNs to be worth the round trip - and it refuses in
# both ways there are: a 403 or 405 status, and a connection dropped mid-answer.
# A URL is dead only when both have failed.
func reach(url as string) {
    def none as map of string to string;
    def status as int init 0;
    def note as string init "";
    try {
        $status = http.head($url, $none).status;
    } catch (e) {
        $note = $e.message;
    }
    if ($status >= 200 and $status < 400) {
        return "";
    }
    try {
        $status = http.get($url, $none).status;
    } catch (e) {
        if ($note == "") {
            $note = $e.message;
        }
        return $note;
    }
    if ($status >= 400) {
        return "HTTP " + convert.toString($status);
    }
    return "";
}

# --- checking a site -------------------------------------------------

# A code span holds markup as text, and a page that documents an `href` puts the
# literal string in its own output. Cutting the spans out first is what keeps a
# check about HTML from failing on a page about HTML.
func stripped(html as string) {
    def out as string init $html;
    for (def m in regex.findAll(CODE, $html)) {
        $out = strings.replace($out, $m.text, "");
    }
    return $out;
}

# An external URL is remembered once, and only when it is going to be checked.
func remember(seen as list of string, url as string, wanted as bool) {
    if (not $wanted or lists.contains($seen, $url)) {
        return $seen;
    }
    def out as list of string init $seen;
    $out[] = $url;
    return $out;
}

# Why one link is dead, or "" when it is not. `own` is the page's own markup, so
# a link to an anchor on the same page needs no second read.
func deadReason(page as string, dir as string, url as string, own as string) {
    def file as string init $page;
    if (target($url) != "") {
        $file = path.clean(path.join($dir, target($url)));
        if (not fs.isFile($file)) {
            return "no such file";
        }
    }
    if (fragment($url) == "") {
        return "";
    }
    def body as string init $own;
    if ($file != $page) {
        $body = fs.readString($file);
    }
    if (strings.contains($body, ANCHOR + fragment($url) + '"')) {
        return "";
    }
    return "no such anchor";
}

/**
 * Every dead link in a built site, page by page.
 *
 * A finding is one line: the page it was found in, the link as written, and why
 * it is dead. The list is complete rather than first-only - a build that stops
 * at one dead link is a build run once per dead link.
 * @param site {string} the directory the site was built into
 * @param external {bool} whether to check `http(s)` links over the network
 * @return {list of string} the findings, empty when every link resolves
 * @throws {Error} kind "plugin" when there is no site at that path
 */
export func check(site as string, external as bool) {
    if (not fs.isDir($site)) {
        fail("no site at " + $site);
    }
    def findings as list of string;
    def externals as list of string;
    for (def page in pagesUnder($site)) {
        def html as string init fs.readString($page);
        def dir as string init path.dir($page);
        for (def m in regex.findAll(LINKS, stripped($html))) {
            def url as string init $m.groups[0];
            if ($url == "") {
                continue;
            }
            if (isExternal($url)) {
                $externals = remember($externals, $url, $external);
                continue;
            }
            def why as string init deadReason($page, $dir, $url, $html);
            if ($why != "") {
                $findings[] = $page + ": " + $url + " -> " + $why;
            }
        }
    }
    for (def url in lists.sort($externals)) {
        def why as string init reach($url);
        if ($why != "") {
            $findings[] = $url + " -> " + $why;
        }
    }
    return $findings;
}

/**
 * Run the plugin over one request: read it, check the site it names, report.
 *
 * Findings go to stderr and the status is non-zero, which fails the build. A
 * clean site says nothing but its reply.
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
        def external as bool init false;
        if (json.has($req, "/plugin/settings/external")) {
            $external = json.asBool($req, "/plugin/settings/external");
        }
        def findings as list of string init check(json.asString($req, "/book/out"), $external);
        if (len($findings) == 0) {
            io.printf('{"api":%d}', API);
            return 0;
        }
        for (def finding in $findings) {
            io.eprintf("%s\n", $finding);
        }
        io.eprintf("grimoire-linkcheck: %d dead link(s)\n", len($findings));
        return 1;
    } catch (e) {
        io.eprintf("grimoire-linkcheck: %s\n", $e.message);
        return 1;
    }
}
