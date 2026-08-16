# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `main.j`, run by `jennifer test src/main_test.j`.
 *
 * The command line is the one part of Grimoire with no other test: a flag that
 * stops being wired to its configuration field still parses, still builds, and
 * simply does nothing. So most of what is below runs a real argument vector
 * through `parser` and `configure` and then asserts on the `Config` that comes
 * out - which is exactly the join that goes quiet when it breaks.
 *
 * `run` itself appears only where its exit status is the contract: the status is
 * what CI and `makepkg` read.
 *
 * A few of these print to stdout or stderr as they go. That is the code under
 * test doing its job, not a test misbehaving.
 * @module main_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use fs;
use os;
use path;
use strings;

# One command line, parsed and resolved the way `dispatch` would resolve it.
func resolve(argv as list of string) {
    return configure(args.parse(parser(), $argv), ".");
}

func buildArgs(rest as list of string) {
    def argv as list of string init ["grimoire", "build"];
    for (def a in $rest) {
        $argv[] = $a;
    }
    return $argv;
}

# --- the parser is complete ------------------------------------------

func testEveryCommandIsRegistered() {
    def usage as string init args.usage(parser());
    testing.assertContains($usage, "build");
    testing.assertContains($usage, "pdf");
    testing.assertContains($usage, "serve");
    testing.assertContains($usage, "themes");
    testing.assertContains($usage, "init");
}

func testBuildTakesEveryFlagItDocuments() {
    def usage as string init args.usage(buildParser());
    for (def flag in [
        "--config",
        "--src",
        "--out",
        "--theme",
        "--mode",
        "--nav",
        "--toc",
        "--clean",
        "--no-clean",
        "--raw-html",
        "--no-raw-html",
        "--title-url",
        "--pdf",
        "--no-search",
        "--jobs",
        "--verbose",
        "--quiet",
        "--ui-language"
    ]) {
        testing.assertContains($usage, $flag);
    }
}

func testServeTakesItsOwnFlags() {
    def usage as string init args.usage(serveParser());
    for (def flag in [
        "--addr",
        "--watch",
        "--no-reload",
        "--no-build",
        "--nav",
        "--toc",
        "--clean",
        "--no-clean",
        "--raw-html",
        "--no-raw-html",
        "--title-url"
    ]) {
        testing.assertContains($usage, $flag);
    }
}

# The printed book has no chrome, so neither the interface language nor the
# column placement means anything to `pdf`.
func testPdfTakesNoChromeFlags() {
    def usage as string init args.usage(pdfParser());
    testing.assertContains($usage, "--paper");
    testing.assertContains($usage, "--output");
    testing.assertFalse(strings.contains($usage, "--nav"));
    testing.assertFalse(strings.contains($usage, "--ui-language"));
}

# --- configure: a flag always wins over the file ---------------------

func testConfigureStartsFromTheDefaults() {
    def c as config.Config init resolve(buildArgs(["--config", "no-such-file.toml"]));
    testing.assertEqual($c.srcDir, "docs");
    testing.assertEqual($c.outDir, "site");
    testing.assertEqual($c.theme, "grimoire");
}

func testFlagsOverrideTheFile() {
    def dir as string init fs.makeTempDir(os.tempDir(), "grimoire-main-");
    def file as string init path.join($dir, "grimoire.toml");
    fs.writeString($file, '[book]
src = "from-file"

[html]
theme = "nordic"
');
    def c as config.Config init resolve(buildArgs(["--config", $file]));
    testing.assertEqual($c.srcDir, "from-file");
    testing.assertEqual($c.theme, "nordic");
    def overridden as config.Config init resolve(buildArgs([
        "--config",
        $file,
        "--src",
        "from-flag",
        "--theme",
        "ember"
    ]));
    testing.assertEqual($overridden.srcDir, "from-flag");
    testing.assertEqual($overridden.theme, "ember");
    fs.removeAll($dir);
}

# Each of these is a flag wired to a field. A rewiring that broke one would still
# parse and still build.
func testEveryBuildFlagReachesItsField() {
    def c as config.Config init resolve(buildArgs([
        "--config",
        "no-such-file.toml",
        "--src",
        "chapters",
        "--out",
        "public",
        "--theme",
        "sepia",
        "--mode",
        "dark",
        "--nav",
        "right",
        "--toc",
        "off",
        "--jobs",
        "6",
        "--ui-language",
        "de",
        "--pdf",
        "--clean",
        "--no-search",
        "--verbose"
    ]));
    testing.assertTrue($c.clean);
    testing.assertEqual($c.srcDir, "chapters");
    testing.assertEqual($c.outDir, "public");
    testing.assertEqual($c.theme, "sepia");
    testing.assertEqual($c.defaultMode, "dark");
    testing.assertEqual($c.navPosition, "right");
    testing.assertEqual($c.tocPosition, "off");
    testing.assertEqual($c.jobs, 6);
    testing.assertEqual($c.uiLanguage, "de");
    testing.assertTrue($c.pdf);
    testing.assertFalse($c.search);
    testing.assertTrue($c.verbose);
    locale.install("en");
}

func testThePdfFlagsReachTheirFields() {
    def argv as list of string init [
        "grimoire",
        "pdf",
        "--config",
        "no-such-file.toml",
        "--output",
        "manual.pdf",
        "--paper",
        "letter"
    ];
    def c as config.Config init resolve($argv);
    testing.assertEqual($c.pdfOutput, "manual.pdf");
    testing.assertEqual($c.pdfPaper, "letter");
}

# The two together are a mistake, and the reading that deletes nothing is the one
# to take when it is not clear which was meant.
func testNoCleanWinsOverClean() {
    def both as config.Config init resolve(buildArgs([
        "--config",
        "no-such-file.toml",
        "--clean",
        "--no-clean"
    ]));
    testing.assertFalse($both.clean);
}

# A book that turns pruning on in `grimoire.toml` still needs a way to say "not
# this time" that is not editing the file.
func testNoCleanOverridesTheConfiguration() {
    def dir as string init fs.makeTempDir(os.tempDir(), "grimoire-clean-");
    def file as string init path.join($dir, "grimoire.toml");
    fs.writeString($file, '[build]
clean = true
');
    testing.assertTrue(resolve(buildArgs(["--config", $file])).clean);
    testing.assertFalse(resolve(buildArgs(["--config", $file, "--no-clean"])).clean);
    fs.removeAll($dir);
}

# `serve` writes an output directory too, and a stale preview is exactly when a
# clean one is wanted. Only its first build prunes; `watch.j` sees to the rest.
func testTheCleanFlagsReachServe() {
    def argv as list of string init [
        "grimoire",
        "serve",
        "--config",
        "no-such-file.toml",
        "--clean"
    ];
    testing.assertTrue(resolve($argv).clean);
}

# Not on `pdf`: it writes one file into the output directory and reads nothing
# else there, so emptying it would be a side effect of an unrelated command.
func testThePdfCommandTakesNoCleanFlag() {
    testing.assertFalse(strings.contains(args.usage(pdfParser()), "--clean"));
}

# The same pair shape as `--clean`, and the same precedence: when both are given
# the reading that escapes wins, because escaping shows the markup and the other
# way runs it.
func testNoRawHtmlWinsOverRawHtml() {
    def both as config.Config init resolve(buildArgs([
        "--config",
        "no-such-file.toml",
        "--raw-html",
        "--no-raw-html"
    ]));
    testing.assertFalse($both.rawHtml);
}

func testTheRawHtmlFlagsReachTheirField() {
    def off as list of string init ["--config", "no-such-file.toml", "--no-raw-html"];
    testing.assertTrue(resolve(buildArgs(["--config", "no-such-file.toml"])).rawHtml);
    testing.assertFalse(resolve(buildArgs($off)).rawHtml);
    def serveArgv as list of string init [
        "grimoire",
        "serve",
        "--config",
        "no-such-file.toml",
        "--no-raw-html"
    ];
    testing.assertFalse(resolve($serveArgv).rawHtml);
}

# --- where the title links -------------------------------------------

func testTheTitleUrlFlagReachesItsField() {
    def argv as list of string init [
        "--config",
        "no-such-file.toml",
        "--title-url",
        "https://example.com/"
    ];
    testing.assertEqual(resolve(buildArgs($argv)).titleUrl, "https://example.com/");
    testing.assertEqual(resolve(buildArgs(["--config", "no-such-file.toml"])).titleUrl, "");
}

func testTheTitleUrlFlagReachesServe() {
    def argv as list of string init [
        "grimoire",
        "serve",
        "--config",
        "no-such-file.toml",
        "--title-url",
        "/"
    ];
    testing.assertEqual(resolve($argv).titleUrl, "/");
}

# An empty value is a value, not an absent flag: it is how a run puts the link
# back to the book's own landing page when the file says otherwise. The `args`
# module has to distinguish the two for that to work, so this pins it.
func testAnEmptyTitleUrlFlagResetsTheConfiguredOne() {
    def dir as string init fs.makeTempDir(os.tempDir(), "grimoire-titleurl-");
    def file as string init path.join($dir, "grimoire.toml");
    fs.writeString($file, '[html]
titleUrl = "https://from-file.example/"
');
    testing.assertEqual(
        resolve(buildArgs(["--config", $file])).titleUrl,
        "https://from-file.example/");
    testing.assertEqual(resolve(buildArgs(["--config", $file, "--title-url", ""])).titleUrl, "");
    fs.removeAll($dir);
}

# A book that turns it off in `grimoire.toml` still needs a way to say "not this
# time" that is not editing the file.
func testRawHtmlOverridesTheConfiguration() {
    def dir as string init fs.makeTempDir(os.tempDir(), "grimoire-rawhtml-");
    def file as string init path.join($dir, "grimoire.toml");
    fs.writeString($file, '[html]
rawHtml = false
');
    testing.assertFalse(resolve(buildArgs(["--config", $file])).rawHtml);
    testing.assertTrue(resolve(buildArgs(["--config", $file, "--raw-html"])).rawHtml);
    fs.removeAll($dir);
}

func testEntryCountReadsAsEnglish() {
    testing.assertEqual(entryCount(0), "0 entries");
    testing.assertEqual(entryCount(1), "1 entry");
    testing.assertEqual(entryCount(14), "14 entries");
}

# Trying an arrangement is what `serve --watch` is for, so it takes them too.
func testTheColumnFlagsReachServe() {
    def argv as list of string init [
        "grimoire",
        "serve",
        "--config",
        "no-such-file.toml",
        "--nav",
        "off",
        "--toc",
        "left"
    ];
    def c as config.Config init resolve($argv);
    testing.assertEqual($c.navPosition, "off");
    testing.assertEqual($c.tocPosition, "left");
}

# `configure` is also where the interface language is selected, at the one point
# where the configuration is finished and nothing has rendered yet.
func testConfigureInstallsTheInterfaceLanguage() {
    resolve(buildArgs(["--config", "no-such-file.toml", "--ui-language", "fr"]));
    testing.assertEqual(locale.tr("search"), "Rechercher");
    resolve(buildArgs(["--config", "no-such-file.toml", "--ui-language", "en"]));
    testing.assertEqual(locale.tr("search"), "Search");
}

# --- position --------------------------------------------------------

# A `grimoire.toml` key of the wrong shape quietly keeps the default, which is
# right for a file that may be half written. A flag was typed just now, by
# someone watching, so it says so before falling back.
func testAMistypedPositionFallsBackToTheDefault() {
    def c as config.Config init resolve(buildArgs([
        "--config",
        "no-such-file.toml",
        "--nav",
        "sideways",
        "--toc",
        "middle"
    ]));
    testing.assertEqual($c.navPosition, "left");
    testing.assertEqual($c.tocPosition, "right");
}

func testPositionAcceptsAllThree() {
    for (def where in ["left", "right", "off"]) {
        def c as config.Config init resolve(buildArgs([
            "--config",
            "no-such-file.toml",
            "--nav",
            $where
        ]));
        testing.assertEqual($c.navPosition, $where);
    }
}

# --- humanBytes ------------------------------------------------------

func testHumanBytesUsesBytesBelowAKibibyte() {
    testing.assertEqual(humanBytes(0), "0 B");
    testing.assertEqual(humanBytes(999), "999 B");
    testing.assertEqual(humanBytes(1023), "1023 B");
}

func testHumanBytesUsesWholeKibibytes() {
    testing.assertEqual(humanBytes(1024), "1 KiB");
    testing.assertEqual(humanBytes(1536), "1 KiB");
    testing.assertEqual(humanBytes(1024 * 1023), "1023 KiB");
}

# One decimal at this scale: a 1.9 MiB PDF reported as "1 MiB" reads as a bug.
func testHumanBytesKeepsOneDecimalForMebibytes() {
    testing.assertEqual(humanBytes(1024 * 1024), "1.0 MiB");
    testing.assertEqual(humanBytes(1024 * 1024 * 2 - 1024 * 100), "1.9 MiB");
    testing.assertEqual(humanBytes(1024 * 1024 * 12), "12.0 MiB");
}

# --- writeIfAbsent ---------------------------------------------------

# `init` on an existing directory fills the gaps and leaves everything already
# written alone.
func testWriteIfAbsentNeverClobbers() {
    def dir as string init fs.makeTempDir(os.tempDir(), "grimoire-init-");
    def file as string init path.join($dir, "kept.md");
    testing.assertTrue(writeIfAbsent($file, "first"));
    testing.assertFalse(writeIfAbsent($file, "second"));
    testing.assertEqual(fs.readString($file), "first");
    fs.removeAll($dir);
}

func testWriteIfAbsentCreatesParentDirectories() {
    def dir as string init fs.makeTempDir(os.tempDir(), "grimoire-init-");
    def file as string init path.join($dir, "deep/nested/x.md");
    testing.assertTrue(writeIfAbsent($file, "body"));
    testing.assertTrue(fs.isFile($file));
    fs.removeAll($dir);
}

# --- the starter book ------------------------------------------------

# `init` writes the book that the rest of the documentation tells a reader to
# build, so it has to be a book Grimoire can actually build.
func testTheStarterBookIsCoherent() {
    testing.assertContains(STARTER_CONFIG, "[book]");
    testing.assertContains(STARTER_CONFIG, "[html]");
    testing.assertContains(STARTER_CONFIG, "navPosition");
    testing.assertContains(STARTER_SUMMARY, "getting-started/installation.md");
    testing.assertContains(STARTER_SUMMARY, "getting-started/first-steps.md");
    testing.assertContains(STARTER_SUMMARY, "index.md");
}

func testTheStarterConfigParses() {
    def c as config.Config init config.apply(config.defaults(), STARTER_CONFIG);
    testing.assertEqual($c.title, "My Book");
    testing.assertEqual($c.srcDir, "docs");
    testing.assertEqual($c.navPosition, "left");
    testing.assertEqual($c.tocPosition, "right");
}

# The starter outline names four chapters and `init` writes three files plus the
# summary; every entry has to have a file behind it or a fresh book warns on its
# very first build.
func testTheStarterOutlineResolves() {
    def dir as string init fs.makeTempDir(os.tempDir(), "grimoire-starter-");
    fs.writeString(path.join($dir, "grimoire.toml"), STARTER_CONFIG);
    fs.mkdirAll(path.join($dir, "docs/getting-started"));
    fs.writeString(path.join($dir, "docs/SUMMARY.md"), STARTER_SUMMARY);
    fs.writeString(path.join($dir, "docs/index.md"), STARTER_INDEX);
    fs.writeString(path.join($dir, "docs/getting-started/installation.md"), STARTER_INSTALL);
    fs.writeString(path.join($dir, "docs/getting-started/first-steps.md"), STARTER_FIRST);
    def c as config.Config init config.apply(config.defaults(), STARTER_CONFIG);
    $c.srcDir = path.join($dir, "docs");
    def entries as list of summary.Entry init summary.load($c.srcDir);
    testing.assertEqual(len(build.resolvedPages($c, $entries)), len(summary.pages($entries)));
    fs.removeAll($dir);
}

# --- run: the exit status is the contract ----------------------------

func testVersionAndHelpSucceed() {
    testing.assertEqual(run(".", ["grimoire", "--version"]), 0);
    testing.assertEqual(run(".", ["grimoire", "build", "--help"]), 0);
}

# Two different failures with two different statuses, and the difference is worth
# keeping: a name that is not a command is an argument error that `args` raises
# and `run` reports as 1, while invoking Grimoire with nothing at all falls
# through `dispatch` to the usage text and 2. Neither may succeed.
func testAnUnknownCommandIsAnArgumentError() {
    testing.assertEqual(run(".", ["grimoire", "nosuchcommand"]), 1);
}

func testNoCommandAtAllPrintsUsage() {
    testing.assertEqual(run(".", ["grimoire"]), 2);
}

# A missing source directory is a diagnostic and a non-zero status, not a
# traceback.
func testAMissingSourceDirectoryFailsCleanly() {
    def argv as list of string init [
        "grimoire",
        "pdf",
        "--config",
        "no-such-file.toml",
        "--src",
        "no-such-directory"
    ];
    testing.assertEqual(run(".", $argv), 1);
}
