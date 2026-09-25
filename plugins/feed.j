# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0
# pragma-jennifer-capability: exec

/**
 * An RSS feed of what changed in the book, from its git history.
 *
 * A renderer. One item per chapter, dated by the last commit that touched it and
 * titled by that commit's subject, newest first - so a reader can follow a
 * manual the way they follow a changelog, and a reader who only cares about one
 * chapter can see when it last moved.
 *
 * The dates come from git rather than from the filesystem. A fresh checkout
 * stamps every file with the moment it was cloned, which would publish a feed
 * claiming the whole book changed today.
 *
 * Git is asked for its own formatting - `--date=rfc2822` is exactly what RSS
 * wants - so no date is parsed or rebuilt here. Nothing in the feed is "now":
 * `lastBuildDate` is the newest item's date, so two builds of an unchanged book
 * are the same file.
 *
 * A book that is not in a checkout gets no feed and a warning. Publishing one
 * with invented dates would be worse than publishing none.
 * @module feed
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use os;
use fs;
use path;
use json;
use xml;
use strings;
use convert;
use lists;

def const API as int init 1;

# Wide enough for a unix timestamp past the year 2286, so every sort key is the
# same length and a text sort is a numeric one.
def const KEY_WIDTH as int init 12;
def const FAR_FUTURE as int init 999999999999;

# One chapter in the feed.
def struct Item {
    key as string,
    title as string,
    href as string,
    date as string,
    subject as string
};

# A refusal, rather than an exit: `run` turns it into a status and a message on
# stderr, and a test can catch it. `exit` inside a module would take the test
# runner with it.
func fail(message as string) {
    throw Error{kind: "plugin", message: $message, file: "", line: 0, col: 0};
}

# Nothing to publish is not a failure. The reply carries a warning instead, which
# reaches the build's own warnings where a reader is already looking.
func nothing(message as string) {
    return '{"api":' + convert.toString(API) + ',"warnings":[' + json.encode($message) + ']}';
}

func join(base as string, page as string) {
    if (strings.endsWith($base, "/")) {
        return $base + $page;
    }
    return $base + "/" + $page;
}

# Newest first, and a tie broken by path so two chapters committed in the same
# second keep a fixed order. The key is the distance from a far future date,
# zero-padded, which turns "sort descending by time" into an ordinary ascending
# text sort.
func sortKey(stamp as int, src as string) {
    def digits as string init convert.toString(FAR_FUTURE - $stamp);
    while (len($digits) < KEY_WIDTH) {
        $digits = "0" + $digits;
    }
    return $digits + "|" + $src;
}

# `git -C dir log -1` over one path. The three fields are asked for in one go and
# split on a character a commit subject cannot contain.
func lastCommit(dir as string, file as string) {
    def result as os.Result;
    try {
        $result = os.run([
            "git",
            "-C",
            $dir,
            "log",
            "-1",
            "--date=rfc2822",
            "--format=%at|%ad|%s",
            "--",
            $file
        ]);
    } catch (e) {
        return "";
    }
    if ($result.exitCode != 0) {
        return "";
    }
    return strings.trim($result.stdout);
}

# Whether this is a checkout at all. A tarball is a perfectly good way to build a
# book; it just has no history to publish.
func isCheckout(dir as string) {
    def result as os.Result;
    try {
        $result = os.run(["git", "-C", $dir, "rev-parse", "--is-inside-work-tree"]);
    } catch (e) {
        return false;
    }
    return $result.exitCode == 0 and strings.trim($result.stdout) == "true";
}

# --- building the feed -----------------------------------------------

/**
 * The feed for one book, as XML - or a reply carrying a warning when there is
 * nothing to publish.
 *
 * Everything it needs comes from the request and from git. Nothing is read from
 * the clock: `lastBuildDate` is the newest item's own date, so an unchanged book
 * rebuilds to the same bytes.
 * @param req {json.Value} the decoded request
 * @return {string} the feed XML, or "" when the reply should be a warning
 * @throws {Error} kind "plugin" when the request is not one this can answer
 */
export func feedFor(req as json.Value) {
    def base as string init "";
    if (json.has($req, "/plugin/settings/baseUrl")) {
        $base = json.asString($req, "/plugin/settings/baseUrl");
    }
    if ($base == "") {
        return "";
    }
    def root as string init json.asString($req, "/book/src");
    if (not isCheckout($root)) {
        return "";
    }
    def limit as int init 20;
    if (json.has($req, "/plugin/settings/limit")) {
        $limit = json.asInt($req, "/plugin/settings/limit");
    }
    def output as string init "feed.xml";
    if (json.has($req, "/plugin/settings/output")) {
        $output = json.asString($req, "/plugin/settings/output");
    }
    def items as list of Item;
    def keys as list of string;
    def byKey as map of string to int;
    for (def i in 0..json.length($req, "/entries")) {
        def at as string init "/entries/" + convert.toString($i);
        if (json.asString($req, $at + "/kind") != "page") {
            continue;
        }
        def src as string init json.asString($req, $at + "/src");
        def item as Item init itemFor(
            $root,
            $src,
            json.asString($req, $at + "/title"),
            $base,
            json.asString($req, $at + "/out"));
        if ($item.key == "") {
            continue;
        }
        $byKey[$item.key] = len($items);
        $keys[] = $item.key;
        $items[] = $item;
    }
    if (len($items) == 0) {
        return "";
    }
    return channel($req, $base, $output, ordered($items, $keys, $byKey, $limit));
}

# One chapter, or an Item with an empty key when git knows nothing about it - new
# or untracked. It joins the feed the first time it is committed.
func itemFor(root as string, src as string, title as string, base as string, out as string) {
    def empty as Item init Item{key: "", title: "", href: "", date: "", subject: ""};
    def line as string init lastCommit($root, $src);
    if ($line == "") {
        return $empty;
    }
    def parts as list of string init strings.split($line, "|");
    if (len($parts) < 3) {
        return $empty;
    }
    # A commit subject may contain the separator; only the first two fields are
    # split off.
    def subject as string init strings.join(lists.tail($parts, len($parts) - 2), "|");
    return Item{
        key: sortKey(convert.toInt($parts[0]), $src),
        title: $title,
        href: join($base, $out),
        date: $parts[1],
        subject: $subject
    };
}

# The items, newest first, no more than `limit` of them.
func ordered(
    items as list of Item,
    keys as list of string,
    byKey as map of string to int,
    limit as int) {
    def out as list of Item;
    def n as int init 0;
    for (def key in lists.sort($keys)) {
        if ($n >= $limit) {
            break;
        }
        $out[] = $items[$byKey[$key]];
        $n = $n + 1;
    }
    return $out;
}

# One `<item>`: a chapter, as a reader's feed shows it.
func itemNode(item as Item) {
    def out as xml.Value init xml.element("item");
    $out = xml.append($out, xml.setText(xml.element("title"), $item.title));
    $out = xml.append($out, xml.setText(xml.element("link"), $item.href));
    def guid as xml.Value init xml.setAttr(xml.element("guid"), "isPermaLink", "true");
    $out = xml.append($out, xml.setText($guid, $item.href));
    $out = xml.append($out, xml.setText(xml.element("pubDate"), $item.date));
    return xml.append($out, xml.setText(xml.element("description"), $item.subject));
}

# The channel around them.
#
# Built as a tree and encoded rather than assembled as text: a chapter title is
# somebody's prose, and one ampersand in it against a hand-written `<title>` is
# a feed no reader will parse. `xml.setText` escapes because it has to.
#
# `lastBuildDate` is the newest item's date - taken from the item rather than
# read back out of the markup - because a feed that changed on every build would
# be a plugin breaking the determinism the contract asks of it.
func channel(req as json.Value, base as string, output as string, items as list of Item) {
    def channel as xml.Value init xml.element("channel");
    $channel = xml.append(
        $channel,
        xml.setText(xml.element("title"), json.asString($req, "/book/title")));
    $channel = xml.append($channel, xml.setText(xml.element("link"), $base));
    $channel = xml.append(
        $channel,
        xml.setText(xml.element("description"), json.asString($req, "/book/description")));
    $channel = xml.append(
        $channel,
        xml.setText(xml.element("language"), json.asString($req, "/book/language")));
    if (len($items) > 0) {
        $channel = xml.append($channel, xml.setText(xml.element("lastBuildDate"), $items[0].date));
    }
    def self as xml.Value init xml.setAttr(xml.element("atom:link"), "href", join($base, $output));
    $self = xml.setAttr($self, "rel", "self");
    $self = xml.setAttr($self, "type", "application/rss+xml");
    $channel = xml.append($channel, $self);
    for (def item in $items) {
        $channel = xml.append($channel, itemNode($item));
    }
    def rss as xml.Value init xml.setAttr(xml.element("rss"), "version", "2.0");
    $rss = xml.setAttr($rss, "xmlns:atom", "http://www.w3.org/2005/Atom");
    return '<?xml version="1.0" encoding="utf-8"?>' + "\n" +
        xml.encodePretty(xml.append($rss, $channel)) + "\n";
}

/**
 * Run the plugin over one request: build the feed, write it, report what it
 * wrote - or write nothing and say why.
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
        def feed as string init feedFor($req);
        if ($feed == "") {
            io.printf("%s", nothing(whyNot($req)));
            return 0;
        }
        def output as string init "feed.xml";
        if (json.has($req, "/plugin/settings/output")) {
            $output = json.asString($req, "/plugin/settings/output");
        }
        def target as string init path.join(json.asString($req, "/book/out"), $output);
        def dir as string init path.dir($target);
        if ($dir != "" and $dir != ".") {
            fs.mkdirAll($dir);
        }
        fs.writeString($target, $feed);
        io.printf('{"api":%d,"written":[%s]}', API, json.encode($output));
        return 0;
    } catch (e) {
        io.eprintf("grimoire-feed: %s\n", $e.message);
        return 1;
    }
}

# Why there is no feed, in the words the build will print.
func whyNot(req as json.Value) {
    if (not json.has($req, "/plugin/settings/baseUrl") or
        json.asString($req, "/plugin/settings/baseUrl") == "") {
        return "no baseUrl configured, nothing written";
    }
    def root as string init json.asString($req, "/book/src");
    if (not isCheckout($root)) {
        return "no git checkout at " + $root + ", nothing written";
    }
    return "no chapter has a commit behind it, nothing written";
}
