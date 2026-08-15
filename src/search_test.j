# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `search.j`, run by `jennifer test src/search_test.j`.
 *
 * Two things here are contracts with code that lives outside Jennifer: the
 * record is a positional array whose field order `assets/grimoire.js` reads by
 * index, and the index is a script that assigns a global rather than JSON to be
 * fetched, so search keeps working on a site opened over `file://`. Both are
 * invisible from this side and both are asserted below.
 * @module search_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use strings;
use json;

func sample() {
    return record("guide/x.html", "A page", "A section", "a-section", "Some body text.", 1200);
}

# The prefix the index script assigns through, and what has to come off the front
# to get at the JSON underneath it. The tail is the `;` and the newline.
def const ASSIGN as string init "window.grimoireIndex = ";

func decodeIndex(js as string) {
    return json.decode(strings.substring($js, len(ASSIGN), len($js) - 2));
}

# --- record ----------------------------------------------------------

func testRecordKeepsItsFields() {
    def r as Record init sample();
    testing.assertEqual($r.path, "guide/x.html");
    testing.assertEqual($r.title, "A page");
    testing.assertEqual($r.heading, "A section");
    testing.assertEqual($r.anchor, "a-section");
    testing.assertEqual($r.body, "Some body text.");
}

func testRecordSqueezesTheBody() {
    def r as Record init record("p.html", "T", "H", "h", "  ragged\n\ntext\there  ", 1200);
    testing.assertEqual($r.body, "ragged text here");
}

# A single enormous section must not dominate the index, which is what the
# budget is for.
func testRecordTruncatesTheBody() {
    def r as Record init record("p.html", "T", "H", "h", "one two three four five", 12);
    testing.assertTrue(len($r.body) <= 12);
    testing.assertEqual($r.body, "one two");
}

func testRecordAcceptsAPageLeadIn() {
    def r as Record init record("p.html", "T", "", "", "lead-in", 1200);
    testing.assertEqual($r.heading, "");
    testing.assertEqual($r.anchor, "");
}

# --- script ----------------------------------------------------------

# A global assignment rather than JSON on the wire: this is what lets a built
# site search when it was opened straight off the disk.
func testScriptAssignsAGlobal() {
    def js as string init script([sample()]);
    testing.assertTrue(strings.startsWith($js, "window.grimoireIndex = "));
    testing.assertContains($js, '"docs"');
    testing.assertTrue(strings.endsWith($js, "\n"));
}

# The field order is a contract with `assets/grimoire.js`, which reads these by
# index. Changing it here silently breaks every search result.
func testScriptWritesFieldsInTheOrderTheClientReads() {
    def decoded as json.Value init decodeIndex(script([sample()]));
    testing.assertEqual(json.asString($decoded, "/docs/0/0"), "guide/x.html");
    testing.assertEqual(json.asString($decoded, "/docs/0/1"), "A page");
    testing.assertEqual(json.asString($decoded, "/docs/0/2"), "A section");
    testing.assertEqual(json.asString($decoded, "/docs/0/3"), "a-section");
    testing.assertEqual(json.asString($decoded, "/docs/0/4"), "Some body text.");
}

func testScriptOfNoRecordsIsStillValid() {
    def js as string init script([]);
    testing.assertContains($js, "[]");
    testing.assertTrue(strings.startsWith($js, "window.grimoireIndex = "));
}

func testScriptCarriesEveryRecord() {
    def rows as list of Record init [
        record("a.html", "A", "", "", "one", 1200),
        record("b.html", "B", "", "", "two", 1200),
        record("c.html", "C", "", "", "three", 1200)
    ];
    def js as string init script($rows);
    testing.assertContains($js, "a.html");
    testing.assertContains($js, "b.html");
    testing.assertContains($js, "c.html");
}

# Body text is author input and lands inside a script tag, so it has to be
# encoded rather than concatenated - a quote or a backslash must not end the
# string it sits in.
func testScriptEncodesAwkwardBodyText() {
    def r as Record init record("p.html", "T", "H", "h", 'a "quote" here', 1200);
    def js as string init script([$r]);
    testing.assertContains($js, '\"quote\"');
    testing.assertFalse(strings.contains($js, 'a "quote"'));
    testing.assertEqual(json.asString(decodeIndex($js), "/docs/0/4"), 'a "quote" here');
}
