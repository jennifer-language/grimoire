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
 * `javascript:` href.
 * @module content
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use strings;
use convert;

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

# inner renders a styled span's content. A span the module reports no children
# for is a leaf - its own text, escaped.
func inner(n as markdown.Node) {
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
        when "strong" { return "<strong>" + inner($n) + "</strong>"; }
        when "emphasis" { return "<em>" + inner($n) + "</em>"; }
        when "link" {
            def title as string init markdown.attr($n, "title");
            def extra as string init "";
            if ($title != "") {
                $extra = ' title="' + attrEsc($title) + '"';
            }
            if (util.isExternal(markdown.attr($n, "href"))) {
                $extra = $extra + ' rel="noopener noreferrer"';
            }
            return '<a href="' + attrEsc(href(markdown.attr($n, "href"))) + '"' + $extra + ">" +
                inner($n) + "</a>";
        }
        when "image" {
            def alt as string init attrEsc(markdown.text($n));
            def title as string init markdown.attr($n, "title");
            def extra as string init "";
            if ($title != "") {
                $extra = ' title="' + attrEsc($title) + '"';
            }
            return '<img src="' + attrEsc(href(markdown.attr($n, "url"))) + '" alt="' + $alt +
                '" loading="lazy"' + $extra + ">";
        }
        else {
            # A block that turned up in inline position - a nested list, or the
            # paragraph the module now wraps a multi-line list item in - renders
            # through the block path.
            return renderBlock($n, false);
        }
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
    if (len($kids) == 0) {
        return html.escape($text);
    }
    return renderInline(markdown.children($kids[0]));
}

# --- block rendering -----------------------------------------------

func renderList(n as markdown.Node) {
    def tag as string init "ul";
    if (markdown.attr($n, "ordered") == "true") {
        $tag = "ol";
    }
    def out as list of string init ["<" + $tag + ">"];
    for (def item in markdown.children($n)) {
        $out[] = "<li>" + renderInline(markdown.children($item)) + "</li>";
    }
    $out[] = "</" + $tag + ">";
    return strings.join($out, "");
}

func renderRow(row as markdown.Node, cellTag as string) {
    def out as list of string init ["<tr>"];
    for (def cell in markdown.children($row)) {
        def align as string init markdown.attr($cell, "align");
        def attrs as string init "";
        if ($align != "" and $align != "left") {
            $attrs = ' data-align="' + attrEsc($align) + '"';
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

func renderCode(n as markdown.Node, highlighting as bool) {
    def lang as string init strings.trim(markdown.attr($n, "lang"));
    def code as string init markdown.text($n);
    def label as string init "";
    def classes as list of string;
    if ($lang != "") {
        $label = '<span class="gr-lang">' + html.escape($lang) + "</span>";
        $classes[] = "language-" + attrEsc(util.slugify($lang));
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

func renderQuote(n as markdown.Node, highlighting as bool) {
    def out as list of string init ["<blockquote>"];
    for (def child in markdown.children($n)) {
        $out[] = renderBlock($child, $highlighting);
    }
    $out[] = "</blockquote>";
    return strings.join($out, "");
}

# renderBlock covers every block kind except a top-level heading, which the page
# walk handles itself so it can attach the anchor id it assigned.
func renderBlock(n as markdown.Node, highlighting as bool) {
    match (markdown.typeOf($n)) {
        when "paragraph" { return "<p>" + renderInline(markdown.children($n)) + "</p>"; }
        when "heading" {
            def level as string init convert.toString(markdown.level($n));
            return "<h" + $level + ">" + renderInline(markdown.children($n)) + "</h" + $level + ">";
        }
        when "code" { return renderCode($n, $highlighting); }
        when "list" { return renderList($n); }
        when "table" { return renderTable($n); }
        when "quote" { return renderQuote($n, $highlighting); }
        when "thematic_break" { return "<hr>"; }
        # A hand-written block goes to the page verbatim - that is the point of
        # writing it. It comes from the book's own source, which is trusted the
        # same way the configured footer is; everything that comes from anywhere
        # else on this page is escaped.
        when "html_block" { return markdown.text($n); }
        # A page-break directive is print-only and has nothing to draw here.
        when "page_break" { return ""; }
        else {
            # An inline node in block position.
            return renderSpan($n);
        }
    }
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
 * @return {Rendered} the rendered page
 * @throws {Error} kind "markdown" when the document is too deep or too large
 */
export func render(md as string, highlighting as bool) {
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
        if (markdown.typeOf($node) != "heading") {
            $out[] = renderBlock($node, $highlighting);
            # Raw markup and a rule are both structure rather than prose, so
            # neither goes into the search index - nobody searches for a `<div>`.
            def kind as string init markdown.typeOf($node);
            if ($kind == "html_block" or $kind == "thematic_break") {
                continue;
            }
            def flat as string init util.squeeze(markdown.text($node));
            if ($flat != "") {
                $buffer[] = $flat;
            }
            continue;
        }
        def text as string init util.squeeze(markdown.text($node));
        def base as string init util.slugify($text);
        def id as string init util.uniqueSlug($seen, $base);
        $seen = util.remember($seen, $base);
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
