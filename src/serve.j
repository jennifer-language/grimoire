# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The local preview server behind `grimoire serve`: a static file server over
 * the `httpd` engine, rooted at the build output.
 *
 * It runs a small pool of accept loops rather than one, because a single page
 * pulls its stylesheet, its runtime, and (on the first search) the index, and a
 * browser asks for those in parallel - a one-at-a-time loop would serialise
 * them. `httpd.serveDir` resolves the path, so `..` cannot escape the output
 * directory.
 *
 * With `--watch` it also reloads the browser. That is off in every other mode
 * and, more to the point, **the script that does it never touches the disk**: it
 * is spliced into the response on its way out, so the files in the output
 * directory are the same bytes a publish would upload. A preview build that had
 * quietly grown a polling loop would be a bad thing to `rsync`.
 *
 * Needs the default `jennifer` binary; `jennifer-tiny` stubs `httpd` and the
 * call reports that itself.
 * @module serve
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use httpd;
use task;
use io;
use fs;
use path;
use strings;
use convert;

import "./assets.j" as assets;

# Enough parallelism for a browser loading a page and its assets at once,
# without spinning up workers a local preview will never use.
def const WORKERS as int init 4;

# What the injected script asks, and how often. The leading dot keeps it out of
# the way of any chapter a book might name; the interval is a compromise between
# a save feeling instant and a browser tab that is left open all day.
def const RELOAD_PATH as string init "/.grimoire-reload";
def const POLL_MS as int init 700;

# The file whose modification time is the build token. Every successful build
# rewrites the stylesheet - unconditionally, like every other asset - so its
# timestamp moves exactly when there is something new to look at, and a build
# that failed leaves it alone. One `stat` answers a poll.
def const STAMP_FILE as string init "assets/grimoire.css";

# token is what the browser compares between polls. "" when the stylesheet is
# missing, which the script reads as "nothing to say" rather than as a change.
func token(root as string) {
    def file as string init path.join($root, STAMP_FILE);
    if (not fs.isFile($file)) {
        return "";
    }
    return convert.toString(fs.stat($file).mtimeNanos);
}

# pageFile resolves a request path to the HTML file it names, or "" for anything
# that is not one - an asset, a directory with no index, a path trying to climb
# out of the site.
#
# This is the one place that maps a URL onto the filesystem by hand rather than
# leaving it to `httpd.serveDir`, so it is also the one place that has to refuse
# `..` itself: the cleaned path has to stay relative and stay inside. A path that
# does not resolve here is not an error - it falls through to `serveDir`, which
# handles percent-encoding and everything else this deliberately does not.
func pageFile(root as string, urlPath as string) {
    def rel as string init $urlPath;
    if (strings.startsWith($rel, "/")) {
        $rel = strings.substring($rel, 1, len($rel));
    }
    if ($rel == "" or strings.endsWith($rel, "/")) {
        $rel = $rel + "index.html";
    }
    if (not strings.endsWith($rel, ".html")) {
        return "";
    }
    def clean as string init path.clean($rel);
    if (path.isAbs($clean) or strings.startsWith($clean, "..")) {
        return "";
    }
    def file as string init path.join($root, $clean);
    if (not fs.isFile($file)) {
        return "";
    }
    return $file;
}

# inject splices the reload script in before the closing body tag. Grimoire wrote
# the page being spliced, three modules away, and that page carries exactly one
# `</body>`, on its own line near the end.
func inject(page as string) {
    def script as string init "<script>" + assets.liveReload(RELOAD_PATH, POLL_MS) + "</script>";
    def at as int init strings.indexOf($page, "</body>");
    if ($at < 0) {
        return $page + $script;
    }
    return strings.substring($page, 0, $at) + $script +
        strings.substring($page, $at, len($page));
}

# answer handles one request: the reload endpoint, then an HTML page that needs
# the script spliced into it, and otherwise the file itself.
func answer(req as httpd.Request, root as string, live as bool) {
    if (not $live) {
        httpd.serveDir($req, $root);
        return 0;
    }
    if (httpd.path($req) == RELOAD_PATH) {
        httpd.setHeader($req, "Content-Type", "text/plain; charset=utf-8");
        httpd.setHeader($req, "Cache-Control", "no-store");
        httpd.respond($req, 200, token($root));
        return 0;
    }
    def file as string init pageFile($root, httpd.path($req));
    if ($file == "") {
        httpd.serveDir($req, $root);
        return 0;
    }
    httpd.setHeader($req, "Content-Type", "text/html; charset=utf-8");
    # A preview that answers from the browser cache is a preview of the last
    # build, which is the one thing this mode must not do.
    httpd.setHeader($req, "Cache-Control", "no-store");
    httpd.respond($req, 200, inject(fs.readString($file)));
    return 0;
}

# loop answers requests until the server is shut down, at which point `accept`
# errors and the worker retires quietly.
func loop(srv as httpd.Server, root as string, live as bool) {
    def running as bool init true;
    try {
        while ($running) {
            def req as httpd.Request init httpd.accept($srv);
            answer($req, $root, $live);
        }
    } catch (e) {
        # `accept` errors once the server is shut down; that is the exit path.
        $running = false;
    }
    return 0;
}

# displayUrl turns a listen address into something a reader can click: a bare
# port or a wildcard host becomes localhost.
func displayUrl(addr as string) {
    def host as string init $addr;
    if (strings.startsWith($host, ":")) {
        $host = "localhost" + $host;
    } elseif (strings.startsWith($host, "0.0.0.0:")) {
        $host = "localhost" + strings.substring($host, 7, len($host));
    }
    return "http://" + $host + "/";
}

/**
 * Serve a directory over HTTP until the process is interrupted.
 * @param root {string} the directory to serve
 * @param addr {string} the listen address, such as `127.0.0.1:8080`
 * @param live {bool} splice the live-reload script into every page served
 * @return {int} the process exit status
 * @throws {Error} kind "httpd" when the address cannot be bound
 */
export func run(root as string, addr as string, live as bool) {
    def srv as httpd.Server init httpd.listen($addr);
    io.printf("serving %s/ at %s (ctrl-c to stop)\n", $root, displayUrl($addr));
    def workers as list of task of int;
    for (def i in 1..WORKERS) {
        $workers[] = spawn {
            return loop($srv, $root, $live);
        };
    }
    # The last loop runs on this task, so the process stays alive without a wait.
    loop($srv, $root, $live);
    task.waitAll($workers);
    return 0;
}
