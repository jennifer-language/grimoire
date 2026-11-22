# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.27.0

/**
 * White-box tests for `pluginkit.j`, run by `jennifer test src/pluginkit_test.j`.
 *
 * The fence scanner gets the most cases, because every plugin that leaves code
 * alone leans on it and a wrong answer rewrites an example a page meant to
 * show. The cases follow the CommonMark spec's section on fenced code blocks.
 * @module pluginkit_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;

# --- fences: openers --------------------------------------------------

func testBackticksAndTildesOpenAFence() {
    testing.assertEqual(openerOf("```").size, 3);
    testing.assertEqual(openerOf("```").mark, "`");
    testing.assertEqual(openerOf("~~~~~").size, 5);
    testing.assertEqual(openerOf("~~~~~").mark, "~");
    testing.assertEqual(openerOf("``").size, 0);
    testing.assertEqual(openerOf("~~").size, 0);
    testing.assertEqual(openerOf("text").size, 0);
    testing.assertEqual(openerOf("").size, 0);
}

# Up to three columns of indentation; four is indented code.
func testAnOpenerMayBeIndentedThreeColumns() {
    testing.assertEqual(openerOf("   ```").width, 3);
    testing.assertEqual(openerOf("   ```").indent, "   ");
    testing.assertEqual(openerOf("    ```").size, 0);
    testing.assertEqual(openerOf("\t```").size, 0);
    # A tab after a space still reaches column four.
    testing.assertEqual(openerOf(" \t```").size, 0);
}

func testTheInfoStringIsTrimmed() {
    testing.assertEqual(openerOf("```  mermaid title  ").info, "mermaid title");
    testing.assertEqual(languageOf("mermaid title"), "mermaid");
    testing.assertEqual(languageOf("  rust\tlinenos"), "rust");
    testing.assertEqual(languageOf(""), "");
}

# After backticks the info string may not hold a backtick: such a line is an
# inline code span. After tildes it may.
func testABacktickInABacktickInfoStringIsNoFence() {
    testing.assertEqual(openerOf("``` aa `").size, 0);
    testing.assertEqual(openerOf("~~~ aa ` ~~~").size, 3);
    testing.assertEqual(openerOf("~~~ aa ` ~~~").info, "aa ` ~~~");
}

# --- fences: closers --------------------------------------------------

func testACloserIsAtLeastAsLongAndTheSameCharacter() {
    def open as Fence init openerOf("````");
    testing.assertTrue(closes("````", $open));
    testing.assertTrue(closes("``````", $open));
    testing.assertFalse(closes("```", $open));
    testing.assertFalse(closes("~~~~", $open));
}

# A closer takes no info string, and at most three columns of indentation.
func testACloserCarriesNothingButSpaces() {
    def open as Fence init openerOf("```");
    testing.assertTrue(closes("```   ", $open));
    testing.assertTrue(closes("   ```", $open));
    testing.assertFalse(closes("``` js", $open));
    testing.assertFalse(closes("    ```", $open));
    testing.assertFalse(closes("``` ```", $open));
}

# --- fences: blocks ---------------------------------------------------

func testAFenceIsFoundWithItsBody() {
    def found as list of Fence init fencesIn("text\n\n```sh\nls\npwd\n```\nafter\n");
    testing.assertEqual(len($found), 1);
    testing.assertEqual($found[0].first, 2);
    testing.assertEqual($found[0].last, 5);
    testing.assertTrue($found[0].closed);
    testing.assertEqual($found[0].info, "sh");
    testing.assertEqual($found[0].body, "ls\npwd\n");
}

# A shorter run, or the other character, is content.
func testAFenceInsideALongerOneIsContent() {
    def found as list of Fence init fencesIn("````md\n```js\nx\n```\n````\n\n~~~\n```\n~~~\n");
    testing.assertEqual(len($found), 2);
    testing.assertEqual($found[0].body, "```js\nx\n```\n");
    testing.assertEqual($found[1].body, "```\n");
}

# A fence that is never closed runs to the end of the chapter.
func testAnUnclosedFenceRunsToTheEnd() {
    def found as list of Fence init fencesIn("```\naaa\n\n```js\nbbb\n");
    testing.assertEqual(len($found), 1);
    testing.assertFalse($found[0].closed);
    testing.assertEqual($found[0].last, 5);
    testing.assertEqual($found[0].body, "aaa\n\n```js\nbbb\n\n");
}

# An indented fence takes up to its own indentation off each content line, and
# no more.
func testAnIndentedFenceTakesItsIndentationOff() {
    def found as list of Fence init fencesIn("  ```\n  aaa\naaa\n     aaa\n  ```\n");
    testing.assertEqual($found[0].body, "aaa\naaa\n   aaa\n");
    testing.assertEqual($found[0].indent, "  ");
}

func testAnEmptyFenceHasAnEmptyBody() {
    def found as list of Fence init fencesIn("```\n```\n");
    testing.assertEqual(len($found), 1);
    testing.assertEqual($found[0].body, "");
}

# Indented code is never a fence, so a fence written inside it is not found.
func testIndentedCodeIsNoFence() {
    testing.assertEqual(len(fencesIn("    ```\n    x\n    ```\n")), 0);
}

func testCrlfLinesAreRead() {
    def found as list of Fence init fencesIn("```mermaid\r\ngraph\r\n```\r\n");
    testing.assertEqual(len($found), 1);
    testing.assertTrue($found[0].closed);
    testing.assertEqual($found[0].info, "mermaid");
    testing.assertEqual($found[0].body, "graph\n");
}

func testSeveralFencesAreFoundInOrder() {
    def found as list of Fence init fencesIn("```a\n1\n```\n\ntext\n\n~~~b\n2\n~~~\n");
    testing.assertEqual(len($found), 2);
    testing.assertEqual($found[0].info, "a");
    testing.assertEqual($found[1].info, "b");
    testing.assertEqual($found[1].first, 6);
}

func testFencedLinesMarkTheFencesAndTheirContent() {
    def marks as list of bool init fencedLines("a\n```\nb\n```\nc");
    testing.assertEqual(len($marks), 5);
    testing.assertFalse($marks[0]);
    testing.assertTrue($marks[1]);
    testing.assertTrue($marks[2]);
    testing.assertTrue($marks[3]);
    testing.assertFalse($marks[4]);
    # Unclosed: everything after the opener.
    def open as list of bool init fencedLines("a\n~~~\nb");
    testing.assertFalse($open[0]);
    testing.assertTrue($open[2]);
}

# --- the contract -----------------------------------------------------

def const GOOD as string init '{"api":1,"kind":"preprocessor","book":{},"chapters":[]}';

func emptyRequest() {
    request("  ", "preprocessor");
}

func emptyObject() {
    request('{}', "preprocessor");
}

func notAnObject() {
    request("[1, 2]", "preprocessor");
}

func notJson() {
    request("api=1", "preprocessor");
}

func apiAsText() {
    request(strings.replace(GOOD, '"api":1', '"api":"1"'), "preprocessor");
}

func noKind() {
    request(strings.replace(GOOD, '"kind":"preprocessor",', ""), "preprocessor");
}

func testAMalformedRequestIsThePluginsError() {
    testing.assertThrows("emptyObject", "plugin");
    testing.assertThrows("notAnObject", "plugin");
    testing.assertThrows("notJson", "plugin");
    testing.assertThrows("apiAsText", "plugin");
    testing.assertThrows("noKind", "plugin");
}

func otherApi() {
    request(strings.replace(GOOD, '"api":1', '"api":2'), "preprocessor");
}

func otherKind() {
    request(GOOD, "renderer");
}

func testARequestIsCheckedBeforeItIsUsed() {
    testing.assertEqual(json.asInt(request(GOOD, "preprocessor"), "/api"), 1);
    testing.assertThrows("emptyRequest", "plugin");
    testing.assertThrows("otherApi", "plugin");
    testing.assertThrows("otherKind", "plugin");
    try {
        otherKind();
    } catch (e) {
        testing.assertEqual($e.message, "this is a renderer; the request asks for a preprocessor");
    }
    try {
        otherApi();
    } catch (e) {
        testing.assertEqual($e.message, "this plugin speaks api 1, the request speaks 2");
    }
}

func testFeaturesAreReadFromTheRequest() {
    testing.assertFalse(hasFeature(json.decode(GOOD), "files"));
    testing.assertTrue(hasFeature(json.decode('{"features":["x","files"]}'), "files"));
    testing.assertFalse(hasFeature(json.decode('{"features":"files"}'), "files"));
}

func filesMissing() {
    requireFiles(json.decode(GOOD));
}

func testRequireFilesNamesTheGrimoireThatHasThem() {
    testing.assertThrows("filesMissing", "plugin");
    try {
        filesMissing();
    } catch (e) {
        testing.assertContains($e.message, "Grimoire 0.5.0");
    }
    def dir as string init fs.makeTempDir(os.tempDir(), "pluginkit-");
    def req as json.Value init json.decode(
        '{"features":["files"],"plugin":{"files":' + json.encode($dir) + '}}');
    testing.assertEqual(requireFiles($req), $dir);
    fs.removeAll($dir);
}

func mathmlMissing() {
    requireFeature(json.decode('{"features":["files"]}'), "mathml");
}

# Every feature names the Grimoire that first offered it, so a plugin built for
# MathML refuses an older Grimoire with the version to upgrade to.
func testRequireFeatureNamesTheGrimoireThatHasIt() {
    testing.assertEqual(features(), ["files", "mathml"]);
    requireFeature(json.decode('{"features":["files","mathml"]}'), "mathml");
    testing.assertThrows("mathmlMissing", "plugin");
    try {
        mathmlMissing();
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "this plugin needs Grimoire 0.5.0 or later, whose requests offer the `mathml` " +
                "feature; this one does not");
    }
}

func testRepliesAreTheContractsShape() {
    testing.assertEqual(
        preprocessorReply([chapterReply("a.md", "x\n")]),
        '{"api":1,"chapters":[{"src":"a.md","content":"x\n"}]}');
    testing.assertEqual(preprocessorReply([]), '{"api":1,"chapters":[]}');
    testing.assertEqual(rendererReply(["a.xml"], []), '{"api":1,"written":["a.xml"]}');
    testing.assertEqual(rendererReply([], ["w"]), '{"api":1,"warnings":["w"]}');
    testing.assertEqual(rendererReply([], []), '{"api":1}');
}

# --- errors -----------------------------------------------------------

func testAPlaceGoesIntoTheMessageAndTheFields() {
    try {
        failAt("plugin", "guide/a.md", 12, "broken");
    } catch (e) {
        testing.assertEqual($e.kind, "plugin");
        testing.assertEqual($e.message, "guide/a.md:12: broken");
        testing.assertEqual($e.file, "guide/a.md");
        testing.assertEqual($e.line, 12);
    }
    try {
        limit("over 10 bytes");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
    }
}

# --- settings ---------------------------------------------------------

func withSettings(settings as string) {
    return json.decode('{"plugin":{"name":"p","settings":' + $settings + '}}');
}

func testTypedSettingsAndTheirFallbacks() {
    def req as json.Value init withSettings(
        '{"s":"x","b":true,"i":3,"f":1.5,"n":2,"l":["a","b"],"a/b":"slash"}');
    testing.assertEqual(settingText($req, "s", "d"), "x");
    testing.assertEqual(settingText($req, "missing", "d"), "d");
    testing.assertTrue(settingBool($req, "b", false));
    testing.assertEqual(settingInt($req, "i", 0), 3);
    testing.assertEqual(settingNumber($req, "f", 0.0), 1.5);
    testing.assertEqual(settingNumber($req, "n", 0.0), 2.0);
    testing.assertEqual(settingTexts($req, "l", []), ["a", "b"]);
    testing.assertEqual(settingText($req, "a/b", ""), "slash");
    testing.assertTrue(hasSetting($req, "i"));
    testing.assertFalse(hasSetting($req, "z"));
}

func wrongSettingType() {
    settingBool(withSettings('{"b":"yes"}'), "b", false);
}

func unknownSetting() {
    checkSettings(withSettings('{"them":"dark","command":"x","args":[]}'), ["theme"]);
}

func testABadSettingIsRefused() {
    testing.assertThrows("wrongSettingType", "plugin");
    try {
        wrongSettingType();
    } catch (e) {
        testing.assertEqual($e.message, "setting `b` must be true or false, not string");
    }
    testing.assertThrows("unknownSetting", "plugin");
    try {
        unknownSetting();
    } catch (e) {
        testing.assertEqual($e.message, "unknown setting `them`; the settings are theme");
    }
}

# Grimoire's own keys are always allowed, and never listed as the plugin's.
func testGrimoiresKeysAreItsOwn() {
    def req as json.Value init withSettings('{"command":"x","args":[],"theme":"d"}');
    checkSettings($req, ["theme"]);
    testing.assertEqual(settingKeys($req), ["theme"]);
    testing.assertEqual(reservedKeys(), ["command", "args"]);
    testing.assertEqual(len(settingKeys(json.decode('{"plugin":{}}'))), 0);
}

func testAPointerKeyEscapesItsSeparators() {
    testing.assertEqual(pointerKey("a/b~c"), "a~1b~0c");
}

# --- generated files and names ----------------------------------------

func testALinkIsRelativeToItsChapter() {
    testing.assertEqual(
        generatedLink("index.md", "mermaid", "ab.svg"),
        "_generated/mermaid/ab.svg");
    testing.assertEqual(
        generatedLink("a/b/c.md", "diagrams", "ab.svg"),
        "../../_generated/diagrams/ab.svg");
    testing.assertEqual(generatedName(), "_generated");
}

func testAContentNameFollowsItsParts() {
    def name as string init contentName(["a", "b"], 16);
    testing.assertEqual(len($name), 16);
    testing.assertEqual(contentName(["a", "b"], 16), $name);
    testing.assertNotEqual(contentName(["a", "c"], 16), $name);
    # The parts are joined by newlines, so their boundaries count.
    testing.assertNotEqual(contentName(["ab"], 16), contentName(["a", "b"], 16));
    testing.assertEqual(
        contentName(["abc"], 64),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
}

func tooManyDigits() {
    contentName(["a"], 65);
}

func testAContentNameHasAtMost64Digits() {
    testing.assertThrows("tooManyDigits", "plugin");
}

# --- other programs ---------------------------------------------------

func testARunGivesItsFirstMessageLine() {
    def ok as Ran init runProgram(["sh", "-c", "cat"], "in\n");
    testing.assertTrue($ok.started);
    testing.assertEqual($ok.stdout, "in\n");
    testing.assertEqual($ok.message, "");
    def bad as Ran init runProgram(
        [
            "sh",
            "-c",
            "echo; echo '  first  ' >&2; echo second >&2; exit 3"
        ],
        "");
    testing.assertEqual($bad.exitCode, 3);
    testing.assertEqual($bad.message, "first");
    def quiet as Ran init runProgram(["sh", "-c", "exit 4"], "");
    testing.assertEqual($quiet.message, "exited 4");
    def missing as Ran init runProgram(["pluginkit-no-such-program"], "");
    testing.assertFalse($missing.started);
    testing.assertNotEqual($missing.message, "");
}

func testAMissingProgramSaysWhatToDo() {
    testing.assertEqual(
        missingProgram("merman-cli", "not found", "merman-cli", "program"),
        "cannot run merman-cli (not found); install merman-cli, or set `program` to where it is");
    testing.assertNotEqual(onPath("sh"), "");
    testing.assertEqual(onPath("pluginkit-no-such-program"), "");
}

# --- bounded concurrent work ------------------------------------------

# A worker: the item's text, after sleeping its `wait` in milliseconds; an item
# with `fail` throws, with a place in the book.
func echoItem(context as json.Value, item as json.Value) {
    if (json.has($item, "/wait")) {
        os.run(["sleep", json.asString($item, "/wait")]);
    }
    if (json.has($item, "/fail")) {
        failAt(
            json.asString($context, "/kind"),
            json.asString($item, "/fail"),
            json.asInt($item, "/line"),
            "failed");
    }
    return json.asString($context, "/prefix") + json.asString($item, "/text");
}

func items(texts as list of string) {
    def out as list of json.Value;
    for (def t in $texts) {
        $out[] = json.decode('{"text":' + json.encode($t) + '}');
    }
    return $out;
}

func testWorkReturnsResultsInItemOrder() {
    def ctx as json.Value init json.decode('{"prefix":"> ","kind":"plugin"}');
    def list1 as list of json.Value init items(["a", "b", "c", "d", "e"]);
    $list1[0] = json.decode('{"text":"a","wait":"0.3"}');
    for (def jobs in [1, 2, 0]) {
        testing.assertEqual(
            work($jobs, echoItem, $ctx, $list1),
            ["> a", "> b", "> c", "> d", "> e"]);
    }
    testing.assertEqual(len(work(4, echoItem, $ctx, [])), 0);
}

func failingWork() {
    def ctx as json.Value init json.decode('{"prefix":"","kind":"limit"}');
    work(
        2,
        echoItem,
        $ctx,
        [
            json.decode('{"text":"a","fail":"one.md","line":3,"wait":"0.3"}'),
            json.decode('{"text":"b","fail":"two.md","line":9}')
        ]);
}

# The first failure in item order is the one reported, whichever task met its
# own first, with its kind and its place kept.
func testWorkReportsTheFirstFailureInItemOrder() {
    testing.assertThrows("failingWork", "limit");
    try {
        failingWork();
    } catch (e) {
        testing.assertEqual($e.message, "one.md:3: failed");
        testing.assertEqual($e.file, "one.md");
        testing.assertEqual($e.line, 3);
    }
}
