# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `plugin.j`, run by `jennifer test src/plugin_test.j`.
 *
 * The contract is the thing under test, and both halves of it are text: a
 * request a program written in any language has to be able to read, and a reply
 * this build has to read back. `request` and `merge` are tested directly for
 * that reason - a change to either is a change other people's programs see.
 *
 * The runner itself is exercised through real subprocesses. `sh` is what the
 * fixtures are written in, so the tests need no interpreter but the one already
 * running them, and a plugin that misbehaves - wrong exit code, wrong api,
 * unknown chapter, missing binary - is a case rather than a hypothetical.
 * @module plugin_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use strings;
use maps;

# A book on disk: two chapters, one of them nested.
func book() {
    def root as string init fs.makeTempDir(os.tempDir(), "grimoire-plugin-");
    fs.writeString(path.join($root, "index.md"), "# One\n");
    fs.mkdirAll(path.join($root, "deep"));
    fs.writeString(path.join($root, "deep/two.md"), "# Two\n");
    return $root;
}

func entryFor(src as string, title as string) {
    return summary.Entry{
        kind: summary.pageKind(),
        title: $title,
        src: $src,
        out: $src + ".html",
        level: 0,
        number: ""
    };
}

func pagesOf() {
    return [entryFor("index.md", "One"), entryFor("deep/two.md", "Two")];
}

func sourcesOf() {
    def out as map of string to string;
    $out["index.md"] = "# One\n";
    $out["deep/two.md"] = "# Two\n";
    return $out;
}

func specFor(command as string) {
    def none as list of string;
    return config.Plugin{name: "probe", command: $command, args: $none, settings: '{"depth":2}'};
}

# A shell script that answers with `reply`, whatever it is asked. Written to a
# temp directory and made executable, so the runner reaches it the way it reaches
# any other plugin.
func plugAnswering(reply as string) {
    def dir as string init fs.makeTempDir(os.tempDir(), "grimoire-plug-");
    def file as string init path.join($dir, "plug.sh");
    fs.writeString($file, "#!/bin/sh\ncat > /dev/null\ncat <<'REPLY'\n" + $reply + "\nREPLY\n");
    os.run(["chmod", "+x", $file]);
    return $file;
}

# A script that reads the request, writes it to a file, and answers with a fixed
# reply - so a test can assert on what the plugin was actually handed.
func plugRecording(into as string, reply as string) {
    def dir as string init fs.makeTempDir(os.tempDir(), "grimoire-plug-");
    def file as string init path.join($dir, "plug.sh");
    fs.writeString($file, "#!/bin/sh\ncat > " + $into + "\ncat <<'REPLY'\n" + $reply + "\nREPLY\n");
    os.run(["chmod", "+x", $file]);
    return $file;
}

func plugFailing(code as string, message as string) {
    def dir as string init fs.makeTempDir(os.tempDir(), "grimoire-plug-");
    def file as string init path.join($dir, "plug.sh");
    fs.writeString(
        $file,
        "#!/bin/sh\ncat > /dev/null\necho '" + $message + "' >&2\nexit " + $code + "\n");
    os.run(["chmod", "+x", $file]);
    return $file;
}

func configWith(root as string, command as string) {
    def c as config.Config init config.apply(
        config.defaults(),
        '[book]
title = "T"

[preprocessor.probe]
command = "' + $command + '"
');
    $c.srcDir = $root;
    return $c;
}

# --- the request -----------------------------------------------------

# Every field a plugin is promised. Asserted as JSON rather than as text: the
# shape is the contract, and a reader parses it.
func testTheRequestCarriesTheBookAndTheChapters() {
    def c as config.Config init config.defaults();
    $c.title = "The Book";
    $c.language = "de";
    $c.authors = ["Ada"];
    def body as string init request(
        $c,
        specFor("x"),
        "preprocessor",
        pagesOf(),
        pagesOf(),
        sourcesOf());
    def doc as json.Value init json.decode($body);
    testing.assertEqual(json.asInt($doc, "/api"), 1);
    testing.assertEqual(json.asString($doc, "/book/title"), "The Book");
    testing.assertEqual(json.asString($doc, "/book/language"), "de");
    testing.assertEqual(json.asString($doc, "/book/authors/0"), "Ada");
    testing.assertEqual(json.asString($doc, "/plugin/name"), "probe");
    testing.assertEqual(json.asInt($doc, "/plugin/settings/depth"), 2);
    testing.assertEqual(json.length($doc, "/chapters"), 2);
    testing.assertEqual(json.asString($doc, "/chapters/0/src"), "index.md");
    testing.assertEqual(json.asString($doc, "/chapters/0/content"), "# One\n");
}

# The outline goes over whole, so a plugin can see which part a chapter sits
# under without reading `SUMMARY.md` itself.
func testTheRequestCarriesTheOutline() {
    def entries as list of summary.Entry init [
        summary.Entry{
            kind: summary.partKind(),
            title: "Guides",
            src: "",
            out: "",
            level: 0,
            number: ""
        },
        entryFor("index.md", "One")
    ];
    def body as string init request(
        config.defaults(),
        specFor("x"),
        "preprocessor",
        $entries,
        pagesOf(),
        sourcesOf());
    def doc as json.Value init json.decode($body);
    testing.assertEqual(json.length($doc, "/entries"), 2);
    testing.assertEqual(json.asString($doc, "/entries/0/kind"), summary.partKind());
    testing.assertEqual(json.asString($doc, "/entries/0/title"), "Guides");
}

# A chapter is JSON-encoded text, so a quotation mark or a newline in a book is
# not a wire problem.
func testTheRequestEscapesTheContent() {
    def sources as map of string to string;
    $sources["index.md"] = 'a "quote" and a \\ backslash' + "\nand a newline\n";
    def pages as list of summary.Entry init [entryFor("index.md", "One")];
    def body as string init request(
        config.defaults(),
        specFor("x"),
        "preprocessor",
        $pages,
        $pages,
        $sources);
    def doc as json.Value init json.decode($body);
    testing.assertEqual(json.asString($doc, "/chapters/0/content"), $sources["index.md"]);
}

# --- the reply -------------------------------------------------------

func testMergeAppliesARewrite() {
    def out as map of string to string init merge(
        "preprocessor",
        specFor("x"),
        sourcesOf(),
        '{"api":1,"chapters":[{"src":"index.md","content":"rewritten"}]}');
    testing.assertEqual($out["index.md"], "rewritten");
    testing.assertEqual($out["deep/two.md"], "# Two\n");
}

# A reply is allowed to be sparse: a plugin that touches one chapter says so and
# the rest are left alone.
func testMergeLeavesUnmentionedChaptersAlone() {
    def out as map of string to string init merge(
        "preprocessor",
        specFor("x"),
        sourcesOf(),
        '{"api":1}');
    testing.assertEqual($out["index.md"], "# One\n");
    testing.assertEqual(len(maps.keys($out)), 2);
}

# The outline decides what a book contains. A reply naming something else is a
# plugin working from a book this is not.
func mergeUnknownChapter() {
    merge(
        "preprocessor",
        specFor("x"),
        sourcesOf(),
        '{"api":1,"chapters":[{"src":"nope.md","content":"x"}]}');
}

func testMergeRefusesAChapterTheBookDoesNotHave() {
    testing.assertThrows("mergeUnknownChapter", "grimoire");
}

# A plugin written against a later contract is refused rather than read as
# though it spoke this one.
func mergeFutureApi() {
    merge("preprocessor", specFor("x"), sourcesOf(), '{"api":99,"chapters":[]}');
}

func testMergeRefusesAnotherApiVersion() {
    testing.assertThrows("mergeFutureApi", "grimoire");
}

func mergeGarbage() {
    merge("preprocessor", specFor("x"), sourcesOf(), '["not", "an", "object"]');
}

func testMergeRefusesSomethingThatIsNotTheContract() {
    testing.assertThrows("mergeGarbage", "grimoire");
}

# --- running one -----------------------------------------------------

func testAPluginRewritesTheBook() {
    def root as string init book();
    def c as config.Config init configWith(
        $root,
        plugAnswering('{"api":1,"chapters":[{"src":"index.md","content":"# Rewritten\n"}]}'));
    def pages as list of summary.Entry init pagesOf();
    def dir as string init preprocess($c, $pages, $pages);
    testing.assertNotEqual($dir, $root);
    testing.assertEqual(fs.readString(path.join($dir, "index.md")), "# Rewritten\n");
    # The scratch tree is a complete book, not only what changed, so nothing
    # downstream has to know a plugin ran.
    testing.assertEqual(fs.readString(path.join($dir, "deep/two.md")), "# Two\n");
    discard($c, $dir);
    fs.removeAll($root);
}

func testTheRequestReachesThePlugin() {
    def root as string init book();
    def seen as string init path.join(os.tempDir(), "grimoire-plugin-seen.json");
    def c as config.Config init configWith($root, plugRecording($seen, '{"api":1}'));
    def pages as list of summary.Entry init pagesOf();
    def dir as string init preprocess($c, $pages, $pages);
    def doc as json.Value init json.decode(fs.readString($seen));
    testing.assertEqual(json.asString($doc, "/plugin/name"), "probe");
    testing.assertEqual(json.length($doc, "/chapters"), 2);
    discard($c, $dir);
    fs.removeAll($root);
    fs.removeAll($seen);
}

# A build that half-ran a plugin is worse than one that stopped, so a non-zero
# exit is an error with the plugin's own message in it.
func testAFailingPluginStopsTheBuild() {
    def root as string init book();
    def c as config.Config init configWith($root, plugFailing("2", "no such include"));
    def pages as list of summary.Entry init pagesOf();
    def threw as bool init false;
    try {
        preprocess($c, $pages, $pages);
    } catch (e) {
        $threw = true;
        testing.assertEqual($e.kind, "grimoire");
        testing.assertContains($e.message, "preprocessor probe");
        testing.assertContains($e.message, "no such include");
    }
    testing.assertTrue($threw);
    fs.removeAll($root);
}

# "executable file not found" on its own sends the reader to the wrong
# repository.
func testAMissingPluginSaysWhichOne() {
    def root as string init book();
    def c as config.Config init configWith($root, "grimoire-no-such-plugin-here");
    def pages as list of summary.Entry init pagesOf();
    def threw as bool init false;
    try {
        preprocess($c, $pages, $pages);
    } catch (e) {
        $threw = true;
        testing.assertContains($e.message, "preprocessor probe");
        testing.assertContains($e.message, "grimoire-no-such-plugin-here");
    }
    testing.assertTrue($threw);
    fs.removeAll($root);
}

# --- renderers -------------------------------------------------------

func rendererConfig(root as string, command as string) {
    def c as config.Config init config.apply(
        config.defaults(),
        '[book]
title = "T"

[renderer.probe]
command = "' + $command + '"
');
    $c.srcDir = $root;
    return $c;
}

# The same request with a different `kind`, so one program can implement both
# and know which it is being asked for.
func testARendererIsAskedAsARenderer() {
    def root as string init book();
    def seen as string init path.join(os.tempDir(), "grimoire-renderer-seen.json");
    def c as config.Config init rendererConfig($root, plugRecording($seen, '{"api":1}'));
    def pages as list of summary.Entry init pagesOf();
    render($c, $pages, $pages);
    def doc as json.Value init json.decode(fs.readString($seen));
    testing.assertEqual(json.asString($doc, "/kind"), "renderer");
    testing.assertEqual(json.asString($doc, "/book/out"), $c.outDir);
    # The chapters go over as the preprocessors left them: a renderer making a
    # second edition wants that text, not the HTML it can read off disk.
    testing.assertEqual(json.length($doc, "/chapters"), 2);
    fs.removeAll($root);
    fs.removeAll($seen);
}

func testARendererReportsWhatItWrote() {
    def root as string init book();
    def c as config.Config init rendererConfig(
        $root,
        plugAnswering('{"api":1,"written":["book.epub","cover.png"]}'));
    def pages as list of summary.Entry init pagesOf();
    def results as list of Rendered init render($c, $pages, $pages);
    testing.assertEqual(len($results), 1);
    testing.assertEqual($results[0].name, "probe");
    testing.assertEqual(len($results[0].written), 2);
    testing.assertEqual($results[0].written[0], "book.epub");
    testing.assertEqual(len($results[0].warnings), 0);
    fs.removeAll($root);
}

# A renderer that has something to say says it where the build's own warnings
# are already printed.
func testARendererCanWarn() {
    def root as string init book();
    def c as config.Config init rendererConfig(
        $root,
        plugAnswering('{"api":1,"warnings":["no cover image"]}'));
    def pages as list of summary.Entry init pagesOf();
    def results as list of Rendered init render($c, $pages, $pages);
    testing.assertEqual(len($results[0].warnings), 1);
    testing.assertEqual($results[0].warnings[0], "no cover image");
    fs.removeAll($root);
}

# Plenty of renderers write nothing and simply check.
func testARendererNeedNotReportAnything() {
    def root as string init book();
    def c as config.Config init rendererConfig($root, plugAnswering('{"api":1}'));
    def pages as list of summary.Entry init pagesOf();
    def results as list of Rendered init render($c, $pages, $pages);
    testing.assertEqual(len($results[0].written), 0);
    testing.assertEqual(len($results[0].warnings), 0);
    fs.removeAll($root);
}

func testAFailingRendererStopsTheBuild() {
    def root as string init book();
    def c as config.Config init rendererConfig($root, plugFailing("3", "pandoc not found"));
    def pages as list of summary.Entry init pagesOf();
    def threw as bool init false;
    try {
        render($c, $pages, $pages);
    } catch (e) {
        $threw = true;
        testing.assertEqual($e.kind, "grimoire");
        # The kind is part of the message: a renderer reported as a preprocessor
        # sends the reader to the wrong table in their configuration.
        testing.assertContains($e.message, "renderer probe");
        testing.assertContains($e.message, "pandoc not found");
    }
    testing.assertTrue($threw);
    fs.removeAll($root);
}

# --- finding the program ---------------------------------------------

# A bare name is looked for beside Grimoire before `PATH`, which is where the
# plugins that ship live: they stay out of `/usr/bin`, where they would share a
# prefix with the `grimoire` command and cost a keystroke on every completion.
func testABareNameIsFoundBesideGrimoire() {
    def app as string init fs.makeTempDir(os.tempDir(), "grimoire-app-");
    fs.mkdirAll(path.join($app, "plugins"));
    def shipped as string init path.join($app, "plugins/grimoire-probe");
    # `appDir` is the module tree; the plugins sit beside it.
    # The braces live in a raw string: a cooked one reads them as an
    # interpolation.
    fs.writeString($shipped, "#!/bin/sh\ncat > /dev/null\necho " + '{"api":1}' + "\n");
    os.run(["chmod", "+x", $shipped]);
    def c as config.Config init config.defaults();
    $c.appDir = path.join($app, "src");
    testing.assertEqual(resolved($c, "preprocessor", specFor("grimoire-probe")).path, $shipped);
    # Anything it does not ship is left to `PATH`, where this one is not either.
    testing.assertEqual(resolved($c, "preprocessor", specFor("grimoire-elsewhere")).path, "");
    fs.removeAll($app);
}

# A name with a separator is a path, which is how a book points at a plugin it
# keeps in its own repository. It is reported as the absolute path that will run,
# because "./tools/mermaid" says nothing about which file that is.
func testAPathIsResolvedAgainstTheDirectoryTheBuildRunsIn() {
    def c as config.Config init config.defaults();
    $c.appDir = "/opt/grimoire/src";
    testing.assertEqual(
        resolved($c, "preprocessor", specFor("./plugins/grimoire-sitemap")).path,
        path.join(os.cwd(), "plugins/grimoire-sitemap"));
    testing.assertEqual(resolved($c, "preprocessor", specFor("/bin/sh")).path, "/bin/sh");
    # A path to nothing resolves to nothing rather than to a plausible string.
    testing.assertEqual(resolved($c, "preprocessor", specFor("./tools/mermaid")).path, "");
}

# The whole path: a shipped plugin runs from beside Grimoire with nothing on
# `PATH` and no `command` in the table.
func testAShippedPluginRunsWithoutBeingInstalled() {
    def root as string init book();
    def app as string init fs.makeTempDir(os.tempDir(), "grimoire-app-");
    fs.mkdirAll(path.join($app, "plugins"));
    def shipped as string init path.join($app, "plugins/grimoire-probe");
    # `appDir` is the module tree; the plugins sit beside it.
    fs.writeString(
        $shipped,
        "#!/bin/sh\ncat > /dev/null\ncat <<'REPLY'\n" +
            '{"api":1,"chapters":[{"src":"index.md","content":"# Shipped\n"}]}' + "\nREPLY\n");
    os.run(["chmod", "+x", $shipped]);
    def c as config.Config init config.apply(
        config.defaults(),
        '[book]
title = "T"

[preprocessor.probe]
');
    $c.srcDir = $root;
    $c.appDir = path.join($app, "src");
    def pages as list of summary.Entry init pagesOf();
    def dir as string init preprocess($c, $pages, $pages);
    testing.assertEqual(fs.readString(path.join($dir, "index.md")), "# Shipped\n");
    discard($c, $dir);
    fs.removeAll($root);
    fs.removeAll($app);
}

# --- no plugins ------------------------------------------------------

# The pipeline a book without plugins gets is the one it had: the same directory,
# no temp tree, no process.
func testWithoutAPluginNothingHappens() {
    def root as string init book();
    def c as config.Config init config.defaults();
    $c.srcDir = $root;
    def pages as list of summary.Entry init pagesOf();
    testing.assertEqual(preprocess($c, $pages, $pages), $root);
    testing.assertEqual(len(render($c, $pages, $pages)), 0);
    fs.removeAll($root);
}

# --- discard ---------------------------------------------------------

# The test is on the path rather than on a flag, so a caller holding `srcDir`
# cannot delete the book.
func testDiscardRefusesAnythingButItsOwnTree() {
    def c as config.Config init config.defaults();
    $c.srcDir = "/books/mine";
    testing.assertFalse(discard($c, "/books/mine"));
    testing.assertFalse(discard($c, ""));
    testing.assertFalse(discard($c, "/tmp/somewhere-else"));
}

# --- what runs, and where it came from --------------------------------

# A plugin's program, by its real path, is the one thing about a build that
# reading the book does not tell you. These cover the four answers.

func testABareNameResolvesBesideGrimoireFirst() {
    def c as config.Config init config.defaults();
    def root as string init fs.makeTempDir(os.tempDir(), "grimoire-app-");
    fs.mkdirAll(path.join($root, "plugins"));
    fs.mkdirAll(path.join($root, "src"));
    def shipped as string init path.join($root, "plugins/grimoire-probe");
    fs.writeString($shipped, "#!/bin/sh\n");
    os.run(["chmod", "+x", $shipped]);
    $c.appDir = path.join($root, "src");
    def r as Resolved init resolved($c, "preprocessor", specFor("grimoire-probe"));
    testing.assertEqual($r.path, $shipped);
    testing.assertEqual($r.origin, "ships with Grimoire");
    fs.removeAll($root);
}

# `sh` is on every machine this runs on, and is exactly the case worth naming:
# a bare name that is not Grimoire's own, answered by something on PATH.
func testABareNameOtherwiseComesFromPath() {
    def c as config.Config init config.defaults();
    $c.appDir = path.join(os.tempDir(), "no-such-grimoire/src");
    def r as Resolved init resolved($c, "preprocessor", specFor("sh"));
    testing.assertEqual($r.origin, "found on PATH");
    testing.assertTrue(strings.endsWith($r.path, "/sh"));
}

func testANameNothingAnswersToIsReportedAsMissing() {
    def c as config.Config init config.defaults();
    $c.appDir = path.join(os.tempDir(), "no-such-grimoire/src");
    def r as Resolved init resolved($c, "renderer", specFor("grimoire-not-installed"));
    testing.assertEqual($r.path, "");
    testing.assertEqual($r.origin, "not found");
}

# A relative path is resolved against the directory the build runs in, and that
# is what decides whether it is part of the book or something else on the
# machine.
func testAPathInsideTheBookIsToldFromOneOutsideIt() {
    def c as config.Config init config.defaults();
    def here as string init path.join(os.cwd(), "plugins/grimoire-sitemap");
    def inside as Resolved init resolved($c, "renderer", specFor("plugins/grimoire-sitemap"));
    testing.assertEqual($inside.path, $here);
    testing.assertEqual($inside.origin, "in this book");
    def outside as Resolved init resolved($c, "renderer", specFor("/bin/sh"));
    testing.assertEqual($outside.path, "/bin/sh");
    testing.assertEqual($outside.origin, "outside this book");
}

func testThePlanIsPreprocessorsThenRenderers() {
    def c as config.Config init config.apply(
        config.defaults(),
        '[book]
title = "T"

[preprocessor.first]
command = "/bin/sh"

[renderer.second]
command = "/bin/sh"
');
    def found as list of Resolved init plan($c);
    testing.assertEqual(len($found), 2);
    testing.assertEqual($found[0].kind, "preprocessor");
    testing.assertEqual($found[0].name, "first");
    testing.assertEqual($found[1].kind, "renderer");
    testing.assertEqual($found[1].name, "second");
}

func testTheListingAlignsAndSaysWhereEachCameFrom() {
    def c as config.Config init config.apply(
        config.defaults(),
        '[book]
title = "T"

[preprocessor.a]
command = "/bin/sh"
args = ["-c", "true"]

[renderer.longer-name]
command = "grimoire-not-installed"
');
    def lines as list of string init listing(plan($c));
    testing.assertEqual(len($lines), 2);
    testing.assertContains(
        $lines[0],
        "preprocessor  a            ->  /bin/sh  (outside this book)");
    testing.assertContains($lines[0], "args: -c true");
    testing.assertContains($lines[1], "renderer      longer-name  ->  grimoire-not-installed");
    testing.assertContains($lines[1], "(not found)");
}

# Shipped and in-book programs are reviewable by reading the repository; the
# other two are what the build says out loud without being asked.
func testOnlyWhatCameFromOutsideTheBookIsWorthAWarning() {
    def c as config.Config init config.apply(
        config.defaults(),
        '[book]
title = "T"

[preprocessor.own]
command = "plugins/grimoire-sitemap"

[preprocessor.borrowed]
command = "/bin/sh"

[renderer.gone]
command = "grimoire-not-installed"
');
    def said as list of string init concerns($c);
    testing.assertEqual(len($said), 2);
    testing.assertContains(
        $said[0],
        "preprocessor borrowed: runs /bin/sh, which is outside this book");
    testing.assertContains(
        $said[1],
        "renderer gone: nothing named grimoire-not-installed was found");
}
