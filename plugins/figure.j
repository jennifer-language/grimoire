# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Captions for the pictures a book already has.
 *
 * A preprocessor. An image standing alone in a paragraph gets the caption its
 * Markdown already carries - the title in quotes, or the alt text - written
 * under it. An image inside a sentence is left alone: it is part of the prose,
 * not a figure.
 *
 *     ![A build, end to end](pipeline.png "How a book is built")
 *
 * By default the caption is written as **Markdown**, an emphasised line under
 * the picture, because that is the form that reaches every edition: the site,
 * the EPUB, and the printable book. `html = true` writes a `<figure>` with a
 * `<figcaption>` instead, which is better markup and **disappears from the
 * PDF** - the printable build draws pictures and text, and skips a block of
 * HTML it cannot read. A book with no printable edition should turn it on; one
 * with a PDF should not.
 * @module figure
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use json;
use strings;
use convert;
use regex;

import "html.j" as html;

def const API as int init 1;

# An image, alone on its line: `![alt](dest)`, with an optional title inside the
# parentheses. A line with anything else on it is prose about a picture.
def const IMAGE as string init '^!\[([^\]]*)\]\(([^)]+)\)$';

# A refusal, rather than an exit: `run` turns it into a status and a message on
# stderr, and a test can catch it. `exit` inside a module would take the test
# runner with it.
func fail(message as string) {
    throw Error{kind: "plugin", message: $message, file: "", line: 0, col: 0};
}

/**
 * One picture, as its Markdown gives it.
 * @field alt {string} the alt text, which stays the alt text
 * @field src {string} the image's path
 * @field title {string} the title in quotes, or ""
 */
export def struct Picture {
    alt as string,
    src as string,
    title as string
};

/**
 * Split an image's destination into the path and the title beside it.
 *
 * `pipeline.png "How a book is built"` is one destination in Markdown and two
 * things to a reader.
 * @param alt {string} the alt text
 * @param dest {string} everything between the parentheses
 * @return {Picture} the picture, with its title split off
 */
export func pictureOf(alt as string, dest as string) {
    def rest as string init strings.trim($dest);
    def title as string init "";
    for (def quote in ['"', "'"]) {
        if (not strings.endsWith($rest, $quote)) {
            continue;
        }
        def at as int init strings.indexOf($rest, " " + $quote);
        if ($at < 0) {
            continue;
        }
        $title = strings.substring($rest, $at + 2, len($rest) - 1);
        $rest = strings.trim(strings.substring($rest, 0, $at));
        break;
    }
    return Picture{alt: $alt, src: $rest, title: $title};
}

/**
 * The caption a picture gets, or "" when it has none to give.
 *
 * `auto` prefers the title and falls back to the alt text, which is what a book
 * that writes both means by writing both. `title` and `alt` say which one,
 * for a book whose alt text is written for a screen reader rather than for a
 * caption - the two are not the same sentence.
 * @param picture {Picture} the picture
 * @param source {string} "auto", "title", or "alt"
 * @return {string} the caption text
 * @throws {Error} kind "plugin" when `source` is none of the three
 */
export func captionOf(picture as Picture, source as string) {
    match ($source) {
        when "auto" { if ($picture.title != "") {
            return $picture.title;
        }
        return $picture.alt; }
        when "title" { return $picture.title; }
        when "alt" { return $picture.alt; }
        else { fail("caption is \"" + $source + "\": it is `auto`, `title`, or `alt`"); }
    }
    return "";
}

# The picture and its caption, as Markdown: the form that reaches the site, the
# EPUB and the printable book alike.
func asMarkdown(picture as Picture, caption as string) {
    def image as string init "![" + $picture.alt + "](" + $picture.src + ")";
    return $image + "\n\n*" + $caption + "*";
}

# The picture and its caption, as a block of HTML: better markup, and the
# printable build skips it.
func asHtml(picture as Picture, caption as string) {
    return '<figure class="gr-figure">' + "\n" +
        '<img src="' + html.escape(html.safeUrl($picture.src)) + '" alt="' +
        html.escape($picture.alt) + '"/>' + "\n" +
        "<figcaption>" + html.escape($caption) + "</figcaption>\n</figure>";
}

# The fence a line opens or closes, or "".
func fenceOf(line as string) {
    def trimmed as string init strings.trim($line);
    for (def mark in ["```", "~~~"]) {
        if (not strings.startsWith($trimmed, $mark)) {
            continue;
        }
        def run as int init 0;
        for (def ch in strings.chars($trimmed)) {
            if ($ch != strings.substring($mark, 0, 1)) {
                break;
            }
            $run = $run + 1;
        }
        return strings.substring($trimmed, 0, $run);
    }
    return "";
}

/**
 * One chapter, with a caption under every picture that stands alone.
 *
 * A picture inside a sentence keeps its place in the sentence, and one with no
 * caption to give is left exactly as written - a book that wrote no title and no
 * alt text said what it wanted.
 * @param content {string} the chapter, as Markdown
 * @param source {string} where the caption comes from: "auto", "title", "alt"
 * @param markup {bool} true for a `<figure>` block, false for Markdown
 * @return {string} the chapter
 * @throws {Error} kind "plugin" when `source` is not one of the three
 */
export func expand(content as string, source as string, markup as bool) {
    def out as list of string;
    def fence as string init "";
    for (def line in strings.split($content, "\n")) {
        def mark as string init fenceOf($line);
        if ($fence == "" and $mark != "") {
            $fence = $mark;
            $out[] = $line;
            continue;
        }
        if ($fence != "") {
            if ($mark == $fence) {
                $fence = "";
            }
            $out[] = $line;
            continue;
        }
        def m as regex.Match init regex.find(IMAGE, strings.trim($line));
        if (len($m.groups) < 2) {
            $out[] = $line;
            continue;
        }
        def picture as Picture init pictureOf($m.groups[0], $m.groups[1]);
        def caption as string init captionOf($picture, $source);
        if (strings.trim($caption) == "") {
            $out[] = $line;
            continue;
        }
        if ($markup) {
            $out[] = asHtml($picture, $caption);
            continue;
        }
        $out[] = asMarkdown($picture, $caption);
    }
    return strings.join($out, "\n");
}

# The reply: the chapters that gained a caption, and no others.
func replyFor(req as json.Value) {
    def source as string init "auto";
    if (json.has($req, "/plugin/settings/caption")) {
        $source = json.asString($req, "/plugin/settings/caption");
    }
    def markup as bool init false;
    if (json.has($req, "/plugin/settings/html")) {
        $markup = json.asBool($req, "/plugin/settings/html");
    }
    def replies as list of string;
    for (def i in 0..json.length($req, "/chapters")) {
        def at as string init "/chapters/" + convert.toString($i);
        def content as string init json.asString($req, $at + "/content");
        def out as string init expand($content, $source, $markup);
        if ($out != $content) {
            $replies[] = '{"src":' + json.encode(json.asString($req, $at + "/src")) +
                ',"content":' + json.encode($out) + '}';
        }
    }
    return '{"api":' + convert.toString(API) + ',"chapters":[' +
        strings.join($replies, ",") + ']}';
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
        if (json.asString($req, "/kind") != "preprocessor") {
            fail("this is a preprocessor; the request asks for a " +
                json.asString($req, "/kind"));
        }
        io.printf("%s", replyFor($req));
        return 0;
    } catch (e) {
        io.eprintf("grimoire-figure: %s\n", $e.message);
        return 1;
    }
}
