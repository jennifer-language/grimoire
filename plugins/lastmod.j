# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0
# pragma-jennifer-capability: exec

/**
 * A `Last updated` line on each chapter, from git.
 *
 * A preprocessor. The date is the last commit that touched the chapter, asked
 * of git once per file, and it is appended to the chapter it belongs to.
 *
 * The date comes from history rather than from the filesystem on purpose. A
 * fresh checkout stamps every file with the moment it was cloned, so a build
 * from one would claim the whole book changed today - which is worse than saying
 * nothing, because a reader has no way to tell the difference.
 *
 * A book with no git, and a chapter with no commit behind it, both get nothing
 * added. Neither is an error: a tarball is a perfectly good way to build a book,
 * and a chapter written this morning is simply not in history yet.
 * @module lastmod
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use os;
use json;
use strings;
use convert;

def const API as int init 1;

# strftime, because that is what git's `--date=format:` takes and what Jennifer's
# own `time.format` takes. The date is asked of git already formatted, so there
# is no parsing here and no second idea of what a date looks like.
def const DEFAULT_FORMAT as string init "%Y-%m-%d";
def const DEFAULT_LABEL as string init "Last updated";

# A refusal, rather than an exit: `run` turns it into a status and a message on
# stderr, and a test can catch it. `exit` inside a module would take the test
# runner with it.
func fail(message as string) {
    throw Error{kind: "plugin", message: $message, file: "", line: 0, col: 0};
}

# Whether this is a checkout at all. A tarball is a perfectly good way to build a
# book; it just has no history to date it by.
func isCheckout(dir as string) {
    def result as os.Result;
    try {
        $result = os.run(["git", "-C", $dir, "rev-parse", "--is-inside-work-tree"]);
    } catch (e) {
        return false;
    }
    return $result.exitCode == 0 and strings.trim($result.stdout) == "true";
}

/**
 * The date of the last commit that touched one file, already formatted.
 *
 * git does the formatting: `--date=format:` takes the same strftime layout the
 * configuration does, which keeps one idea of what a date looks like rather than
 * two. An untracked file, or a repository with no commits, gives "".
 * @param dir {string} the directory to ask git in
 * @param file {string} the file, relative to that directory
 * @param format {string} a strftime layout
 * @return {string} the date, or "" when git has nothing to say about the file
 */
export func dateOf(dir as string, file as string, format as string) {
    def result as os.Result;
    try {
        $result = os.run([
            "git",
            "-C",
            $dir,
            "log",
            "-1",
            "--date=format:" + $format,
            "--format=%ad",
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

/**
 * A chapter with its date on the end.
 *
 * The line is emphasised Markdown rather than markup, so it reaches the site,
 * the printable book and the EPUB alike, and a book can style it with the
 * selector its theme already has for emphasis.
 * @param content {string} the chapter
 * @param label {string} the words in front of the date
 * @param date {string} the date, already formatted
 * @return {string} the chapter, with the line appended
 */
export func stamped(content as string, label as string, date as string) {
    if ($date == "") {
        return $content;
    }
    def body as string init $content;
    while (strings.endsWith($body, "\n")) {
        $body = strings.substring($body, 0, len($body) - 1);
    }
    return $body + "\n\n*" + $label + ": " + $date + "*\n";
}

# The settings, with their defaults.
func formatOf(req as json.Value) {
    if (json.has($req, "/plugin/settings/format")) {
        return json.asString($req, "/plugin/settings/format");
    }
    return DEFAULT_FORMAT;
}

func labelOf(req as json.Value) {
    if (json.has($req, "/plugin/settings/label")) {
        return json.asString($req, "/plugin/settings/label");
    }
    return DEFAULT_LABEL;
}

/**
 * The reply for one request: every chapter that has a date, and no others.
 *
 * A book that is not a checkout replies with no chapters at all rather than
 * asking git about each one in turn, which is one process per chapter to be told
 * the same thing every time.
 * @param req {json.Value} the decoded request
 * @return {string} the JSON reply
 */
export func replyFor(req as json.Value) {
    def root as string init json.asString($req, "/book/src");
    def replies as list of string;
    if (isCheckout($root)) {
        def format as string init formatOf($req);
        def label as string init labelOf($req);
        for (def i in 0..json.length($req, "/chapters")) {
            def at as string init "/chapters/" + convert.toString($i);
            def src as string init json.asString($req, $at + "/src");
            def content as string init json.asString($req, $at + "/content");
            def out as string init stamped($content, $label, dateOf($root, $src, $format));
            if ($out != $content) {
                $replies[] = '{"src":' + json.encode($src) + ',"content":' +
                    json.encode($out) + '}';
            }
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
        io.eprintf("grimoire-lastmod: %s\n", $e.message);
        return 1;
    }
}
