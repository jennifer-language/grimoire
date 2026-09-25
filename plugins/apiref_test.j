# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `apiref.j`, run by `jennifer test apiref_test.j`.
 *
 * The parsing is `docblock.parse` and is not this plugin's to test. What is
 * tested here is everything around it: which constructs reach the page, what
 * they look like as Markdown, and the two shapes that decide whether a
 * generated chapter is usable at all - a table that is one block rather than
 * six paragraphs, and a heading whose anchor is the name rather than the whole
 * signature.
 * @module apiref_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use os;

# A module on disk, with one documented struct, one exported function, one that
# is not exported, and one function with no doc comment at all.
func sourceTree() {
    def root as string init fs.makeTempDir(os.tempDir(), "apiref-");
    fs.writeString(
        path.join($root, "geo.j"),
        '# SPDX-License-Identifier: LGPL-3.0-only
/**
 * Distances on a plane.
 *
 * Small on purpose.
 * @module geo
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use math;

/**
 * A point.
 * @field x {float} the horizontal coordinate
 * @field y {float} the vertical coordinate
 */
export def struct Point {
    x as float,
    y as float
};

/**
 * Distance between two points.
 * @param a {Point} one point
 * @param b {Point} the other
 * @return {float} the distance
 * @throws {Error} kind "geo" when a coordinate is not finite
 */
export func distance(a as Point, b as Point) {
    return 0.0;
}

/**
 * Doubles a number, and is not exported.
 * @param n {int} the number
 * @return {int} twice it
 */
func helper(n as int) {
    return $n * 2;
}

func undocumented(n as int) {
    return $n;
}
');
    return $root;
}

# --- the pieces ------------------------------------------------------

# The signature is the parameter list a caller writes, rebuilt from what the
# docblock names.
func testTheSignatureIsRebuiltFromTheParameters() {
    def root as string init sourceTree();
    def doc as docblock.FileDoc init docblock.parse(fs.readString(path.join($root, "geo.j")));
    testing.assertEqual(signature($doc.funcs[0]), "distance(a as Point, b as Point)");
    fs.removeAll($root);
}

# One string, not a list of them: every piece this produces is a block and
# blocks are joined with a blank line between, so a table whose rows were blocks
# would render as six paragraphs that happen to contain pipes.
func testATableIsOneBlock() {
    def fields as list of docblock.ParamDoc init [
        docblock.ParamDoc{name: "x", type: "float", description: "across"},
        docblock.ParamDoc{name: "y", type: "float", description: "down"}
    ];
    def out as string init table($fields, "Field");
    testing.assertEqual(len(strings.split($out, "\n")), 4);
    testing.assertFalse(strings.contains($out, "\n\n"));
}

func testAnEmptyTableIsNothing() {
    def none as list of docblock.ParamDoc;
    testing.assertEqual(table($none, "Field"), "");
}

func testHeadingLevelsAreClamped() {
    testing.assertEqual(clamped(1), 2);
    testing.assertEqual(clamped(7), 6);
    testing.assertEqual(clamped(3), 3);
}

# --- a whole tree ----------------------------------------------------

func testTheModuleAndItsExportsReachThePage() {
    def root as string init sourceTree();
    def out as string init reference($root, 2, false);
    testing.assertContains($out, "## `geo`");
    testing.assertContains($out, "Distances on a plane.");
    testing.assertContains($out, "### `Point`");
    testing.assertContains($out, "### `distance`");
    testing.assertContains($out, "| `a` | `Point` | one point |");
    testing.assertContains($out, "**Returns** `float`");
    testing.assertContains($out, "**Throws** `Error`");
    fs.removeAll($root);
}

# The anchor a reader links to is `#distance`, not the whole signature
# slugified. The signature goes underneath, where the highlighter colours it.
func testTheHeadingIsTheBareNameAndTheSignatureIsFenced() {
    def root as string init sourceTree();
    def out as string init reference($root, 2, false);
    testing.assertContains(
        $out,
        "### `distance`\n\n```jennifer\ndistance(a as Point, b as Point)\n```");
    fs.removeAll($root);
}

func testWhatIsNotExportedIsLeftOut() {
    def root as string init sourceTree();
    testing.assertFalse(strings.contains(reference($root, 2, false), "Doubles a number"));
    testing.assertContains(reference($root, 2, true), "Doubles a number");
    fs.removeAll($root);
}

# `docblock.parse` returns what carries a doc comment, so a function with none
# is never listed whatever `private` says.
func testWhatIsUndocumentedIsNeverListed() {
    def root as string init sourceTree();
    testing.assertFalse(strings.contains(reference($root, 2, true), "undocumented"));
    fs.removeAll($root);
}

# A test overlay documents the tests, not the module.
func testTestOverlaysAreSkipped() {
    def root as string init sourceTree();
    fs.writeString(
        path.join($root, "geo_test.j"),
        '/**
 * Tests.
 * @module geotest
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
');
    testing.assertFalse(strings.contains(reference($root, 2, false), "geotest"));
    fs.removeAll($root);
}

func referenceOfNothing() {
    reference(path.join(os.tempDir(), "apiref-no-such-tree"), 2, false);
}

func testAPathWithNoSourcesIsRefused() {
    testing.assertThrows("referenceOfNothing", "plugin");
}

# --- the directive ---------------------------------------------------

func testTheDirectiveExpandsInPlace() {
    def root as string init sourceTree();
    def directive as string init '{{#apiref ' + $root + '}}';
    def out as string init expand("# Reference\n\n" + $directive + "\n\nAfter.", 2, false);
    testing.assertContains($out, "# Reference");
    testing.assertContains($out, "## `geo`");
    testing.assertContains($out, "After.");
    fs.removeAll($root);
}

# A marker inside a sentence is prose about the syntax; one with a backslash in
# front of it is how a book shows the syntax.
func testWhatIsNotADirective() {
    # Raw strings: a cooked one reads `{{` as an interpolation slot.
    def inline as string init 'see {{#apiref src}} inline';
    def escaped as string init '\{{#apiref src}}';
    def out as string init expand($inline + "\n" + $escaped, 2, false);
    testing.assertContains($out, $inline);
    testing.assertContains($out, '{{#apiref src}}');
    testing.assertFalse(strings.contains($out, $escaped));
}

# --- run -------------------------------------------------------------

func testRunRefusesAnEmptyRequest() {
    testing.assertEqual(run(" "), 1);
}

func testRunRefusesARendererRequest() {
    testing.assertEqual(run('{"api":1,"kind":"renderer","chapters":[]}'), 1);
}

func testRunLeavesAChapterWithNoDirectiveAlone() {
    def request as string init '{"api":1,"kind":"preprocessor","plugin":{"name":"apiref",' +
        '"settings":{}},"entries":[],"chapters":[{"src":"a.md","content":"# A\n\nprose\n"}]}';
    testing.assertEqual(run($request), 0);
}
