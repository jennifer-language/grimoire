# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `figure.j`, run by `jennifer test plugins/figure_test.j`.
 *
 * What matters is which pictures are figures and which are prose, where the
 * caption comes from, and that the two output forms are the two they claim to
 * be: Markdown that reaches the printable book, and a `<figure>` that does not.
 * @module figure_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;

def const NO_SETTINGS as string init '{}';

func requestFor(settings as string, content as string) {
    return '{"api":1,"kind":"preprocessor","book":{"title":"A Book","description":"d",' +
        '"authors":["Ada"],"language":"en","src":"docs","out":"site"},' +
        '"plugin":{"name":"figure","settings":' + $settings + '},' +
        '"entries":[],"chapters":[{"src":"index.md","content":' +
        json.encode($content) + '}]}';
}

func testTheTitleIsSplitOffTheDestination() {
    def p as Picture init pictureOf("A build", 'pipeline.png "How a book is built"');
    testing.assertEqual($p.src, "pipeline.png");
    testing.assertEqual($p.title, "How a book is built");
    testing.assertEqual($p.alt, "A build");
    def plain as Picture init pictureOf("A build", "pipeline.png");
    testing.assertEqual($plain.src, "pipeline.png");
    testing.assertEqual($plain.title, "");
}

# A path can hold a space and no title; a title can be in single quotes.
func testADestinationWithNoTitleIsLeftWhole() {
    testing.assertEqual(pictureOf("a", "img/one two.png").src, "img/one two.png");
    testing.assertEqual(pictureOf("a", "x.png 'quoted'").title, "quoted");
}

# `auto` is what a book that wrote both meant by writing both.
func testTheCaptionComesFromWhereTheBookSays() {
    def both as Picture init Picture{alt: "the alt", src: "x.png", title: "the title"};
    testing.assertEqual(captionOf($both, "auto"), "the title");
    testing.assertEqual(captionOf($both, "alt"), "the alt");
    testing.assertEqual(captionOf($both, "title"), "the title");
    def altOnly as Picture init Picture{alt: "the alt", src: "x.png", title: ""};
    testing.assertEqual(captionOf($altOnly, "auto"), "the alt");
    testing.assertEqual(captionOf($altOnly, "title"), "");
}

func aCaptionFromNowhere() {
    captionOf(Picture{alt: "a", src: "x.png", title: ""}, "somewhere");
}

func testACaptionSourceThatIsNoneOfTheThreeIsRefused() {
    testing.assertThrows("aCaptionFromNowhere", "plugin");
}

# The default form reaches the site, the EPUB and the printable book, which is
# the whole reason it is the default.
func testTheDefaultFormIsMarkdown() {
    def out as string init expand('![A build](p.png "How it works")' + "\n", "auto", false);
    testing.assertEqual($out, "![A build](p.png)\n\n*How it works*\n");
}

func testTheMarkupFormIsAFigure() {
    def out as string init expand('![A build](p.png "How it works")' + "\n", "auto", true);
    testing.assertContains($out, '<figure class="gr-figure">');
    testing.assertContains($out, '<img src="p.png" alt="A build"/>');
    testing.assertContains($out, "<figcaption>How it works</figcaption>");
}

# The caption and the alt text reach an attribute and an element, so a picture
# whose alt text holds markup cannot put markup in the page.
func testTextThatLooksLikeMarkupIsEscaped() {
    def out as string init expand('![a <b> & c](p.png "x & y")' + "\n", "auto", true);
    testing.assertContains($out, 'alt="a &lt;b&gt; &amp; c"');
    testing.assertContains($out, "<figcaption>x &amp; y</figcaption>");
}

# A picture inside a sentence is part of the sentence.
func testAPictureInASentenceIsLeftAlone() {
    def content as string init 'Text with ![an icon](i.png "Icon") in it.' + "\n";
    testing.assertEqual(expand($content, "auto", false), $content);
}

# A book that wrote no title and no alt text said what it wanted.
func testAPictureWithNothingToSayGetsNoCaption() {
    def content as string init "![](p.png)\n";
    testing.assertEqual(expand($content, "auto", false), $content);
}

func testFencedCodeIsLeftAlone() {
    def content as string init "```markdown\n" + '![A build](p.png "How it works")' + "\n```\n";
    testing.assertEqual(expand($content, "auto", false), $content);
}

func testSurroundingProseIsUntouched() {
    def content as string init "Before.\n\n" + '![A build](p.png "Caption")' + "\n\nAfter.\n";
    def out as string init expand($content, "auto", false);
    testing.assertContains($out, "Before.\n\n![A build](p.png)\n\n*Caption*\n\nAfter.");
}

func testTheReplyCarriesOnlyWhatChanged() {
    def out as string init replyFor(json.decode(requestFor(
        NO_SETTINGS,
        'A picture:' + "\n\n" + '![A build](p.png "Caption")' + "\n")));
    testing.assertEqual(json.length(json.decode($out), "/chapters"), 1);
    def quiet as string init replyFor(json.decode(requestFor(NO_SETTINGS, "No pictures.\n")));
    testing.assertEqual(json.length(json.decode($quiet), "/chapters"), 0);
}

func testRunCaptionsTheBook() {
    def content as string init '![A build](p.png "Caption")' + "\n";
    testing.assertEqual(run(requestFor(NO_SETTINGS, $content)), 0);
}

func testRunRefusesARequestItCannotAnswer() {
    def req as string init requestFor(NO_SETTINGS, "plain\n");
    testing.assertEqual(run(strings.replace($req, '"api":1', '"api":2')), 1);
    testing.assertEqual(run(strings.replace($req, '"preprocessor"', '"renderer"')), 1);
    testing.assertEqual(run(""), 1);
}
