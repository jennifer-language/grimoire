# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.27.0
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
use json;
use strings;
use convert;
import "../src/pluginkit.j" as kit;

# strftime, because that is what git's `--date=format:` takes and what Jennifer's
# own `time.format` takes. The date is asked of git already formatted, so there
# is no parsing here and no second idea of what a date looks like.
def const DEFAULT_FORMAT as string init "%Y-%m-%d";
def const DEFAULT_LABEL as string init "Last updated";

# Whether this is a checkout at all. A tarball is a perfectly good way to build a
# book; it just has no history to date it by.
func isCheckout(dir as string) {
    def result as kit.Ran init kit.runProgram(
        [
            "git",
            "-C",
            $dir,
            "rev-parse",
            "--is-inside-work-tree"
        ],
        "");
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
    def result as kit.Ran init kit.runProgram(
        [
            "git",
            "-C",
            $dir,
            "log",
            "-1",
            "--date=format:" + $format,
            "--format=%ad",
            "--",
            $file
        ],
        "");
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
        $body = $body[..len($body) - 1];
    }
    return $body + "\n\n*" + $label + ": " + $date + "*\n";
}

# The settings, with their defaults.
func formatOf(req as json.Value) {
    return kit.settingText($req, "format", DEFAULT_FORMAT);
}

func labelOf(req as json.Value) {
    return kit.settingText($req, "label", DEFAULT_LABEL);
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
                $replies[] = kit.chapterReply($src, $out);
            }
        }
    }
    return kit.preprocessorReply($replies);
}

/**
 * Run the plugin over one request.
 * @param request {string} the JSON request from stdin
 * @return {int} the exit status
 */
export func run(request as string) {
    try {
        def req as json.Value init kit.request($request, "preprocessor");
        io.printf("%s", replyFor($req));
        return 0;
    } catch (e) {
        return kit.report("grimoire-lastmod", $e.message);
    }
}
