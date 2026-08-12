# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The page shell: the document head, the top bar with its colour-mode selector
 * and search button, the sidebar built from the book outline, the contents
 * column, the previous / next pager, and the search dialog.
 *
 * Every asset path is written relative to the page that uses it, so a built site
 * works unchanged from a subdirectory, from a web root, or straight off the
 * filesystem.
 * @module layout
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use strings;
use json;
use convert;

import "html.j" as html;
import "./config.j" as config;
import "./summary.j" as summary;
import "./content.j" as content;
import "./assets.j" as assets;

/**
 * Everything that varies from page to page, gathered so the shell takes one
 * argument instead of a dozen.
 * @field title {string} the page title
 * @field keywords {string} the page's `keywords` meta tag value ("" for none)
 * @field body {string} the rendered body HTML
 * @field toc {string} the contents list HTML ("" for none)
 * @field root {string} the `../` prefix from this page back to the site root
 * @field prevTitle {string} the previous page's label, as rendered HTML ("" for none)
 * @field prevHref {string} the previous page's href
 * @field nextTitle {string} the next page's label, as rendered HTML ("" for none)
 * @field nextHref {string} the next page's href
 * @field editUrl {string} the edit-this-page URL ("" for none)
 */
export def struct View {
    title as string,
    keywords as string,
    body as string,
    toc as string,
    root as string,
    prevTitle as string,
    prevHref as string,
    nextTitle as string,
    nextHref as string,
    editUrl as string
};

# --- icons ---------------------------------------------------------
#
# Inline SVG rather than an icon font: one less request, no flash of missing
# glyphs, and `currentColor` makes every icon follow the active colour mode.

def const SVG_OPEN as string init '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">';

def const ICON_MENU as string init SVG_OPEN +
    '<path d="M4 7h16M4 12h16M4 17h16"/></svg>';

def const ICON_SEARCH as string init SVG_OPEN +
    '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>';

def const ICON_SUN as string init SVG_OPEN + '<circle cx="12" cy="12" r="4"/>' +
    '<path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2' +
    'M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>';

def const ICON_MOON as string init SVG_OPEN +
    '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>';

def const ICON_AUTO as string init SVG_OPEN +
    '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/></svg>';

def const ICON_BOOK as string init SVG_OPEN +
    '<path d="M4 4.5A2.5 2.5 0 0 1 6.5 2H20v18H6.5A2.5 2.5 0 0 0 4 22z"/>' +
    '<path d="M4 17.5A2.5 2.5 0 0 1 6.5 15H20"/></svg>';

def const ICON_LINK as string init SVG_OPEN +
    '<path d="M14 4h6v6"/><path d="M20 4 10 14"/>' +
    '<path d="M18 14v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4"/></svg>';

func attrEsc(s as string) {
    return strings.replace(html.escape($s), '"', "&quot;");
}

/**
 * The mark drawn beside the title in the top-left corner: a book's own logo, or
 * the default book glyph when it has none.
 *
 * An SVG logo is inlined rather than linked, so it needs no second request and
 * its `currentColor` strokes follow the active colour mode; any other image is
 * referenced, and its path is resolved per page. Exactly one of the two fields
 * is ever set.
 * @field svg {string} inline SVG markup ("" when there is none)
 * @field image {string} an image path relative to the site root ("" when there is none)
 */
export def struct Brand {
    svg as string,
    image as string
};

/**
 * The default mark: no logo configured.
 * @return {Brand} an empty brand
 */
export func noBrand() {
    return Brand{svg: "", image: ""};
}

/**
 * A brand from inline SVG markup.
 * @param svg {string} the SVG element source
 * @return {Brand} the brand
 */
export func svgBrand(svg as string) {
    return Brand{svg: $svg, image: ""};
}

/**
 * A brand from an image path, relative to the site root.
 * @param image {string} the image path
 * @return {Brand} the brand
 */
export func imageBrand(image as string) {
    return Brand{svg: "", image: $image};
}

func brandMark(b as Brand, root as string, title as string) {
    if ($b.svg != "") {
        return '<span class="gr-mark" data-logo="true" aria-hidden="true">' + $b.svg + "</span>";
    }
    if ($b.image != "") {
        return '<span class="gr-mark" data-logo="true"><img src="' + attrEsc($root + $b.image) +
            '" alt="' + attrEsc($title) + '"></span>';
    }
    return '<span class="gr-mark" aria-hidden="true">' + ICON_BOOK + "</span>";
}

# --- sidebar -------------------------------------------------------

/**
 * One sidebar row with its label already rendered. The sidebar is rebuilt for
 * every page - the hrefs are relative to the reader's position and the current
 * entry carries a marker - but the labels are Markdown and parsing them once per
 * page would mean parsing the whole outline once per chapter. Pre-rendering them
 * turns the per-page work into string concatenation.
 * @field kind {string} the outline entry kind
 * @field label {string} the rendered inner HTML of the row
 * @field out {string} the page path, relative to the site root
 * @field level {int} the nesting depth
 */
export def struct NavItem {
    kind as string,
    label as string,
    out as string,
    level as int
};

/**
 * Pre-render the sidebar rows for a book outline. Call once per build and pass
 * the result to `navHtml` for each page.
 * @param entries {list of summary.Entry} the book outline
 * @param numbers {bool} whether to show section numbers
 * @return {list of NavItem} the pre-rendered rows
 */
export func navItems(entries as list of summary.Entry, numbers as bool) {
    def out as list of NavItem;
    for (def e in $entries) {
        def label as string init "";
        if ($e.kind != summary.separatorKind()) {
            def number as string init "";
            if ($numbers and $e.number != "") {
                $number = '<span class="gr-num">' + html.escape($e.number) + ".</span>";
            }
            $label = $number + "<span>" + content.inline($e.title) + "</span>";
        }
        $out[] = NavItem{kind: $e.kind, label: $label, out: $e.out, level: $e.level};
    }
    return $out;
}

func navRow(item as NavItem, current as string, root as string) {
    if ($item.kind == summary.separatorKind()) {
        return '<li><hr class="gr-sep"></li>';
    }
    if ($item.kind == summary.partKind()) {
        return '<li class="gr-part">' + $item.label + "</li>";
    }
    def level as string init ' data-level="' + convert.toString($item.level) + '"';
    if ($item.kind == summary.draftKind()) {
        return "<li" + $level + '><span class="gr-draft">' + $item.label + "</span></li>";
    }
    def marker as string init "";
    if ($item.out == $current) {
        $marker = ' aria-current="page"';
    }
    return "<li" + $level + '><a href="' + attrEsc($root + $item.out) + '"' + $marker + ">" +
        $item.label + "</a></li>";
}

/**
 * The sidebar navigation for one page: the whole book outline, with the current
 * page marked and every href written relative to it.
 * @param items {list of NavItem} the pre-rendered rows from `navItems`
 * @param current {string} the current page path, relative to the site root
 * @param root {string} the `../` prefix back to the site root
 * @return {string} the navigation HTML
 */
export func navHtml(items as list of NavItem, current as string, root as string) {
    def rows as list of string;
    for (def item in $items) {
        $rows[] = navRow($item, $current, $root);
    }
    return '<nav class="gr-nav" aria-label="Book contents"><ol>' + strings.join($rows, "") +
        "</ol></nav>";
}

# --- chrome pieces -------------------------------------------------

func modeSelector() {
    def out as string init '<div class="gr-modes" role="radiogroup" aria-label="Colour mode">';
    $out = $out + '<button type="button" role="radio" data-mode="light" aria-checked="false" ' +
        'title="Light" aria-label="Light">' + ICON_SUN + "</button>";
    $out = $out + '<button type="button" role="radio" data-mode="auto" aria-checked="false" ' +
        'title="Match the system" aria-label="Match the system">' + ICON_AUTO + "</button>";
    $out = $out + '<button type="button" role="radio" data-mode="dark" aria-checked="false" ' +
        'title="Dark" aria-label="Dark">' + ICON_MOON + "</button>";
    return $out + "</div>";
}

func topbar(c as config.Config, v as View, b as Brand) {
    def out as string init '<header class="gr-topbar">';
    $out = $out + '<button class="gr-btn gr-icon-btn" id="gr-menu" type="button" ' +
        'aria-expanded="false" aria-controls="gr-sidebar" aria-label="Toggle navigation">' +
        ICON_MENU + "</button>";
    $out = $out + '<a class="gr-brand" href="' + attrEsc($v.root + "index.html") + '">' +
        brandMark($b, $v.root, $c.title) + html.escape($c.title) + "</a>";
    $out = $out + '<span class="gr-spacer"></span>';
    if ($c.search) {
        $out = $out + '<button class="gr-btn gr-searchbtn" id="gr-search-open" type="button" ' +
            'aria-label="Search">' + ICON_SEARCH + "<span>Search</span>" +
            '<kbd class="gr-kbd">/</kbd></button>';
    }
    $out = $out + modeSelector();
    if ($c.repoUrl != "") {
        $out = $out + '<a class="gr-btn gr-icon-btn" href="' + attrEsc(html.safeUrl($c.repoUrl)) +
            '" rel="noopener noreferrer" title="' + attrEsc($c.repoLabel) + '" aria-label="' +
            attrEsc($c.repoLabel) + '">' + ICON_LINK + "</a>";
    }
    return $out + "</header>";
}

func pager(v as View) {
    if ($v.prevTitle == "" and $v.nextTitle == "") {
        return "";
    }
    def out as string init '<nav class="gr-pager" aria-label="Chapter navigation">';
    if ($v.prevTitle != "") {
        $out = $out + '<a class="gr-prev" href="' + attrEsc($v.prevHref) + '" rel="prev">' +
            '<span class="gr-dir">Previous</span><span class="gr-title">' +
            $v.prevTitle + "</span></a>";
    }
    if ($v.nextTitle != "") {
        $out = $out + '<a class="gr-next" href="' + attrEsc($v.nextHref) + '" rel="next">' +
            '<span class="gr-dir">Next</span><span class="gr-title">' +
            $v.nextTitle + "</span></a>";
    }
    return $out + "</nav>";
}

func footer(c as config.Config, v as View) {
    def bits as list of string;
    if ($c.footer != "") {
        # Verbatim, not escaped and not parsed as Markdown: the footer is the
        # book owner's own configuration, so a credit that wants to carry a link
        # can just write the anchor.
        $bits[] = "<span>" + $c.footer + "</span>";
    }
    def authors as string init config.authorCredit($c);
    if ($authors != "") {
        $bits[] = "<span>" + html.escape($authors) + "</span>";
    }
    if ($v.editUrl != "") {
        $bits[] = '<a href="' + attrEsc(html.safeUrl($v.editUrl)) +
            '" rel="noopener noreferrer">Edit this page</a>';
    }
    if (len($bits) == 0) {
        return "";
    }
    return '<footer class="gr-footer">' + strings.join($bits, "") + "</footer>";
}

func tocColumn(v as View) {
    if ($v.toc == "") {
        return '<aside class="gr-toc"></aside>';
    }
    return '<aside class="gr-toc" aria-label="On this page"><div class="gr-toc-inner">' +
        "<h2>On this page</h2>" + $v.toc + "</div></aside>";
}

func searchDialog(c as config.Config) {
    if (not $c.search) {
        return "";
    }
    return '<div class="gr-search" id="gr-search" hidden role="dialog" aria-modal="true" ' +
        'aria-label="Search"><div class="gr-search-panel"><div class="gr-search-head">' +
        ICON_SEARCH + '<input id="gr-search-input" type="search" autocomplete="off" ' +
        'spellcheck="false" placeholder="Search the book" aria-label="Search the book">' +
        '</div><p class="gr-empty" id="gr-empty">Type to search the book.</p>' +
        '<ul class="gr-results" id="gr-results"></ul><div class="gr-search-foot">' +
        '<span><kbd class="gr-kbd">&uarr;</kbd> <kbd class="gr-kbd">&darr;</kbd> to move</span>' +
        '<span><kbd class="gr-kbd">Enter</kbd> to open</span>' +
        '<span><kbd class="gr-kbd">Esc</kbd> to close</span></div></div></div>';
}

func head(c as config.Config, v as View) {
    def title as string init $c.title;
    if ($v.title != "" and $v.title != $c.title) {
        $title = $v.title + " - " + $c.title;
    }
    def out as list of string;
    $out[] = "<!DOCTYPE html>";
    $out[] = '<html lang="' + attrEsc($c.language) + '">';
    $out[] = "<head>";
    $out[] = '<meta charset="utf-8">';
    $out[] = '<meta name="viewport" content="width=device-width, initial-scale=1">';
    $out[] = "<title>" + html.escape($title) + "</title>";
    if ($c.description != "") {
        $out[] = '<meta name="description" content="' + attrEsc($c.description) + '">';
    }
    def authors as string init config.authorLine($c);
    if ($authors != "") {
        $out[] = '<meta name="author" content="' + attrEsc($authors) + '">';
    }
    if ($v.keywords != "") {
        $out[] = '<meta name="keywords" content="' + attrEsc($v.keywords) + '">';
    }
    $out[] = '<meta name="generator" content="Grimoire">';
    $out[] = '<meta property="og:title" content="' + attrEsc($title) + '">';
    $out[] = '<meta property="og:type" content="article">';
    if ($c.favicon != "") {
        $out[] = '<link rel="icon" href="' + attrEsc($v.root + $c.favicon) + '">';
    }
    $out[] = '<link rel="stylesheet" href="' + attrEsc($v.root + "assets/grimoire.css") + '">';
    # The mode is stamped on the root element before the first paint, so a reader
    # who chose dark never gets a white flash between pages.
    $out[] = "<script>" + assets.boot($c.defaultMode) + "</script>";
    $out[] = "</head>";
    return strings.join($out, "\n");
}

/**
 * Render a complete HTML page.
 * @param c {config.Config} the book configuration
 * @param v {View} the per-page values
 * @param nav {string} the sidebar navigation HTML for this page
 * @param b {Brand} the mark drawn beside the title
 * @return {string} the complete HTML document
 */
export func page(c as config.Config, v as View, nav as string, b as Brand) {
    def out as list of string;
    $out[] = head($c, $v);
    $out[] = "<body>";
    $out[] = '<a class="gr-skip" href="#gr-main">Skip to content</a>';
    $out[] = topbar($c, $v, $b);
    $out[] = '<div class="gr-shell">';
    $out[] = '<div class="gr-backdrop" id="gr-backdrop" data-open="false"></div>';
    $out[] = '<div class="gr-sidebar" id="gr-sidebar" data-open="false">' + $nav + "</div>";
    $out[] = '<main class="gr-main" id="gr-main" tabindex="-1">';
    $out[] = '<article class="gr-content">';
    $out[] = $v.body;
    $out[] = "</article>";
    $out[] = pager($v);
    $out[] = footer($c, $v);
    $out[] = "</main>";
    $out[] = tocColumn($v);
    $out[] = "</div>";
    $out[] = searchDialog($c);
    # The runtime reads its configuration from this global: where the site root is
    # relative to this page, whether a search index was built, and how to fetch
    # highlight.js. Encoded through `json` rather than concatenated, so a CDN URL
    # or a language name out of the config cannot break out of the script.
    def settings as json.Value init json.map();
    $settings = json.set($settings, "/root", $v.root);
    $settings = json.set($settings, "/search", $c.search);
    if (config.usesHighlightJs($c)) {
        $settings = json.set($settings, "/hlCdn", $c.highlightCdn);
        $settings = json.set($settings, "/hlStyle", $c.highlightStyle);
        $settings = json.set($settings, "/hlStyleDark", $c.highlightStyleDark);
        def langs as json.Value init json.list();
        for (def lang in $c.highlightLanguages) {
            $langs = json.append($langs, "", $lang);
        }
        $settings = json.set($settings, "/hlLangs", $langs);
    }
    # `</script>` inside a JSON string would end the block early; the only
    # character that can start one is `<`, so escaping it closes the hole.
    $out[] = "<script>window.grimoire = " +
        strings.replace(json.encode($settings), "<", "\\u003c") + ";</script>";
    $out[] = '<script src="' + attrEsc($v.root + "assets/grimoire.js") + '" defer></script>';
    $out[] = "</body>";
    $out[] = "</html>";
    return strings.join($out, "\n") + "\n";
}
