# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.28.0

/**
 * White-box tests for `themefile.j`, run by `jennifer test src/themefile_test.j`.
 *
 * A theme file is the one part of a book's configuration that is strict, so
 * most of these pin a refusal: each names the file and what is wrong with it.
 * @module themefile_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use os;

# A base to extend: every slot a distinct, printable value.
func base() {
    def p as palette.Palette init palette.palette(
        "#ffffff",
        "#f0f0f0",
        "#e0e0e0",
        "#d0d0d0",
        "#111111",
        "#666666",
        "#000000",
        "#0000aa",
        "#000088",
        "#ffffff",
        "#222222",
        "#eeeeee",
        "rgba(0, 0, 170, 0.2)",
        "rgba(0, 0, 0, 0.1)");
    return palette.Theme{
        name: "base",
        label: "Base",
        description: "",
        light: $p,
        dark: $p,
        fontBody: palette.sans(),
        fontHeading: palette.sans(),
        fontMono: palette.mono(),
        radius: 6,
        contentWidth: 780
    };
}

# themeDir writes a theme file, and any other files, into a fresh directory.
func themeDir(files as map of string to string) {
    def dir as string init fs.makeTempDir(os.tempDir(), "grimoire-theme-");
    for (def name in $files) {
        def target as string init path.join($dir, $name);
        fs.mkdirAll(path.dir($target));
        fs.writeString($target, $files[$name]);
    }
    return $dir;
}

# refusal loads a theme file that must be refused and returns the message.
func refusal(toml as string) {
    def dir as string init themeDir({"t.toml": $toml});
    try {
        load(path.join($dir, "t.toml"), base());
    } catch (e) {
        testing.assertEqual($e.kind, "grimoire");
        return $e.message;
    }
    testing.assertTrue(false);
    return "";
}

func testIsFileIsTheExtension() {
    testing.assertTrue(isFile("theme/house.toml"));
    testing.assertFalse(isFile("nordic"));
}

func testColoursAcceptedAndRefused() {
    for (def ok in [
        "#abc",
        "#abcd",
        "#a1b2c3",
        "#a1b2c3d4",
        "rgb(1, 2, 3)",
        "rgba(1,2,3,0.5)",
        "hsl(120deg 50% 50%)",
        "hsla(120, 50%, 50%, 0.3)"
    ]) {
        testing.assertTrue(isColour($ok));
    }
    for (def bad in ["red", "#ab", "#abcdeg", 'rgb(1,2,3); } body { x: y', "url(x)", "", "rgb()"]) {
        testing.assertFalse(isColour($bad));
    }
}

func testAFileOverridesWhatItNamesAndKeepsTheRest() {
    def dir as string init themeDir({
        "house.toml": strings.join(
            [
                'label = "House"',
                "radius = 4",
                "[fonts]",
                "body = '\"Archivo\", sans-serif'",
                "[light]",
                'accent = "#c2410c"',
                "[dark]",
                'bg = "#0c100e"',
                'selection = "rgba(244, 119, 47, 0.2)"'
            ],
            "\n")
    });
    def t as Loaded init load(path.join($dir, "house.toml"), base());
    testing.assertEqual($t.theme.name, "house");
    testing.assertEqual($t.theme.label, "House");
    testing.assertEqual($t.theme.radius, 4);
    testing.assertEqual($t.theme.contentWidth, 780);
    testing.assertEqual($t.theme.fontBody, '"Archivo", sans-serif');
    testing.assertEqual($t.theme.fontMono, palette.mono());
    testing.assertEqual($t.theme.light.accent, "#c2410c");
    testing.assertEqual($t.theme.light.bg, "#ffffff");
    testing.assertEqual($t.theme.dark.bg, "#0c100e");
    testing.assertEqual($t.theme.dark.selection, "rgba(244, 119, 47, 0.2)");
    testing.assertEqual($t.css, "");
    testing.assertEqual($t.files, []);
}

func testAStylesheetAndItsFilesAreRead() {
    def dir as string init themeDir({
        "t.toml": 'stylesheet = "house.css"' + "\n" + 'files = ["fonts/a.woff2"]',
        "house.css": '@font-face { src: url(fonts/a.woff2); }',
        "fonts/a.woff2": "font"
    });
    def t as Loaded init load(path.join($dir, "t.toml"), base());
    testing.assertContains($t.css, "@font-face");
    testing.assertEqual($t.files, ["fonts/a.woff2"]);
    testing.assertEqual($t.dir, $dir);
}

func testAMissingFileIsRefused() {
    try {
        load(path.join(os.tempDir(), "no-such-theme-file.toml"), base());
        testing.assertTrue(false);
    } catch (e) {
        testing.assertContains($e.message, "no such theme file");
    }
}

func testUnknownKeysAreRefused() {
    testing.assertContains(refusal('colour = "x"'), "unknown key colour");
    testing.assertContains(
        refusal("[light]\naccnet = \"#000000\""),
        "unknown key accnet in [light]");
    testing.assertContains(refusal("[fonts]\nserif = \"x\""), "unknown key serif in [fonts]");
}

func testBadValuesAreRefused() {
    testing.assertContains(refusal("[dark]\nbg = \"red\""), "dark.bg is not a colour");
    testing.assertContains(refusal("[dark]\nbg = 3"), "dark.bg must be a colour string");
    testing.assertContains(refusal("radius = 999"), "radius must be from 0 to 64");
    testing.assertContains(refusal('radius = "4"'), "radius must be an integer");
    testing.assertContains(refusal('[fonts]' + "\n" + 'body = "x; } a { b"'), "may not contain");
    testing.assertContains(refusal("[fonts]\nbody = \"\""), "may not be empty");
    testing.assertContains(refusal("this is not toml ["), "not a TOML document");
}

# The printed book reads these slots as #rrggbb; anything else would print grey.
func testPrintedSlotsMustBeSixDigitHex() {
    testing.assertContains(refusal("[light]\naccent = \"#c41\""), "light.accent must be #rrggbb");
    testing.assertContains(
        refusal("[light]\nborder = \"rgba(0, 0, 0, 0.1)\""),
        "light.border must be #rrggbb");
    # The dark palette never prints, so any colour form is fine there.
    def dir as string init themeDir({"t.toml": "[dark]\naccent = \"#c41\""});
    testing.assertEqual(load(path.join($dir, "t.toml"), base()).theme.dark.accent, "#c41");
}

func testPathsMustStayInsideTheThemesDirectory() {
    testing.assertContains(refusal('stylesheet = "../x.css"'), "must be a path inside");
    testing.assertContains(refusal('stylesheet = "/etc/x.css"'), "must be a path inside");
    testing.assertContains(refusal('files = ["../../secret"]'), "must be a path inside");
    testing.assertContains(refusal('stylesheet = "absent.css"'), "is not a file next to the theme");
    testing.assertContains(refusal('files = ["absent.woff2"]'), "is not a file next to the theme");
    testing.assertContains(refusal('files = "a.woff2"'), "files must be a list");
}

func testExtendsIsReadOnItsOwn() {
    def dir as string init themeDir({"t.toml": 'extends = "carbon"', "u.toml": 'label = "U"'});
    testing.assertEqual(extendsOf(path.join($dir, "t.toml")), "carbon");
    testing.assertEqual(extendsOf(path.join($dir, "u.toml")), "");
}
