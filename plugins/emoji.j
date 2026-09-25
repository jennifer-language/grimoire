# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * `:rocket:` in a chapter, the character in the page.
 *
 * A preprocessor. It replaces the shortcodes a writer already knows from GitHub
 * with the characters they stand for, so a book can be written in plain ASCII
 * and still read the way its author meant.
 *
 * The table is **codepoints, not characters**: `convert.fromCodepoint` builds
 * each one where it is used. That keeps this file ASCII, which is what the rest
 * of the repository is held to, and it makes the identity of an entry the thing
 * that identifies it - a table of look-alike glyphs is a table nobody can
 * review.
 *
 * Two things worth knowing before turning it on. Fenced code is left alone, so
 * a page about shortcodes still shows them. And **the printable book draws what
 * its fonts carry**: an emoji reaches the PDF as whatever `TRANSLITERATIONS` in
 * `src/pdfbook.j` says, or as a question mark if it says nothing, which is
 * exactly what `scripts/check-print.j` reports. A book with a PDF should run it
 * after turning this on.
 * @module emoji
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use json;
use strings;
use convert;
use maps;

def const API as int init 1;

# The characters a shortcode may hold, which is what makes `:not a code:` prose
# and `:white_check_mark:` a name.
def const CODE as string init "abcdefghijklmnopqrstuvwxyz0123456789_+-";

# A name that stands beside a word is part of that word - a ratio like `1:2:3`,
# or a time. A shortcode stands on its own.
def const WORD as string init "abcdefghijklmnopqrstuvwxyz0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ";

# The shortcodes, as the codepoints they stand for. Curated rather than
# exhaustive: these are the ones documentation actually uses - a status, a
# warning, a direction, a piece of the toolchain. A book adds its own with
# `[preprocessor.emoji.extra]` and needs no change here.
#
# A sequence is a sequence: `warning` is U+26A0 plus the variation selector that
# asks for the emoji form rather than the text one, and dropping it gives a
# glyph that renders as a dingbat on half the machines that read the page.
def const SHORTCODES as map of string to list of int init {
    "warning": [0x26A0, 0xFE0F],
    "white_check_mark": [0x2705],
    "heavy_check_mark": [0x2714, 0xFE0F],
    "x": [0x274C],
    "no_entry": [0x26D4],
    "no_entry_sign": [0x1F6AB],
    "question": [0x2753],
    "exclamation": [0x2757],
    "bulb": [0x1F4A1],
    "memo": [0x1F4DD],
    "book": [0x1F4D6],
    "books": [0x1F4DA],
    "bookmark": [0x1F516],
    "label": [0x1F3F7, 0xFE0F],
    "package": [0x1F4E6],
    "wrench": [0x1F527],
    "hammer": [0x1F528],
    "gear": [0x2699, 0xFE0F],
    "nut_and_bolt": [0x1F529],
    "test_tube": [0x1F9EA],
    "microscope": [0x1F52C],
    "mag": [0x1F50D],
    "lock": [0x1F512],
    "unlock": [0x1F513],
    "key": [0x1F511],
    "shield": [0x1F6E1, 0xFE0F],
    "fire": [0x1F525],
    "boom": [0x1F4A5],
    "bug": [0x1F41B],
    "sparkles": [0x2728],
    "rocket": [0x1F680],
    "zap": [0x26A1],
    "hourglass": [0x231B],
    "alarm_clock": [0x23F0],
    "calendar": [0x1F4C5],
    "clipboard": [0x1F4CB],
    "chart_with_upwards_trend": [0x1F4C8],
    "bar_chart": [0x1F4CA],
    "file_folder": [0x1F4C1],
    "open_file_folder": [0x1F4C2],
    "page_facing_up": [0x1F4C4],
    "paperclip": [0x1F4CE],
    "pushpin": [0x1F4CC],
    "link": [0x1F517],
    "mailbox": [0x1F4EB],
    "email": [0x2709, 0xFE0F],
    "speech_balloon": [0x1F4AC],
    "loudspeaker": [0x1F4E2],
    "bell": [0x1F514],
    "computer": [0x1F4BB],
    "keyboard": [0x2328, 0xFE0F],
    "printer": [0x1F5A8, 0xFE0F],
    "floppy_disk": [0x1F4BE],
    "cd": [0x1F4BF],
    "camera": [0x1F4F7],
    "globe_with_meridians": [0x1F310],
    "house": [0x1F3E0],
    "construction": [0x1F6A7],
    "traffic_light": [0x1F6A6],
    "recycle": [0x267B, 0xFE0F],
    "arrow_right": [0x27A1, 0xFE0F],
    "arrow_left": [0x2B05, 0xFE0F],
    "arrow_up": [0x2B06, 0xFE0F],
    "arrow_down": [0x2B07, 0xFE0F],
    "arrows_counterclockwise": [0x1F504],
    "heavy_plus_sign": [0x2795],
    "heavy_minus_sign": [0x2796],
    "star": [0x2B50],
    "heart": [0x2764, 0xFE0F],
    "thumbsup": [0x1F44D],
    "thumbsdown": [0x1F44E],
    "wave": [0x1F44B],
    "eyes": [0x1F440],
    "thinking": [0x1F914],
    "tada": [0x1F389],
    "trophy": [0x1F3C6],
    "coffee": [0x2615],
    "penguin": [0x1F427],
    "snake": [0x1F40D],
    "whale": [0x1F433],
    "cat": [0x1F408],
    "dog": [0x1F415],
    "crystal_ball": [0x1F52E],
    "scroll": [0x1F4DC],
    "feather": [0x1FAB6]
};

# A refusal, rather than an exit: `run` turns it into a status and a message on
# stderr, and a test can catch it. `exit` inside a module would take the test
# runner with it.
func fail(message as string) {
    throw Error{kind: "plugin", message: $message, file: "", line: 0, col: 0};
}

/**
 * The character a list of codepoints stands for.
 * @param points {list of int} the codepoints, in order
 * @return {string} the character, variation selectors included
 */
export func characterOf(points as list of int) {
    def out as string init "";
    for (def point in $points) {
        $out = $out + convert.fromCodepoint($point);
    }
    return $out;
}

/**
 * Every shortcode this build knows: the table, and whatever the book added.
 *
 * A book's own entry wins, so a project can redefine `:warning:` to the glyph
 * its house style uses without waiting for anybody.
 * @param req {json.Value} the decoded request
 * @return {map of string to string} shortcode names, without the colons, to
 *   the characters they stand for
 * @throws {Error} kind "plugin" when an added entry is not a piece of text
 */
export func table(req as json.Value) {
    def out as map of string to string;
    for (def name in maps.keys(SHORTCODES)) {
        $out[$name] = characterOf(SHORTCODES[$name]);
    }
    if (not json.has($req, "/plugin/settings/extra")) {
        return $out;
    }
    for (def name in json.keys($req, "/plugin/settings/extra")) {
        def at as string init "/plugin/settings/extra/" + $name;
        if (json.typeOf(json.get($req, $at)) != "string") {
            fail("the extra shortcode \"" + $name + "\" is not a piece of text");
        }
        $out[$name] = json.asString($req, $at);
    }
    return $out;
}

# Whether the character at an index is one a word is made of. Out of range is
# not: the start and the end of a line are boundaries.
func wordAt(line as string, i as int) {
    if ($i < 0 or $i >= len($line)) {
        return false;
    }
    return strings.contains(WORD, strings.substring($line, $i, $i + 1));
}

# The shortcode that starts at `from`, or "": the colon, a name, a colon, and a
# boundary on each side.
func codeAt(line as string, from as int) {
    def stop as int init $from + 1;
    while ($stop < len($line) and
        strings.contains(CODE, strings.substring($line, $stop, $stop + 1))) {
        $stop = $stop + 1;
    }
    if ($stop >= len($line) or $stop == $from + 1) {
        return "";
    }
    if (strings.substring($line, $stop, $stop + 1) != ":") {
        return "";
    }
    if (wordAt($line, $from - 1) or wordAt($line, $stop + 1)) {
        return "";
    }
    return strings.substring($line, $from + 1, $stop);
}

# One line, with every shortcode the table knows replaced. A name it does not
# know is left exactly as written: a colon is punctuation long before it is
# markup, and a book is full of them.
func expandLine(line as string, codes as map of string to string) {
    def out as string init "";
    def i as int init 0;
    while ($i < len($line)) {
        if (strings.substring($line, $i, $i + 1) != ":") {
            $out = $out + strings.substring($line, $i, $i + 1);
            $i = $i + 1;
            continue;
        }
        def name as string init codeAt($line, $i);
        if ($name == "" or not maps.has($codes, $name)) {
            $out = $out + ":";
            $i = $i + 1;
            continue;
        }
        $out = $out + $codes[$name];
        $i = $i + len($name) + 2;
    }
    return $out;
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
 * One chapter, with its shortcodes replaced.
 *
 * Fenced code is left alone, so a page about shortcodes still shows them.
 * @param content {string} the chapter, as Markdown
 * @param codes {map of string to string} the shortcodes this build knows
 * @return {string} the chapter
 */
export func expand(content as string, codes as map of string to string) {
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
        $out[] = expandLine($line, $codes);
    }
    return strings.join($out, "\n");
}

# The reply: the chapters that used a shortcode, and no others.
func replyFor(req as json.Value) {
    def codes as map of string to string init table($req);
    def replies as list of string;
    for (def i in 0..json.length($req, "/chapters")) {
        def at as string init "/chapters/" + convert.toString($i);
        def content as string init json.asString($req, $at + "/content");
        def out as string init expand($content, $codes);
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
        io.eprintf("grimoire-emoji: %s\n", $e.message);
        return 1;
    }
}
