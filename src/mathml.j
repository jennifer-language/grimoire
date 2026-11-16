# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * MathML in a chapter: recognising it, checking it, and handing it to each
 * edition in the form that edition can use.
 *
 * Maths reaches a chapter as a `<math>` element in the MathML namespace, written
 * by a preprocessor or by hand: as an HTML block for display maths, and as
 * inline HTML inside a paragraph. The parser gives the inline form back as a run
 * of `html_inline` tags with text nodes between them, so a run from an opening
 * `<math` to its `</math>` is put back together here.
 *
 * MathML is not raw HTML. An element is accepted only when it is well-formed
 * XML, every element in it is in the MathML namespace, and no attribute can run
 * or fetch anything (`on*`, `href`, `src`, `style`, or one in another
 * namespace). Such an element reaches every edition whatever `[html] rawHtml`
 * says; anything else is left exactly as before.
 *
 * - The site and the EPUB carry the element.
 * - The printable book cannot typeset maths, so it prints the TeX source the
 *   element carries in `<annotation encoding="application/x-tex">`.
 * - The search index leaves maths out: the element's text is a run of single
 *   letters and operators that nobody searches for.
 * @module mathml
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use xml;
use strings;
use lists;
use regex;
use convert;

import "doctree.j" as doctree;

def const NS as string init "http://www.w3.org/1998/Math/MathML";

# An opening `<math` tag: the name, then a space, a slash or the bracket.
def const OPENER as string init '^<math[\s/>]';

# Attributes that can run or fetch something. Everything else MathML has is
# presentation.
def const UNSAFE as list of string init ["href", "src", "style"];

/**
 * The MathML namespace.
 * @return {string} the namespace URI
 */
export func namespace() {
    return NS;
}

# safeElement checks one element and everything under it.
func safeElement(e as xml.Value) {
    if (xml.namespace($e) != NS) {
        return false;
    }
    for (def name in xml.attrs($e)) {
        def lower as string init strings.lower($name);
        if ($lower == "xmlns") {
            continue;
        }
        if (strings.startsWith($lower, "on") or lists.contains(UNSAFE, $lower) or
            strings.contains($lower, ":")) {
            return false;
        }
    }
    for (def c in xml.children($e)) {
        if (not safeElement($c)) {
            return false;
        }
    }
    return true;
}

/**
 * Whether markup is one `<math>` element this module accepts: well-formed, all
 * MathML, and nothing in it that runs or fetches.
 * @param markup {string} the element as text
 * @return {bool} true when it is accepted
 */
export func accepted(markup as string) {
    def text as string init strings.trim($markup);
    if (not regex.matches(OPENER, $text)) {
        return false;
    }
    try {
        def root as xml.Value init xml.decode($text);
        return xml.localName($root) == "math" and safeElement($root);
    } catch (e) {
        return false;
    }
    return false;
}

/**
 * The TeX source an element carries in `<annotation
 * encoding="application/x-tex">`, or "" when it carries none.
 * @param markup {string} an accepted element
 * @return {string} the TeX source
 */
export func texOf(markup as string) {
    return annotationIn(xml.decode(strings.trim($markup)));
}

func annotationIn(e as xml.Value) {
    if (xml.localName($e) == "annotation" and xml.hasAttr($e, "encoding") and
        xml.attr($e, "encoding") == "application/x-tex") {
        return xml.text($e);
    }
    for (def c in xml.children($e)) {
        def found as string init annotationIn($c);
        if ($found != "") {
            return $found;
        }
    }
    return "";
}

/**
 * Whether an element is display maths: `display="block"`.
 * @param markup {string} an accepted element
 * @return {bool} true for display maths
 */
export func isDisplay(markup as string) {
    def root as xml.Value init xml.decode(strings.trim($markup));
    return xml.hasAttr($root, "display") and xml.attr($root, "display") == "block";
}

# The text of a parsed text node as it stood in the source: the parser decoded
# its entities, and the element is XML again once this is joined to its tags.
func xmlText(text as string) {
    return strings.replace(
        strings.replace(strings.replace($text, "&", "&amp;"), "<", "&lt;"),
        ">",
        "&gt;");
}

/**
 * One inline `<math>` element among a node's children.
 * @field first {int} the index of its opening tag
 * @field last {int} the index of its closing tag
 * @field markup {string} the element as text
 */
export def struct Run {
    first as int,
    last as int,
    markup as string
};

/**
 * The inline `<math>` elements among a list of inline nodes, in order.
 *
 * A run is an `html_inline` opening tag, then only `html_inline` tags and text,
 * up to the `</math>` that closes it, and it counts only when the joined markup
 * is accepted. A run that has anything else in it (emphasis, a link, code) is
 * not maths the way this module reads it, and is left alone.
 * @param nodes {list of doctree.Node} a node's children
 * @return {list of Run} the runs
 */
export func runs(nodes as list of doctree.Node) {
    def out as list of Run;
    def i as int init 0;
    while ($i < len($nodes)) {
        def n as doctree.Node init $nodes[$i];
        if ($n.kind != "html_inline" or not regex.matches(OPENER, $n.text)) {
            $i = $i + 1;
            continue;
        }
        def j as int init closingAt($nodes, $i);
        if ($j < 0) {
            $i = $i + 1;
            continue;
        }
        def markup as string init joined($nodes, $i, $j);
        if (not accepted($markup)) {
            $i = $i + 1;
            continue;
        }
        $out[] = Run{first: $i, last: $j, markup: $markup};
        $i = $j + 1;
    }
    return $out;
}

# closingAt is the index of the `</math>` that closes the tag at `from`, or -1
# when something other than a tag or text comes first.
func closingAt(nodes as list of doctree.Node, from as int) {
    def j as int init $from + 1;
    while ($j < len($nodes)) {
        def m as doctree.Node init $nodes[$j];
        if ($m.kind == "html_inline" and strings.trim($m.text) == "</math>") {
            return $j;
        }
        if ($m.kind != "text" and $m.kind != "html_inline") {
            return -1;
        }
        $j = $j + 1;
    }
    return -1;
}

# joined puts a run back together as markup.
func joined(nodes as list of doctree.Node, first as int, last as int) {
    def parts as list of string;
    for (def k in $first..$last + 1) {
        if ($nodes[$k].kind == "text") {
            $parts[] = xmlText($nodes[$k].text);
        } else {
            $parts[] = $nodes[$k].text;
        }
    }
    return strings.join($parts, "");
}

/**
 * The element an HTML block holds, when it is one accepted `<math>` element,
 * or "".
 * @param n {doctree.Node} a block node
 * @return {string} the markup, or ""
 */
export func blockMarkup(n as doctree.Node) {
    if ($n.kind != "html_block" or not regex.matches(OPENER, strings.trim($n.text))) {
        return "";
    }
    if (not accepted($n.text)) {
        return "";
    }
    return strings.trim($n.text);
}

/**
 * Whether a node, or anything under it, holds an accepted `<math>` element.
 * @param n {doctree.Node} the node
 * @return {bool} true when it does
 */
export func holds(n as doctree.Node) {
    if (blockMarkup($n) != "") {
        return true;
    }
    if (len(runs($n.children)) > 0) {
        return true;
    }
    for (def c in $n.children) {
        if (holds($c)) {
            return true;
        }
    }
    return false;
}

# --- rewriting a tree for an edition -----------------------------------

/**
 * A tree with its maths replaced, and the elements that were taken out.
 * @field node {doctree.Node} the rewritten tree
 * @field taken {list of string} the elements, in the order their placeholders
 *   were numbered
 */
export def struct Rewritten {
    node as doctree.Node,
    taken as list of string
};

func blank(kind as string) {
    return doctree.Node{
        kind: $kind,
        level: 0,
        text: "",
        lang: "",
        ordered: false,
        url: "",
        title: "",
        align: "",
        attrs: {},
        children: []
    };
}

func textNode(kind as string, text as string) {
    def n as doctree.Node init blank($kind);
    $n.text = $text;
    return $n;
}

/**
 * The placeholder that stands for the `n`th element taken out by `rewrite` in
 * "mark" mode: text no chapter writes, between two private-use characters.
 * @param n {int} the element's number
 * @return {string} the placeholder
 */
export func placeholder(n as int) {
    return convert.fromCodepoint(0xE000) + "grimoire-mathml-" + convert.toString($n) +
        convert.fromCodepoint(0xE001);
}

# The TeX source of an element, or its text when it carries none.
func sourceOf(markup as string) {
    def tex as string init texOf($markup);
    if ($tex != "") {
        return $tex;
    }
    return xml.text(xml.decode($markup));
}

# For print: a display formula as lines of monospace, each centred on a column
# `chars` wide with no-break spaces (a run of them is one word the layout keeps,
# where ordinary spaces would collapse), joined by hard line breaks.
func centredTex(tex as string, chars as int) {
    def out as list of doctree.Node;
    for (def line in strings.split(strings.trim($tex), "\n")) {
        def text as string init strings.trim($line);
        if ($text == "") {
            continue;
        }
        if (len($out) > 0) {
            $out[] = blank("line_break");
        }
        def pad as int init ($chars - len($text)) // 2;
        if ($pad > 0) {
            $text = strings.repeat(convert.fromCodepoint(0xA0), $pad) + " " + $text;
        }
        $out[] = textNode("codespan", $text);
    }
    return $out;
}

/**
 * Replace every accepted `<math>` element in a tree.
 *
 * `mode` says with what:
 * - "mark": a placeholder text (`placeholder(n)`), for an edition that puts the
 *   element back into the rendered text; `taken` holds the elements.
 * - "tex": the TeX source in monospace, for print: a code span inline, and a
 *   paragraph of centred lines for display maths. `chars` is how many monospace
 *   characters fit across the column.
 * - "drop": nothing at all, for the search index.
 * @param n {doctree.Node} the tree
 * @param mode {string} "mark", "tex" or "drop"
 * @param chars {int} the column width in monospace characters, for "tex"
 * @return {Rewritten} the tree, and the elements taken out
 */
export func rewrite(n as doctree.Node, mode as string, chars as int) {
    def taken as list of string;
    def r as Rewritten init walk($n, $mode, $chars, $taken);
    return $r;
}

func walk(n as doctree.Node, mode as string, chars as int, taken as list of string) {
    def out as doctree.Node init $n;
    def kids as list of doctree.Node;
    def found as list of string init $taken;
    def inline as list of Run init runs($n.children);
    def r as int init 0;
    def i as int init 0;
    while ($i < len($n.children)) {
        if ($r < len($inline) and $inline[$r].first == $i) {
            def markup as string init $inline[$r].markup;
            if ($mode == "mark") {
                $kids[] = textNode("text", placeholder(len($found)));
                $found[] = $markup;
            } elseif ($mode == "tex") {
                $kids[] = textNode("codespan", strings.trim(sourceOf($markup)));
            }
            $i = $inline[$r].last + 1;
            $r = $r + 1;
            continue;
        }
        def child as doctree.Node init $n.children[$i];
        def block as string init blockMarkup($child);
        if ($block != "") {
            if ($mode == "mark") {
                $kids[] = textNode("html_block", placeholder(len($found)));
                $found[] = $block;
            } elseif ($mode == "tex") {
                def para as doctree.Node init blank("paragraph");
                $para.children = centredTex(sourceOf($block), $chars);
                $kids[] = $para;
            }
            $i = $i + 1;
            continue;
        }
        def inner as Rewritten init walk($child, $mode, $chars, $found);
        $kids[] = $inner.node;
        $found = $inner.taken;
        $i = $i + 1;
    }
    $out.children = $kids;
    return Rewritten{node: $out, taken: $found};
}
