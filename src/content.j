# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The Markdown-to-HTML renderer. It walks the `markdown` module's document tree
 * itself rather than calling `markdown.toHtml`, because a documentation site
 * needs more than the plain translation: stable heading anchors, `.md` links
 * rewritten to `.html`, code blocks wrapped with a language tag and a copy
 * button, scroll containers around tables, and a thematic break the Markdown
 * subset does not model. One walk produces all four outputs a page needs - the
 * body HTML, the page title, the contents list, and the per-section text the
 * search index is built from.
 *
 * Everything that reaches the output goes through `html.escape` (text) or the
 * local attribute escaper (attribute values), and every link goes through
 * `html.safeUrl`, so a hostile document cannot inject markup or a
 * `javascript:` href - in any casing, entity-encoded, or as a `data:` URL.
 * Inline HTML is covered by the same rule without any effort: the parser hands
 * `a <b>bold</b> c` back as one text node, so it is escaped like any other text.
 *
 * A hand-written HTML **block** is the single exception, and the only thing
 * `rawHtml` controls. On, which is the default and what every comparable
 * generator does, it goes to the page as written - that is the point of writing
 * it, and a book's own source is trusted the same way the configured footer is.
 * Off, it is escaped and shown, for a book assembled from Markdown its author did
 * not write.
 *
 * A `> [!NOTE]` callout is the parser's work rather than this module's: it hands
 * back an `admonition` node carrying the kind and any title the marker had, and
 * what is left here is the markup and the label. The label is Grimoire's word,
 * so it comes from the catalogs and follows the book's language.
 *
 * `markdown.toHtml` is not used for any of this. It gained the same choice as
 * `toHtmlWith(md, HtmlOptions{allowRawHtml: ...})` and defaults to escaping now,
 * but nothing here has ever called it: a documentation site needs more than the
 * plain translation, and the walk above is where that difference lives.
 * @module content
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use strings;
use convert;
use lists;
use maps;

import "markdown.j" as markdown;
import "html.j" as html;
import "./highlight.j" as highlight;
import "./util.j" as util;
import "./locale.j" as locale;

/**
 * One heading of a page, as the contents list needs it.
 * @field level {int} the heading level, 1-6
 * @field text {string} the flattened heading text
 * @field id {string} the unique anchor id
 */
export def struct Heading {
    level as int,
    text as string,
    id as string
};

/**
 * One indexable slice of a page: everything from one heading up to the next.
 * @field anchor {string} the heading's anchor id ("" for the lead-in section)
 * @field heading {string} the heading text ("" for the lead-in section)
 * @field text {string} the section's flattened body text
 */
export def struct Section {
    anchor as string,
    heading as string,
    text as string
};

/**
 * A rendered page.
 * @field html {string} the body HTML
 * @field title {string} the first level-one heading, or "" when there is none
 * @field headings {list of Heading} every heading, in document order
 * @field sections {list of Section} the page sliced at its headings
 */
export def struct Rendered {
    html as string,
    title as string,
    headings as list of Heading,
    sections as list of Section
};

# Attribute values are rendered inside double quotes, so they need the quote
# escaped on top of what html.escape does for text.
func attrEsc(s as string) {
    return strings.replace(html.escape($s), '"', "&quot;");
}

# href rewrites a link target for the generated site: an in-page fragment and an
# external URL pass through, a `.md` target becomes its `.html` output (with a
# directory readme folded onto the directory index), and everything is finally
# gated by html.safeUrl so a `javascript:` scheme can never survive.
func href(url as string) {
    if ($url == "" or strings.startsWith($url, "#") or util.isExternal($url)) {
        return html.safeUrl($url);
    }
    def parts as list of string init util.splitFragment($url);
    def target as string init $parts[0];
    if (strings.endsWith(strings.lower($target), ".md")) {
        $target = util.htmlPath($target);
    }
    return html.safeUrl($target + $parts[1]);
}

# --- inline rendering ----------------------------------------------
#
# The Markdown module nests inline spans, so the children of a `**...**`, an
# emphasis, or a link label are real nodes and are rendered as such - which is
# what keeps `` **`json.Value`** `` bold *and* monospaced, and what gets a link
# inside bold its `.md` rewritten to `.html` like any other.

# Every accumulation below collects into a list and joins once. Appending to a
# Jennifer string reallocates it, so a `$out = $out + piece` loop over a long
# chapter is quadratic in the size of the output.
func renderInline(nodes as list of markdown.Node) {
    def out as list of string;
    for (def n in $nodes) {
        $out[] = renderSpan($n);
    }
    return strings.join($out, "");
}

# A node's content: its children rendered inline, or its own text when the module
# reports none - a leaf.
#
# It serves two callers. A styled span uses it for what is inside the emphasis or
# the link, and both renderers use it as the fallback for a type neither of them
# names. The second is the one with a rule attached: it always **descends**, and
# neither `else` branch may instead hand the same node to the other renderer - an
# inline node in block position to `renderSpan`, a block node in inline position
# to `renderBlock`. A type neither names then bounces between the two until the
# interpreter stops the build at ten thousand frames, with a message about
# recursion and nothing about the book. A list `item` is such a type, reached
# through an outline title that begins with an ordered-list marker.
func contentOf(n as markdown.Node) {
    def kids as list of markdown.Node init markdown.children($n);
    if (len($kids) == 0) {
        return html.escape(markdown.text($n));
    }
    return renderInline($kids);
}

func renderSpan(n as markdown.Node) {
    match (markdown.typeOf($n)) {
        when "text" { return html.escape(markdown.text($n)); }
        when "codespan" { return "<code>" + html.escape(markdown.text($n)) + "</code>"; }
        when "strong" { return "<strong>" + contentOf($n) + "</strong>"; }
        when "emphasis" { return "<em>" + contentOf($n) + "</em>"; }
        # Each is the element the syntax means rather than the one it looks
        # like: `~~x~~` is withdrawn text, not struck-through styling, and
        # `==x==` is a mark a reader made.
        when "strikethrough" { return "<del>" + contentOf($n) + "</del>"; }
        when "highlight" { return "<mark>" + contentOf($n) + "</mark>"; }
        when "subscript" { return "<sub>" + contentOf($n) + "</sub>"; }
        when "superscript" { return "<sup>" + contentOf($n) + "</sup>"; }
        when "link" {
            def title as string init markdown.attr($n, "title");
            def extra as string init classOf($n);
            if ($title != "") {
                $extra = $extra + ' title="' + attrEsc($title) + '"';
            }
            if (util.isExternal(markdown.attr($n, "href"))) {
                $extra = $extra + ' rel="noopener noreferrer"';
            }
            return '<a href="' + attrEsc(href(markdown.attr($n, "href"))) + '"' + $extra + ">" +
                contentOf($n) + "</a>";
        }
        when "image" {
            def alt as string init attrEsc(markdown.text($n));
            def title as string init markdown.attr($n, "title");
            def extra as string init classOf($n);
            if ($title != "") {
                $extra = $extra + ' title="' + attrEsc($title) + '"';
            }
            return '<img src="' + attrEsc(href(markdown.attr($n, "url"))) + '" alt="' + $alt +
                '" loading="lazy"' + $extra + ">";
        }
        # A block that turned up in inline position - a nested list, or the
        # paragraph the module wraps a multi-line list item in - renders through
        # the block path. Neither highlighting nor raw HTML can arrive by this
        # route, so both are off: a fenced block is not inline, and inline HTML is
        # text by the time the parser is done with it.
        when "paragraph" { return renderBlock($n, false, false); }
        when "list" { return renderList($n); }
        when "definition_list" { return renderDefinitions($n); }
        when "table" { return renderTable($n); }
        when "code" { return renderCode($n, false); }
        when "quote" { return renderQuote($n, false, false); }
        when "heading" { return renderBlock($n, false, false); }
        else { return contentOf($n); }
    }
}

/**
 * Render a Markdown fragment as inline HTML - used for titles taken from the
 * outline, which are Markdown (`` `code` ``, emphasis) but must not become block
 * elements in a sidebar entry.
 * @param text {string} the Markdown fragment
 * @return {string} the inline HTML
 */
export func inline(text as string) {
    def doc as markdown.Node init markdown.parse($text);
    def kids as list of markdown.Node init markdown.children($doc);
    # A title is inline text, and `markdown.parse` reads blocks. When it made
    # anything but one paragraph - a list, because `1. Peripherals` opens one; a
    # heading, because `# ` does; a fence, a quote - the block reading is not what
    # the author of a `SUMMARY.md` line meant, so the title is taken literally.
    #
    # Numbered outlines are the reason this matters: `- [7. Tapes](tapes.md)` is
    # how a reference manual writes its outline, and read as a block it is a list
    # whose item text has lost the number.
    if (len($kids) != 1 or markdown.typeOf($kids[0]) != "paragraph") {
        return html.escape($text);
    }
    return renderInline(markdown.children($kids[0]));
}

# --- block rendering -----------------------------------------------

# A task list item: the checkbox a reader cannot tick, because a page is not a
# form. `disabled` is what makes that plain to a screen reader as well, and the
# class is what the stylesheet hangs the missing bullet on.
func renderTask(item as markdown.Node) {
    def box as string init '<input type="checkbox" disabled';
    if (markdown.attr($item, "checked") == "true") {
        $box = $box + " checked";
    }
    return '<li class="gr-task">' + $box + "> " +
        renderInline(markdown.children($item)) + "</li>";
}

func renderList(n as markdown.Node) {
    def tag as string init "ul";
    if (markdown.attr($n, "ordered") == "true") {
        $tag = "ol";
    }
    def out as list of string init ["<" + $tag + ">"];
    def tasks as bool init false;
    for (def item in markdown.children($n)) {
        if (markdown.attr($item, "task") == "true") {
            $out[] = renderTask($item);
            $tasks = true;
            continue;
        }
        $out[] = "<li>" + renderInline(markdown.children($item)) + "</li>";
    }
    $out[] = "</" + $tag + ">";
    if ($tasks) {
        # One class on the list, so the stylesheet can drop the markers for a
        # list of tasks without touching the ordinary lists around it.
        $out[0] = "<" + $tag + ' class="gr-tasks">';
    }
    return strings.join($out, "");
}

# A definition list: a term, and what it means. The parser hands the terms and
# the descriptions back as siblings, in document order, so this is a walk rather
# than a pairing.
func renderDefinitions(n as markdown.Node) {
    def out as list of string init ["<dl>"];
    for (def child in markdown.children($n)) {
        if (markdown.typeOf($child) == "def_term") {
            $out[] = "<dt>" + renderInline(markdown.children($child)) + "</dt>";
            continue;
        }
        $out[] = "<dd>" + renderInline(markdown.children($child)) + "</dd>";
    }
    $out[] = "</dl>";
    return strings.join($out, "");
}

func renderRow(row as markdown.Node, cellTag as string) {
    def out as list of string init ["<tr>"];
    for (def cell in markdown.children($row)) {
        # Only the two alignments the stylesheet has a rule for are emitted.
        # Testing for what is *wanted* rather than excluding what is not is what
        # keeps this quiet when the `markdown` module changes its mind about how
        # an unaligned cell is spelled: it reported "" once and reports "none"
        # now, and the exclusion list had put `data-align="none"` on every cell
        # of every table in the book.
        def align as string init markdown.attr($cell, "align");
        def attrs as string init "";
        if ($align == "right" or $align == "center") {
            $attrs = ' data-align="' + $align + '"';
        }
        $out[] = "<" + $cellTag + $attrs + ">" + renderInline(markdown.children($cell)) +
            "</" + $cellTag + ">";
    }
    $out[] = "</tr>";
    return strings.join($out, "");
}

func renderTable(n as markdown.Node) {
    def rows as list of markdown.Node init markdown.children($n);
    if (len($rows) == 0) {
        return "";
    }
    def out as list of string init ['<div class="gr-tablewrap"><table><thead>'];
    $out[] = renderRow($rows[0], "th");
    $out[] = "</thead><tbody>";
    for (def i in 1..len($rows)) {
        $out[] = renderRow($rows[$i], "td");
    }
    $out[] = "</tbody></table></div>";
    return strings.join($out, "");
}

# The copy button carries its own SVG so the page needs no icon font and no
# network request; the script attaches the behaviour.
#
# A function rather than a `def const`, because its label is translated and a
# module constant is built before the catalogs are loaded.
def const COPY_ICON as string init '<svg viewBox="0 0 24 24" fill="none" ' +
    'stroke="currentColor" stroke-width="2" stroke-linecap="round" ' +
    'stroke-linejoin="round" aria-hidden="true">' +
    '<rect x="9" y="9" width="11" height="11" rx="2"/>' +
    '<path d="M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"/></svg>';

func copyButton() {
    return '<button class="gr-copy" type="button" aria-label="' +
        attrEsc(locale.tr("copyCode")) + '">' + COPY_ICON + "</button>";
}

# `title="..."` out of a fence's info string.
#
# The parser keeps the whole info string and splits off only the language, so
# anything else a fence says is text to read here. Only `title` is read, and only
# in quotes: an unquoted value cannot hold the space a file name so often has, and
# a key this does not know is somebody else's convention rather than an error.
func titleOf(info as string) {
    def at as int init strings.indexOf($info, 'title="');
    if ($at < 0) {
        return "";
    }
    def rest as string init strings.substring($info, $at + 7, len($info));
    def stop as int init strings.indexOf($rest, '"');
    if ($stop < 0) {
        return "";
    }
    return strings.substring($rest, 0, $stop);
}

func renderCode(n as markdown.Node, highlighting as bool) {
    def lang as string init strings.trim(markdown.attr($n, "lang"));
    def code as string init markdown.text($n);
    def label as string init "";
    def classes as list of string;
    if ($lang != "") {
        $label = '<span class="gr-lang">' + html.escape($lang) + "</span>";
        $classes[] = "language-" + attrEsc(util.slugify($lang));
    }
    # ```` ```py title="setup.py" ```` names the file the snippet came from, which
    # is the one thing a reader needs that the code cannot say itself. It replaces
    # the language chip rather than joining it: both in one corner is noise, and a
    # file name already says what language it is.
    def named as string init titleOf(markdown.attr($n, "info"));
    if ($named != "") {
        $label = '<span class="gr-lang">' + html.escape($named) + "</span>";
    }
    def body as string init html.escape($code);
    if ($highlighting and highlight.handles($lang)) {
        $body = highlight.render($code);
        # The `hljs` class marks the block as already highlighted, so the
        # highlight.js runtime - if a book also enabled the CDN - leaves it alone
        # instead of repainting work that is already on the page.
        $classes[] = "hljs";
    }
    def cls as string init "";
    if (len($classes) > 0) {
        $cls = ' class="' + strings.join($classes, " ") + '"';
    }
    return '<div class="gr-codeblock">' + $label + copyButton() + "<pre><code" + $cls + ">" +
        $body + "</code></pre></div>";
}

# renderAdmonition draws a callout: the label, then the blocks the parser put
# inside it.
#
# The label is the kind's name from the catalogs, in the book's language - unless
# the marker carried a title (`> [!NOTE] Mind the gap`). A title is the author's
# text, so it is used as written and marked so the sheet does not set it in the
# small capitals a standing label gets.
func renderAdmonition(n as markdown.Node, highlighting as bool, rawHtml as bool) {
    def kind as string init markdown.attr($n, "kind");
    def title as string init markdown.attr($n, "title");
    def label as string init locale.admonitionLabel($kind);
    def labelClass as string init "gr-adm-label";
    if ($title != "") {
        $label = $title;
        $labelClass = "gr-adm-label gr-adm-titled";
    }
    def out as list of string init [
        '<div class="gr-adm gr-adm-' + attrEsc($kind) + '" role="note">',
        '<p class="' + $labelClass + '">' + html.escape($label) + "</p>"
    ];
    for (def child in markdown.children($n)) {
        $out[] = renderBlock($child, $highlighting, $rawHtml);
    }
    $out[] = "</div>";
    return strings.join($out, "");
}

# The blocks that can hold another block, and so a callout with a title. A table
# cell cannot: the parser gives it inline children only, which is why the descent
# below does not walk one - a table-heavy page would pay for every cell.
def const NESTS_BLOCKS as list of string init [
    "quote",
    "admonition",
    "list",
    "item",
    "definition_list",
    "def_desc"
];

# titlesIn collects the title of every callout at or below a node, in document
# order. A title is an attribute rather than a child, so `markdown.text` walks
# past it, and words printed on the page would be unfindable by the search that
# indexes that page.
#
# The descent follows the same containers `flatText` joins, and stops at anything
# that cannot hold a block: a paragraph's children are inline, a code block is
# text. It visits the container nodes and nothing else, which is less of the tree
# than the text walk beside it.
func titlesIn(n as markdown.Node) {
    def kind as string init markdown.typeOf($n);
    def parts as list of string;
    if ($kind == "admonition") {
        def title as string init markdown.attr($n, "title");
        if ($title != "") {
            $parts[] = $title;
        }
    }
    if (lists.contains(NESTS_BLOCKS, $kind)) {
        for (def child in markdown.children($n)) {
            def inner as string init titlesIn($child);
            if ($inner != "") {
                $parts[] = $inner;
            }
        }
    }
    return strings.join($parts, " ");
}

# The blocks whose children are separate pieces of prose rather than one run of
# it: a cell is not the next cell, an item is not the next item.
#
# `markdown.text` concatenates a subtree with nothing between the parts, which is
# right inside a paragraph - `**bold**word` is one word - and wrong for every one
# of these. A table went into the search index as `KeyTypeDefaultMeaning`, so the
# first word of each cell could never match at a word boundary and the index was
# full of tokens no reader would ever type.
def const JOINED as list of string init [
    "list",
    "item",
    "table",
    "row",
    "cell",
    "definition_list",
    "def_term",
    "def_desc",
    "quote",
    "admonition"
];

# flatText is a block's prose for the search index: one run for a paragraph or a
# leaf, and the children joined by a space for anything in `JOINED`.
func flatText(n as markdown.Node) {
    if (not lists.contains(JOINED, markdown.typeOf($n))) {
        return markdown.text($n);
    }
    def parts as list of string;
    for (def child in markdown.children($n)) {
        def piece as string init flatText($child);
        if ($piece != "") {
            $parts[] = $piece;
        }
    }
    return strings.join($parts, " ");
}

# indexText is the text a block contributes to the search index: its own, plus
# the titles of any callouts in it. The parser keeps the marker out of the text
# - that is machinery - while a title is the author's words and belongs in the
# index the way a heading does.
#
# The titles lead, because the body is truncated to `searchBodyChars` and a title
# at its own position could be cut off the end of the section it announces.
func indexText(n as markdown.Node) {
    def titles as string init titlesIn($n);
    if ($titles == "") {
        return flatText($n);
    }
    return $titles + " " + flatText($n);
}

func renderQuote(n as markdown.Node, highlighting as bool, rawHtml as bool) {
    def out as list of string init ["<blockquote>"];
    for (def child in markdown.children($n)) {
        $out[] = renderBlock($child, $highlighting, $rawHtml);
    }
    $out[] = "</blockquote>";
    return strings.join($out, "");
}

# renderBlock covers every block kind except a top-level heading, which the page
# walk handles itself so it can attach the anchor id it assigned.
func renderBlock(n as markdown.Node, highlighting as bool, rawHtml as bool) {
    match (markdown.typeOf($n)) {
        when "paragraph" { return "<p>" + renderInline(markdown.children($n)) + "</p>"; }
        when "heading" {
            def level as string init convert.toString(markdown.level($n));
            return "<h" + $level + ">" + renderInline(markdown.children($n)) + "</h" + $level + ">";
        }
        when "code" { return renderCode($n, $highlighting); }
        when "list" { return renderList($n); }
        when "definition_list" { return renderDefinitions($n); }
        when "table" { return renderTable($n); }
        when "quote" { return renderQuote($n, $highlighting, $rawHtml); }
        when "admonition" { return renderAdmonition($n, $highlighting, $rawHtml); }
        when "thematic_break" { return "<hr>"; }
        # The one place anything reaches the page unescaped, and the only reason
        # `rawHtml` is threaded this far down.
        #
        # A hand-written block goes to the page verbatim - that is the point of
        # writing it - and a book's own source is trusted the same way the
        # configured footer is. `[html] rawHtml = false` is for the book that is
        # not its own author: a generated reference, contributed chapters, a
        # vendored README. Then the markup is shown rather than run.
        #
        # Only a *block* can be raw. Inline HTML never reaches here: the parser
        # hands `a <b>bold</b> c` back as one text node, which the inline path
        # escapes like any other text.
        when "html_block" {
            if ($rawHtml) {
                return markdown.text($n);
            }
            return "<p>" + html.escape(markdown.text($n)) + "</p>";
        }
        # A page-break directive is print-only and has nothing to draw here.
        when "page_break" { return ""; }
        when "text" { return html.escape(markdown.text($n)); }
        when "codespan" { return renderSpan($n); }
        when "strong" { return renderSpan($n); }
        when "emphasis" { return renderSpan($n); }
        when "link" { return renderSpan($n); }
        when "image" { return renderSpan($n); }
        else { return contentOf($n); }
    }
}

# The `class` an attribute list put on a link or an image, as an attribute, or "".
#
# **Only** the class. An attribute list can carry any key a book writes, and a
# renderer that passed them all through would let a chapter put `onclick` on a
# link - markup that runs. A class is styling, and styling is what the syntax is
# for; anything else a book needs it can write as an HTML block, where the rule is
# already `[html] rawHtml` and the author's own decision.
func classOf(n as markdown.Node) {
    def names as string init strings.trim(markdown.attr($n, "class"));
    if ($names == "") {
        return "";
    }
    return ' class="' + attrEsc($names) + '"';
}

# The permalink chip that appears beside a heading on hover.
func anchorLink(id as string) {
    return '<a class="gr-anchor" href="#' + attrEsc($id) +
        '" aria-hidden="true" tabindex="-1">#</a>';
}

func renderHeading(n as markdown.Node, id as string) {
    def level as string init convert.toString(markdown.level($n));
    return "<h" + $level + ' id="' + attrEsc($id) + '">' + anchorLink($id) +
        renderInline(markdown.children($n)) + "</h" + $level + ">";
}

# --- the page walk -------------------------------------------------

/**
 * Render Markdown source into everything a page needs: the body HTML, the
 * title, the contents list, and the per-section text for the search index.
 * Heading anchors are assigned in document order and disambiguated the way
 * GitHub does, so a repeated heading still gets a stable, distinct link.
 * @param md {string} the Markdown source
 * @param highlighting {bool} whether to highlight Jennifer code blocks in place
 * @param rawHtml {bool} whether a hand-written HTML block goes to the page
 *   verbatim; false escapes it, so the markup is shown rather than run
 * @return {Rendered} the rendered page
 * @throws {Error} kind "markdown" when the document is too deep or too large
 */
export func render(md as string, highlighting as bool, rawHtml as bool) {
    def doc as markdown.Node init markdown.parse($md);
    def out as list of string;
    def headings as list of Heading;
    def sections as list of Section;
    def seen as map of string to int;
    def title as string init "";
    def anchor as string init "";
    def sectionHeading as string init "";
    def buffer as list of string;
    for (def node in markdown.children($doc)) {
        def kind as string init markdown.typeOf($node);
        if ($kind != "heading") {
            $out[] = renderBlock($node, $highlighting, $rawHtml);
            # Raw markup and a rule are both structure rather than prose, so
            # neither goes into the search index - nobody searches for a `<div>`.
            if ($kind == "html_block" or $kind == "thematic_break") {
                continue;
            }
            def flat as string init util.squeeze(indexText($node));
            if ($flat != "") {
                $buffer[] = $flat;
            }
            continue;
        }
        def text as string init util.squeeze(markdown.text($node));
        def base as string init util.slugify($text);
        def id as string init util.uniqueSlug($seen, $base);
        # Counted in place rather than through `util.remember`, which hands back a
        # map and so copies the whole of it once per heading. Measured on a page of
        # 400 headings - which is what `{{#apiref}}` produces from a large source
        # tree - that is 104 ms of copying against 9 ms, and it grows
        # quadratically: the reading side, `uniqueSlug`, is borrowed and free.
        if (maps.has($seen, $base)) {
            $seen[$base] = $seen[$base] + 1;
        } else {
            $seen[$base] = 1;
        }
        # `## Heading {#named}` names its own anchor, and then the name is the
        # anchor everywhere: the heading, the contents list, the search index.
        # Assigned here rather than in `renderHeading` for exactly that reason -
        # one id per heading, computed once, or a book's own cross-references
        # would point at a fragment the page does not have.
        #
        # It goes through `slugify` too: an id reaches an attribute and a URL
        # fragment, and a book that writes `{#my anchor}` means one word.
        def named as string init strings.trim(markdown.attr($node, "id"));
        if ($named != "") {
            $id = util.slugify($named);
            # Counted as well, or a later heading whose own slug happens to be
            # this name would be given it a second time and one of the two links
            # would go to the wrong place.
            if (maps.has($seen, $id)) {
                $seen[$id] = $seen[$id] + 1;
            } else {
                $seen[$id] = 1;
            }
        }
        $headings[] = Heading{level: markdown.level($node), text: $text, id: $id};
        if ($title == "" and markdown.level($node) == 1) {
            $title = $text;
        }
        # Close the section the previous heading opened before starting the next.
        if ($sectionHeading != "" or len($buffer) > 0) {
            $sections[] = Section{
                anchor: $anchor,
                heading: $sectionHeading,
                text: strings.join($buffer, " ")
            };
        }
        $buffer = [];
        $anchor = $id;
        $sectionHeading = $text;
        $out[] = renderHeading($node, $id);
    }
    if ($sectionHeading != "" or len($buffer) > 0) {
        $sections[] = Section{
            anchor: $anchor,
            heading: $sectionHeading,
            text: strings.join($buffer, " ")
        };
    }
    return Rendered{
        html: strings.join($out, "\n"),
        title: $title,
        headings: $headings,
        sections: $sections
    };
}

/**
 * The contents list for a page, as HTML: every heading from level 2 down to
 * `maxLevel`. A page with fewer than two such headings gets no contents list at
 * all - a single entry is noise, not navigation.
 * @param headings {list of Heading} the page's headings
 * @param maxLevel {int} the deepest level to include
 * @return {string} the list HTML, or "" when there is nothing worth listing
 */
export func tocHtml(headings as list of Heading, maxLevel as int) {
    def rows as list of string;
    for (def h in $headings) {
        if ($h.level < 2 or $h.level > $maxLevel) {
            continue;
        }
        $rows[] = '<li data-level="' + convert.toString($h.level) + '"><a href="#' +
            attrEsc($h.id) + '">' + html.escape($h.text) + "</a></li>";
    }
    if (len($rows) < 2) {
        return "";
    }
    return "<ol>" + strings.join($rows, "") + "</ol>";
}
