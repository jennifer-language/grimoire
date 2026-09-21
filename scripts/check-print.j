#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * What the printable book cannot draw.
 *
 * The standard-14 PDF fonts encode WinAnsi and no more, so a character outside
 * it reaches the page as whatever `TRANSLITERATIONS` in `src/pdfbook.j` says, or
 * as `?` if it says nothing. This walks everything that ends up in
 * `grimoire.pdf` - every chapter, the configured strings around them, and the
 * interface labels the layout now draws - and reports each character that would
 * print as a question mark.
 *
 * It is the other half of `scripts/check-style.sh`, and the half that has a
 * reason to care about letters. The punctuation check deliberately allows them:
 * an umlaut in a test fixture is data, and the site renders it perfectly. This
 * one asks a narrower question about a smaller set of files - will the *printed*
 * book show it - and answers it with the module's own table rather than with a
 * guess about which alphabets are safe. An `a` with an umlaut passes here, which
 * the old blanket grep never allowed; a Cyrillic word does not, which the old
 * grep caught only by banning every letter it had never seen.
 *
 *   jennifer run scripts/check-print.j [grimoire.toml]
 *
 * Prints every offending character with its file, line, and codepoint, and exits
 * 1; or prints nothing and exits 0.
 * @module checkprint
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use os;
use fs;
use strings;
use convert;
use lists;

import "../src/config.j" as config;
import "../src/locale.j" as locale;
import "../src/pdfbook.j" as pdfbook;

# A character prints as itself, as an ASCII reading, or as a question mark.
# Only the third is a finding: `sanitize` is what the build itself runs, so a
# character with a reading is already handled and a character without one is
# what the reader will actually see.
func lost(ch as string) {
    if (convert.toCodepoint($ch) < 128) {
        return false;
    }
    return pdfbook.sanitize($ch) == "?";
}

# hex renders a codepoint the way Unicode writes one. `convert.toString` is
# decimal only and `io.printf` has no `%x`, so the digits are assembled here.
def const HEX as string init "0123456789ABCDEF";

func hex(n as int) {
    if ($n == 0) {
        return "0";
    }
    def out as string init "";
    def rest as int init $n;
    while ($rest > 0) {
        def digit as int init $rest % 16;
        $out = strings.substring(HEX, $digit, $digit + 1) + $out;
        $rest = $rest // 16;
    }
    return $out;
}

# report prints one finding. The character is named by codepoint rather than
# shown, so this script's own output can be pasted anywhere - and so the script
# obeys the punctuation rule it sits beside.
func report(where as string, line as int, ch as string) {
    io.printf("%s:%d: U+%s would print as `?`\n", $where, $line, hex(convert.toCodepoint($ch)));
}

# scan walks one run of text and reports what the printed page would lose. The
# same character twice on a line is reported once: the point is the character,
# not the count.
func scan(where as string, text as string) {
    def hits as int init 0;
    def line as int init 1;
    for (def raw in strings.split($text, "\n")) {
        def seen as list of string;
        for (def ch in strings.chars($raw)) {
            if (lost($ch) and not lists.contains($seen, $ch)) {
                $seen[] = $ch;
                report($where, $line, $ch);
                $hits = $hits + 1;
            }
        }
        $line = $line + 1;
    }
    return $hits;
}

def confPath as string init "grimoire.toml";
if (len(os.ARGS) > 1) {
    $confPath = os.ARGS[1];
}
def c as config.Config init config.load($confPath);
locale.install($c.uiLanguage);

def total as int init 0;

# The chapters, in whatever order the tree yields them - this is a check, not a
# build, so nothing here depends on the outline.
for (def st in fs.walk($c.srcDir)) {
    if ($st.isDir or not strings.endsWith($st.path, ".md")) {
        continue;
    }
    $total = $total + scan($st.path, fs.readString($st.path));
}

# The strings the configuration puts on the page around them.
$total = $total + scan($confPath + " [book] title", $c.title);
$total = $total + scan($confPath + " [book] description", $c.description);
$total = $total + scan($confPath + " [book] authorsLabel", $c.authorsLabel);
for (def author in $c.authors) {
    $total = $total + scan($confPath + " [book] authors", $author);
}
$total = $total + scan($confPath + " [pdf] footerLeft", $c.pdfFooterLeft);

# The one thing Grimoire itself writes into the printable book: the label on a
# callout, in the book's own language. A book whose language the standard-14
# fonts cannot draw gets question marks where the site says `Warnung`.
for (def kind in ["note", "tip", "important", "warning", "caution"]) {
    def where as string init "locale " + $c.uiLanguage + " admonition " + $kind;
    $total = $total + scan($where, locale.admonitionLabel($kind));
}

if ($total > 0) {
    io.eprintf("%d character(s) the printable book cannot draw\n", $total);
    exit 1;
}
