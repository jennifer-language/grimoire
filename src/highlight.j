# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Build-time syntax highlighting for Jennifer code blocks.
 *
 * This is the no-CDN half of Grimoire's highlighting. The lexical rules are a
 * port of the project's own highlight.js definition
 * (`editors/highlightjs/jennifer.js`, vendored beside this file), so a block
 * highlighted here and the same block highlighted by highlight.js in the browser
 * agree on what every token is. The classes emitted are highlight.js's own
 * (`hljs-keyword`, `hljs-string`, ...), which means the built-in theme colours
 * and any highlight.js stylesheet both fit without translation.
 *
 * Doing it at build time rather than in the browser buys three things: the one
 * language a Jennifer book is certain to contain highlights with no third-party
 * request, it works with JavaScript off, and there is no repaint after load.
 * @module highlight
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use strings;
use lists;

import "html.j" as html;

# The lexical sets, verbatim from the highlight.js definition so the two
# highlighters cannot disagree about what a word is.
def const KEYWORDS as list of string init [
    "export",
    "def",
    "const",
    "func",
    "struct",
    "enum",
    "use",
    "include",
    "import",
    "as",
    "of",
    "to",
    "init",
    "if",
    "elseif",
    "else",
    "while",
    "for",
    "in",
    "repeat",
    "until",
    "match",
    "when",
    "break",
    "continue",
    "return",
    "exit",
    "try",
    "catch",
    "throw",
    "defer",
    "errdefer",
    "spawn",
    "and",
    "or",
    "not"
];
def const TYPES as list of string init [
    "int",
    "float",
    "string",
    "bool",
    "bytes",
    "list",
    "map",
    "task",
    "channel"
];
def const LITERALS as list of string init ["true", "false", "null"];
def const BUILTINS as list of string init ["len"];

# The languages this highlighter understands. Anything else is emitted as plain
# escaped text - and is highlight.js's job, if the book opted into the CDN.
def const JENNIFER_LANGS as list of string init ["jennifer", "j"];

/**
 * Whether a fenced block's language tag is one this highlighter handles.
 * @param lang {string} the fence's language tag
 * @return {bool} true when the block can be highlighted here
 */
export func handles(lang as string) {
    return lists.contains(JENNIFER_LANGS, strings.lower(strings.trim($lang)));
}

func isDigit(ch as string) {
    return $ch >= "0" and $ch <= "9";
}

func isLower(ch as string) {
    return $ch >= "a" and $ch <= "z";
}

func isUpper(ch as string) {
    return $ch >= "A" and $ch <= "Z";
}

func isAlpha(ch as string) {
    return isLower($ch) or isUpper($ch);
}

func isIdentChar(ch as string) {
    return isAlpha($ch) or isDigit($ch) or $ch == "_";
}

# span wraps one token in its highlight.js class. Text is escaped here and
# nowhere else, so every path out of this module is escaped exactly once.
func span(cls as string, text as string) {
    if ($cls == "") {
        return html.escape($text);
    }
    return '<span class="hljs-' + $cls + '">' + html.escape($text) + "</span>";
}

# classifyWord decides what an identifier-shaped token is. Order matters: a
# keyword is a keyword even when followed by `(`, which is why the call and
# namespace tests come last.
func classifyWord(word as string, next as string) {
    if (lists.contains(KEYWORDS, $word)) {
        return "keyword";
    }
    if (lists.contains(TYPES, $word)) {
        return "type";
    }
    if (lists.contains(LITERALS, $word)) {
        return "literal";
    }
    if (lists.contains(BUILTINS, $word)) {
        return "built_in";
    }
    # A namespace prefix: the `io` of `io.printf(...)`.
    if ($next == ".") {
        return "built_in";
    }
    # A constant is UPPER_CASE; a name that is all caps and has no lowercase is
    # one by the language's own naming rule.
    if (isUpper(strings.substring($word, 0, 1)) and strings.upper($word) == $word) {
        return "symbol";
    }
    if ($next == "(") {
        return "title";
    }
    return "";
}

# --- scanners -------------------------------------------------------
#
# Each returns the index just past the token it consumed, so the main loop only
# has to dispatch on the first character.
#
# These five take the character list, which on an interpreter without the
# read-only parameter borrow is one copy of the whole block per call. That is
# affordable where it is left: between them they run about 5,700 times on this
# manual. The three things that ran per character or per identifier - the prompt
# test, the identifier scan, and the slicing - are written out inside `render`
# instead, where `cs` is a local and no binding copies it.
#
# The borrow arrived in 0.24.0-dev+15 and makes the copy free, so this is a
# floor rather than a target: what is inlined below is inlined to remove a call
# per character, which costs something on every interpreter. Do not undo it on
# the grounds that the copy is gone.

func scanLineComment(cs as list of string, at as int) {
    def i as int init $at;
    while ($i < len($cs) and $cs[$i] != "\n") {
        $i = $i + 1;
    }
    return $i;
}

# A block comment nests, so this counts depth rather than stopping at the first
# `*/` - the language says `/* /* */ */` is one comment.
func scanBlockComment(cs as list of string, at as int) {
    def i as int init $at + 2;
    def depth as int init 1;
    while ($i < len($cs)) {
        if ($i + 1 < len($cs) and $cs[$i] == "/" and $cs[$i + 1] == "*") {
            $depth = $depth + 1;
            $i = $i + 2;
            continue;
        }
        if ($i + 1 < len($cs) and $cs[$i] == "*" and $cs[$i + 1] == "/") {
            $depth = $depth - 1;
            $i = $i + 2;
            if ($depth == 0) {
                return $i;
            }
            continue;
        }
        $i = $i + 1;
    }
    return $i;
}

# A raw string ends at the next quote; there are no escapes inside one.
func scanRawString(cs as list of string, at as int) {
    def i as int init $at + 1;
    while ($i < len($cs) and $cs[$i] != "'") {
        $i = $i + 1;
    }
    if ($i < len($cs)) {
        return $i + 1;
    }
    return $i;
}

# A cooked string honours backslash escapes, so a `\"` does not end it.
func scanCookedString(cs as list of string, at as int) {
    def i as int init $at + 1;
    while ($i < len($cs)) {
        if ($cs[$i] == "\\") {
            $i = $i + 2;
            continue;
        }
        if ($cs[$i] == '"') {
            return $i + 1;
        }
        $i = $i + 1;
    }
    return $i;
}

func scanNumber(cs as list of string, at as int) {
    def i as int init $at;
    while ($i < len($cs)) {
        def ch as string init $cs[$i];
        if (isDigit($ch) or isAlpha($ch) or $ch == "_" or $ch == ".") {
            # A `.` only continues the number when a digit follows, so `1.max`
            # is a number then a field access, not one long token.
            if ($ch == "." and ($i + 1 >= len($cs) or not isDigit($cs[$i + 1]))) {
                return $i;
            }
            $i = $i + 1;
            continue;
        }
        if (($ch == "+" or $ch == "-") and $i > $at and
            ($cs[$i - 1] == "e" or $cs[$i - 1] == "E")) {
            $i = $i + 1;
            continue;
        }
        return $i;
    }
    return $i;
}

/**
 * Highlight Jennifer source, returning HTML with highlight.js class names. The
 * text is escaped as it is emitted, so the result is ready to drop inside a
 * `<code>` element.
 * @param code {string} the source of one code block
 * @return {string} the highlighted HTML
 */
export func render(code as string) {
    def cs as list of string init strings.chars($code);
    def out as list of string;
    def n as int init len($cs);
    def i as int init 0;
    def plain as int init 0;
    while ($i < $n) {
        def ch as string init $cs[$i];
        def cls as string init "";
        def stop as int init $i;
        # The REPL prompt rule, written out here rather than as a helper: it is
        # the only test that runs on every character, so a helper taking `cs`
        # would copy the whole block once per character. Real source never opens
        # a line with `>>> `, so this is inert outside a pasted transcript - the
        # first-character test is what keeps it that way.
        def prompt as bool init false;
        if (($ch == ">" or $ch == ".") and $i + 3 < $n and
            ($i == 0 or $cs[$i - 1] == "\n")) {
            def three as string init $ch + $cs[$i + 1] + $cs[$i + 2];
            $prompt = ($three == ">>>" or $three == "...") and $cs[$i + 3] == " ";
        }
        if ($prompt) {
            $cls = "meta";
            $stop = $i + 4;
        } elseif ($ch == "#") {
            $cls = "comment";
            $stop = scanLineComment($cs, $i);
        } elseif ($ch == "/" and $i + 1 < $n and $cs[$i + 1] == "*") {
            $cls = "comment";
            $stop = scanBlockComment($cs, $i);
        } elseif ($ch == '"') {
            $cls = "string";
            $stop = scanCookedString($cs, $i);
        } elseif ($ch == "'") {
            $cls = "string";
            $stop = scanRawString($cs, $i);
        } elseif ($ch == "$" and $i + 1 < $n and isAlpha($cs[$i + 1])) {
            $cls = "variable";
            $stop = $i + 1;
            while ($stop < $n and isIdentChar($cs[$stop])) {
                $stop = $stop + 1;
            }
        } elseif (isDigit($ch)) {
            $cls = "number";
            $stop = scanNumber($cs, $i);
        } elseif (isAlpha($ch) or $ch == "_") {
            # The identifier scan is written out rather than called for the same
            # reason as the prompt test above: it is the most frequent token in
            # any Jennifer source, and a helper taking `cs` copied the whole
            # block on each of the 23,000 of them in this manual.
            $stop = $i;
            while ($stop < $n and isIdentChar($cs[$stop])) {
                $stop = $stop + 1;
            }
            # The character after the token, spaces and tabs skipped, decides
            # whether the identifier is a call or a namespace prefix.
            def after as int init $stop;
            while ($after < $n and ($cs[$after] == " " or $cs[$after] == "\t")) {
                $after = $after + 1;
            }
            def next as string init "";
            if ($after < $n) {
                $next = $cs[$after];
            }
            $cls = classifyWord(strings.join($cs[$i..$stop], ""), $next);
        }
        # A scanner can run past the end - a cooked string whose last character
        # is a backslash consumes the escape and the character after it, which
        # may not exist. Clamping here keeps the slices below in range.
        if ($stop > $n) {
            $stop = $n;
        }
        if ($cls == "" or $stop <= $i) {
            # Ordinary text: accumulate and emit it in one run, so the output is
            # not a span per character.
            $i = $i + 1;
            continue;
        }
        if ($plain < $i) {
            $out[] = html.escape(strings.join($cs[$plain..$i], ""));
        }
        $out[] = span($cls, strings.join($cs[$i..$stop], ""));
        $i = $stop;
        $plain = $i;
    }
    if ($plain < $n) {
        $out[] = html.escape(strings.join($cs[$plain..$n], ""));
    }
    return strings.join($out, "");
}
