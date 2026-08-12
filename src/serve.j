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
 * Needs the default `jennifer` binary; `jennifer-tiny` stubs `httpd` and the
 * call reports that itself.
 * @module serve
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use httpd;
use task;
use io;
use strings;

# Enough parallelism for a browser loading a page and its assets at once,
# without spinning up workers a local preview will never use.
def const WORKERS as int init 4;

# loop answers requests until the server is shut down, at which point `accept`
# errors and the worker retires quietly.
func loop(srv as httpd.Server, root as string) {
    def running as bool init true;
    try {
        while ($running) {
            def req as httpd.Request init httpd.accept($srv);
            httpd.serveDir($req, $root);
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
 * @return {int} the process exit status
 * @throws {Error} kind "httpd" when the address cannot be bound
 */
export func run(root as string, addr as string) {
    def srv as httpd.Server init httpd.listen($addr);
    io.printf("serving %s/ at %s (ctrl-c to stop)\n", $root, displayUrl($addr));
    def workers as list of task of int;
    for (def i in 1..WORKERS) {
        $workers[] = spawn {
            return loop($srv, $root);
        };
    }
    # The last loop runs on this task, so the process stays alive without a wait.
    loop($srv, $root);
    task.waitAll($workers);
    return 0;
}
