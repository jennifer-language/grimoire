# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The rebuild-on-change loop behind `grimoire serve --watch`.
 *
 * The watching is `fs.watch`: a background poll that diffs a snapshot of the
 * tree and delivers `fs.Event` values, which `fs.next` blocks on. Blocking is
 * what makes this cheap - the loop costs nothing between saves, and the poll it
 * sits on runs outside the interpreter, so the server in the main task is never
 * held up by it.
 *
 * Refreshing the browser is `serve`'s half of the job, not this one: it splices
 * a script into the pages it serves that polls for the build. Nothing here
 * knows about that, and nothing on disk carries it - see `src/serve.j`.
 * @module watch
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use fs;
use path;
use strings;
use time;
use convert;

import "./config.j" as config;
import "./build.j" as build;

# How often `fs.watch` re-scans. Fast enough that a save and a reload feel
# connected, slow enough to stay invisible on a battery.
def const POLL_MS as int init 400;

# How long to wait after the first event of a change before draining the rest.
#
# One scan delivers every path it found changed, and a single save is usually
# several: the file itself, its directory's mtime, an editor's temporary file
# beside it. They are queued together, but this loop can wake on the first one
# while the scan is still pushing the others, and rebuilding once per path would
# make a save cost three builds. Far below the poll interval, so it is invisible;
# far above the gap between two pushes onto a queue.
def const SETTLE_MS as int init 50;

# ignored is the prefix an event path carries when Grimoire wrote it itself, for
# the book whose output directory sits inside its source tree. That book is why
# this exists: without it the first rebuild writes into the tree being watched,
# which is another change, which is another rebuild, for ever. Draining the queue
# after a build does not fix it - the write lands before the scan that finds it,
# so there is nothing to drain yet.
#
# "" for a watch with nothing of ours underneath it.
func ignored(outDir as string) {
    if ($outDir == "") {
        return "";
    }
    return path.clean($outDir) + "/";
}

# ignorable reports whether an event is not a source change: a bare directory
# mtime bump, or something Grimoire just wrote.
#
# Directory events are dropped rather than acted on because adding or removing a
# file bumps its directory's mtime, so every child event arrives with one; the
# child is behind it in the queue, and a directory on its own has nothing to
# render.
func ignorable(e as fs.Event, ours as string) {
    if ($e.isDir) {
        return true;
    }
    if ($ours == "") {
        return false;
    }
    return strings.startsWith(path.clean($e.path), $ours);
}

# drain empties whatever the same scan already queued, and reports how many of
# those were real changes.
func drain(w as fs.Watcher, ours as string) {
    def changes as int init 0;
    while (fs.hasEvent($w)) {
        def e as fs.Event init fs.next($w);
        if (not ignorable($e, $ours)) {
            $changes = $changes + 1;
        }
    }
    return $changes;
}

# settle waits out the rest of one scan's events and returns how many further
# changes it accounted for.
func settle(w as fs.Watcher, ours as string) {
    time.sleep(time.fromMilliseconds(SETTLE_MS));
    return drain($w, $ours);
}

# rebuild runs one build and reports it, turning a failure into a message rather
# than an exit. A watch loop that died on the first typo in a `SUMMARY.md` would
# be worse than no watch loop at all: the moment a build breaks is the moment the
# loop is most needed.
func rebuild(c as config.Config) {
    try {
        def report as build.Report init build.run($c);
        io.printf("rebuilt %d pages into %s/\n", $report.pages, $c.outDir);
        for (def missing in $report.missing) {
            io.printf("  missing: %s\n", $missing);
        }
    } catch (e) {
        io.eprintf("grimoire: rebuild failed: %s\n", $e.message);
    }
}

# also is the "and 3 more" a multi-file change gets reported with, and "" for
# the single-file save that is the usual case.
func also(count as int) {
    if ($count < 1) {
        return "";
    }
    return " and " + convert.toString($count) + " more";
}

# watchConfig reports changes to the configuration file, and never acts on them.
#
# Saying so is the whole point of watching it apart from the sources. This loop
# holds the configuration resolved when `serve` started, command-line overrides
# included; rebuilding on a changed `grimoire.toml` would quietly use the old
# theme and the old title and look like it had worked.
func watchConfig(configPath as string) {
    def w as fs.Watcher init fs.watch($configPath, POLL_MS);
    def watching as bool init true;
    while ($watching) {
        try {
            def e as fs.Event init fs.next($w);
            settle($w, "");
            io.printf("%s %s - restart serve to pick it up\n", $e.path, $e.kind);
        } catch (stop) {
            # fs.next errors once the watcher is closed, and that is the way out
            # of a loop that otherwise has none.
            $watching = false;
        }
    }
    return 0;
}

/**
 * Watch the source tree and rebuild whenever it changes. Runs until the process
 * is interrupted.
 * @param c {config.Config} the book configuration
 * @param configPath {string} the configuration file to watch as well ("" for none)
 * @return {int} the process exit status; the loop does not return on its own
 */
export func run(c as config.Config, configPath as string) {
    def sources as fs.Watcher init fs.watch($c.srcDir, POLL_MS);
    if ($configPath != "" and fs.isFile($configPath)) {
        spawn {
            return watchConfig($configPath);
        };
    }
    def ours as string init ignored($c.outDir);
    def watching as bool init true;
    while ($watching) {
        try {
            def e as fs.Event init fs.next($sources);
            if (not ignorable($e, $ours)) {
                def more as int init settle($sources, $ours);
                io.printf("%s %s%s - rebuilding\n", $e.path, $e.kind, also($more));
                rebuild($c);
            }
        } catch (stop) {
            # As above - a closed watcher releases the loop.
            $watching = false;
        }
    }
    return 0;
}

/**
 * The one-line notice `serve` prints when watching, which says whether the
 * browser will follow along on its own or has to be told.
 * @param c {config.Config} the book configuration
 * @param live {bool} whether the pages served carry the reload script
 * @return {string} the notice
 */
export func notice(c as config.Config, live as bool) {
    if ($live) {
        return "watching " + $c.srcDir + "/ for changes (the page reloads itself)";
    }
    return "watching " + $c.srcDir + "/ for changes (reload the page to see them)";
}
