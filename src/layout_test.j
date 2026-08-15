# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `layout.j`, run by `jennifer test src/layout_test.j`.
 *
 * The shell is assembled from a dozen small emitters, and what makes it correct
 * is mostly what it leaves out: no sidebar when the book has none, no search
 * dialog when search is off, no repository link when none is configured. Those
 * are conditionals rather than markup, so each one has a case here in both
 * directions.
 *
 * The nine navigation-column arrangements get their own group. `layout.j` writes
 * the two data attributes and `palette.j` writes the selectors that read them -
 * neither file is wrong on its own, so the attribute names are pinned on both
 * sides.
 * @module layout_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use strings;

func english() {
    locale.install("en");
}

func view() {
    return View{
        title: "A Chapter",
        keywords: "",
        body: "<p>Body text.</p>",
        toc: "<ol><li><a href=\"#a\">A</a></li></ol>",
        root: "",
        prevTitle: "",
        prevHref: "",
        nextTitle: "",
        nextHref: "",
        editUrl: ""
    };
}

func entry(title as string, out as string, number as string) {
    return summary.Entry{
        kind: summary.pageKind(),
        title: $title,
        src: "",
        out: $out,
        level: 0,
        number: $number
    };
}

func outline() {
    return [
        entry("One", "one.html", "1"),
        summary.Entry{
            kind: summary.partKind(),
            title: "A Part",
            src: "",
            out: "",
            level: 0,
            number: ""
        },
        entry("Two", "two.html", "2"),
        summary.Entry{
            kind: summary.separatorKind(),
            title: "",
            src: "",
            out: "",
            level: 0,
            number: ""
        },
        summary.Entry{
            kind: summary.draftKind(),
            title: "Unwritten",
            src: "",
            out: "",
            level: 0,
            number: ""
        }
    ];
}

func shell(c as config.Config) {
    english();
    return page($c, view(), navHtml(navItems(outline(), true), "one.html", ""), noBrand());
}

# --- the brand constructors ------------------------------------------

# Exactly one of the two fields is ever set, which is what lets `brandMark`
# choose by testing them in order.
func testTheThreeBrandsAreMutuallyExclusive() {
    testing.assertEqual(noBrand().svg, "");
    testing.assertEqual(noBrand().image, "");
    testing.assertEqual(svgBrand("<svg/>").svg, "<svg/>");
    testing.assertEqual(svgBrand("<svg/>").image, "");
    testing.assertEqual(imageBrand("logo.png").image, "logo.png");
    testing.assertEqual(imageBrand("logo.png").svg, "");
}

# An SVG is inlined so it needs no second request and follows the colour mode;
# any other image is referenced, and its path is resolved per page.
func testBrandMarkInlinesSvgAndReferencesAnImage() {
    testing.assertContains(brandMark(svgBrand("<svg/>"), "", "T"), "<svg/>");
    testing.assertContains(brandMark(imageBrand("logo.png"), "../", "T"), 'src="../logo.png"');
    testing.assertContains(brandMark(imageBrand("logo.png"), "", "T"), 'alt="T"');
}

func testBrandMarkFallsBackToTheBookGlyph() {
    def mark as string init brandMark(noBrand(), "", "T");
    testing.assertContains($mark, "<svg");
    testing.assertFalse(strings.contains($mark, 'data-logo="true"'));
}

# --- navItems and navHtml --------------------------------------------

func testNavItemsPreRendersEveryRow() {
    def items as list of NavItem init navItems(outline(), true);
    testing.assertEqual(len($items), 5);
    testing.assertContains($items[0].label, "One");
    testing.assertEqual($items[0].out, "one.html");
}

func testNavItemsRendersMarkdownInTitles() {
    def items as list of NavItem init navItems([entry("`code` title", "x.html", "1")], false);
    testing.assertContains($items[0].label, "<code>code</code>");
}

func testNavItemsHonoursSectionNumbers() {
    testing.assertContains(navItems(outline(), true)[0].label, '<span class="gr-num">1.</span>');
    testing.assertFalse(strings.contains(navItems(outline(), false)[0].label, "gr-num"));
}

func testNavItemsLeavesASeparatorUnlabelled() {
    def items as list of NavItem init navItems(outline(), true);
    testing.assertEqual($items[3].label, "");
}

func testNavHtmlRendersEachKind() {
    def html as string init navHtml(navItems(outline(), true), "one.html", "");
    testing.assertContains($html, '<nav class="gr-nav"');
    testing.assertContains($html, '<li class="gr-part">');
    testing.assertContains($html, '<hr class="gr-sep">');
    testing.assertContains($html, '<span class="gr-draft">');
}

func testNavHtmlMarksTheCurrentPage() {
    def html as string init navHtml(navItems(outline(), true), "two.html", "");
    testing.assertContains($html, 'href="two.html" aria-current="page"');
    testing.assertFalse(strings.contains($html, 'href="one.html" aria-current'));
}

# Every href is written relative to the page that uses it, which is what makes a
# built site work from a subdirectory, from a web root, or straight off a disk.
func testNavHtmlWritesHrefsRelativeToThePage() {
    def html as string init navHtml(navItems(outline(), true), "guide/two.html", "../");
    testing.assertContains($html, 'href="../one.html"');
}

func testADraftIsNotALink() {
    def html as string init navHtml(navItems(outline(), true), "one.html", "");
    testing.assertFalse(strings.contains($html, ">Unwritten</a>"));
}

# --- the top bar -----------------------------------------------------

func testTopbarCarriesTheTitleAndModeSelector() {
    english();
    def bar as string init topbar(config.defaults(), view(), noBrand());
    testing.assertContains($bar, "Documentation");
    testing.assertContains($bar, 'class="gr-modes"');
    testing.assertContains($bar, 'data-mode="light"');
    testing.assertContains($bar, 'data-mode="dark"');
    testing.assertContains($bar, 'data-mode="auto"');
}

func testTheSearchButtonFollowsTheSearchSetting() {
    english();
    def c as config.Config init config.defaults();
    testing.assertContains(topbar($c, view(), noBrand()), 'id="gr-search-open"');
    $c.search = false;
    testing.assertFalse(strings.contains(topbar($c, view(), noBrand()), "gr-search-open"));
}

func testTheRepositoryLinkAppearsOnlyWhenConfigured() {
    english();
    def c as config.Config init config.defaults();
    testing.assertFalse(strings.contains(topbar($c, view(), noBrand()), "gr-icon-btn\" href"));
    $c.repoUrl = "https://example.com/book";
    def bar as string init topbar($c, view(), noBrand());
    testing.assertContains($bar, "https://example.com/book");
    testing.assertContains($bar, 'title="Source"');
}

# A repository URL is configuration, but it still goes through the same URL gate
# as anything else that lands in an href.
func testTheRepositoryLinkIsGated() {
    english();
    def c as config.Config init config.defaults();
    $c.repoUrl = "javascript:alert(1)";
    testing.assertFalse(strings.contains(
        strings.lower(topbar($c, view(), noBrand())),
        "javascript:"));
}

# --- the pager -------------------------------------------------------

func testThePagerLinksBothWays() {
    english();
    def v as View init view();
    $v.prevTitle = "Before";
    $v.prevHref = "before.html";
    $v.nextTitle = "After";
    $v.nextHref = "after.html";
    def html as string init pager($v);
    testing.assertContains($html, 'class="gr-prev" href="before.html" rel="prev"');
    testing.assertContains($html, 'class="gr-next" href="after.html" rel="next"');
}

func testThePagerDisappearsOnALoneChapter() {
    english();
    testing.assertEqual(pager(view()), "");
}

func testThePagerCopesWithOneSideOnly() {
    english();
    def v as View init view();
    $v.nextTitle = "After";
    $v.nextHref = "after.html";
    def html as string init pager($v);
    testing.assertContains($html, "gr-next");
    testing.assertFalse(strings.contains($html, "gr-prev"));
}

# --- the footer ------------------------------------------------------

# The footer is the book owner's own configuration, so it is emitted verbatim: a
# credit that wants to carry a link can just write the anchor.
func testTheFooterIsVerbatim() {
    english();
    def c as config.Config init config.defaults();
    $c.footer = '<a href="https://example.com">Us</a>';
    testing.assertContains(footer($c, view()), '<a href="https://example.com">Us</a>');
}

func testTheFooterCarriesTheAuthorCredit() {
    english();
    def c as config.Config init config.defaults();
    $c.authors = ["Ada"];
    testing.assertContains(footer($c, view()), "Written by Ada");
}

func testTheEditLinkAppearsOnlyWhenSet() {
    english();
    def c as config.Config init config.defaults();
    testing.assertFalse(strings.contains(footer($c, view()), "Edit this page"));
    def v as View init view();
    $v.editUrl = "https://example.com/edit/x.md";
    testing.assertContains(footer($c, $v), "Edit this page");
}

func testAnEmptyFooterIsNoFooterAtAll() {
    english();
    def c as config.Config init config.defaults();
    $c.footer = "";
    testing.assertEqual(footer($c, view()), "");
}

# --- the contents column ---------------------------------------------

# An empty column rather than none at all: the width is reserved on every page,
# so a chapter with too few headings does not shift the text sideways.
func testAnEmptyTocStillReservesItsColumn() {
    english();
    def v as View init view();
    $v.toc = "";
    testing.assertEqual(tocColumn(config.defaults(), $v), '<aside class="gr-toc"></aside>');
}

func testTocColumnIsAbsentWhenTurnedOff() {
    english();
    def c as config.Config init config.defaults();
    $c.tocPosition = "off";
    testing.assertEqual(tocColumn($c, view()), "");
}

func testTocColumnCarriesItsHeading() {
    english();
    testing.assertContains(tocColumn(config.defaults(), view()), "On this page");
}

# --- the search dialog -----------------------------------------------

func testTheSearchDialogFollowsTheSetting() {
    english();
    def c as config.Config init config.defaults();
    testing.assertContains(searchDialog($c), 'id="gr-search"');
    $c.search = false;
    testing.assertEqual(searchDialog($c), "");
}

# The key caps stay as they are - Enter and Esc are what is printed on the
# keyboard in every language - and only the words around them translate.
func testTheSearchDialogKeepsItsKeyCaps() {
    english();
    def html as string init searchDialog(config.defaults());
    testing.assertContains($html, "<kbd class=\"gr-kbd\">Enter</kbd>");
    testing.assertContains($html, "<kbd class=\"gr-kbd\">Esc</kbd>");
}

# --- the document head -----------------------------------------------

func testHeadCombinesThePageAndBookTitles() {
    english();
    testing.assertContains(
        head(config.defaults(), view()),
        "<title>A Chapter - Documentation</title>");
}

func testHeadDoesNotRepeatTheBookTitle() {
    english();
    def v as View init view();
    $v.title = "Documentation";
    testing.assertContains(head(config.defaults(), $v), "<title>Documentation</title>");
}

func testHeadCarriesTheLanguageAndStylesheet() {
    english();
    def html as string init head(config.defaults(), view());
    testing.assertContains($html, '<html lang="en">');
    testing.assertContains($html, 'href="assets/grimoire.css"');
    testing.assertContains($html, '<meta name="generator" content="Grimoire">');
}

func testHeadResolvesAssetPathsPerPage() {
    english();
    def v as View init view();
    $v.root = "../";
    testing.assertContains(head(config.defaults(), $v), 'href="../assets/grimoire.css"');
}

func testOptionalMetaTagsAreOmittedWhenEmpty() {
    english();
    def html as string init head(config.defaults(), view());
    testing.assertFalse(strings.contains($html, 'name="description"'));
    testing.assertFalse(strings.contains($html, 'name="keywords"'));
    testing.assertFalse(strings.contains($html, 'rel="icon"'));
}

func testOptionalMetaTagsAppearWhenSet() {
    english();
    def c as config.Config init config.defaults();
    $c.description = "About the thing";
    $c.favicon = "icon.png";
    $c.authors = ["Ada"];
    def v as View init view();
    $v.keywords = "one, two";
    def html as string init head($c, $v);
    testing.assertContains($html, 'content="About the thing"');
    testing.assertContains($html, 'content="one, two"');
    testing.assertContains($html, 'href="icon.png"');
    testing.assertContains($html, 'name="author" content="Ada"');
}

# The mode is stamped on the root element before the first paint, so a reader who
# chose dark never gets a white flash between pages.
func testHeadCarriesTheBootScript() {
    english();
    testing.assertContains(head(config.defaults(), view()), "<script>");
}

# --- page: the whole shell -------------------------------------------

func testPageIsACompleteDocument() {
    def html as string init shell(config.defaults());
    testing.assertTrue(strings.startsWith($html, "<!DOCTYPE html>"));
    testing.assertTrue(strings.endsWith($html, "</html>\n"));
    testing.assertContains($html, "<body>");
    testing.assertContains($html, '<main class="gr-main"');
    testing.assertContains($html, "<p>Body text.</p>");
}

func testPageCarriesTheRuntimeSettings() {
    def html as string init shell(config.defaults());
    testing.assertContains($html, "window.grimoire = ");
    testing.assertContains($html, 'src="assets/grimoire.js"');
}

# `</script>` inside a JSON string would end the block early, and the only
# character that can start one is `<`.
func testTheSettingsBlobCannotBreakOutOfItsScript() {
    english();
    def c as config.Config init config.defaults();
    $c.highlight = true;
    $c.highlightJs = true;
    $c.highlightCdn = "https://example.com/</script><script>alert(1)";
    def html as string init page($c, view(), "", noBrand());
    testing.assertFalse(strings.contains($html, "</script><script>alert"));
    testing.assertContains($html, "\\u003c");
}

func testHighlightSettingsTravelOnlyWhenUsed() {
    english();
    def c as config.Config init config.defaults();
    testing.assertFalse(strings.contains(page($c, view(), "", noBrand()), "hlCdn"));
    $c.highlight = true;
    $c.highlightJs = true;
    testing.assertContains(page($c, view(), "", noBrand()), "hlCdn");
}

# --- the nine column arrangements ------------------------------------

# The attributes the stylesheet keys on. `layout.j` writes them and `palette.j`
# reads them, so both files pin the names.
func testTheShellCarriesBothPositions() {
    for (def nav in ["left", "right", "off"]) {
        for (def toc in ["left", "right", "off"]) {
            def c as config.Config init config.defaults();
            $c.navPosition = $nav;
            $c.tocPosition = $toc;
            testing.assertContains(
                shell($c),
                'class="gr-shell" data-nav="' + $nav +
                    '" data-toc="' + $toc + '"');
        }
    }
}

# Off means the markup is never emitted rather than hidden, so the pages are
# smaller and the outline is not rendered per page.
func testNavOffRemovesTheSidebarAndItsButton() {
    def c as config.Config init config.defaults();
    $c.navPosition = "off";
    def html as string init shell($c);
    testing.assertFalse(strings.contains($html, "gr-sidebar"));
    testing.assertFalse(strings.contains($html, "gr-backdrop"));
    testing.assertFalse(strings.contains($html, 'id="gr-menu"'));
}

func testNavOnKeepsTheSidebarAndItsButton() {
    def html as string init shell(config.defaults());
    testing.assertContains($html, 'id="gr-sidebar"');
    testing.assertContains($html, 'id="gr-backdrop"');
    testing.assertContains($html, 'id="gr-menu"');
}

func testTocOffRemovesTheColumn() {
    def c as config.Config init config.defaults();
    $c.tocPosition = "off";
    testing.assertFalse(strings.contains(shell($c), "gr-toc"));
}

# The top bar sits outside the shell but carries the same attribute, so the menu
# button can move to the end of the row when the drawer opens from the other edge.
func testTheTopBarKnowsWhichSideTheDrawerIsOn() {
    def c as config.Config init config.defaults();
    $c.navPosition = "right";
    testing.assertContains(shell($c), '<header class="gr-topbar" data-nav="right">');
}
