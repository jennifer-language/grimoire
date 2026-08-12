# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The printable build: the whole book as one paginated PDF, laid out by the
 * `markdown` module over `pdf`.
 *
 * The work here is turning a pile of independent pages into one document. Every
 * chapter owns a level-one heading, which would flatten the book into a list of
 * peers, so chapter headings are demoted one level and the part headings from
 * `SUMMARY.md` take their place at the top - giving the PDF outline the same
 * part / chapter / section shape the sidebar has. A cover page carries the
 * title, authors, and build date, and the document Info dictionary is filled in
 * so the file identifies itself in a reader.
 * @module pdfbook
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use io;
use os;
use strings;
use convert;
use regex;
use maps;
use fs;
use path;
use time;
use encoding;

import "markdown.j" as markdown;
import "pdf.j" as pdf;
import "./config.j" as config;
import "./palette.j" as palette;
import "./theme.j" as theme;
import "./summary.j" as summary;
import "./util.j" as util;

# How far the page-number footer sits from the bottom edge, in points. Inside the
# 48-point page margin, so it never collides with the text block above it.
def const FOOTER_MARGIN as int init 30;

# A4 and US Letter in PDF points, the two sizes the configuration offers.
def const A4_WIDTH as int init 595;
def const A4_HEIGHT as int init 842;
def const LETTER_WIDTH as int init 612;
def const LETTER_HEIGHT as int init 792;

# --- text sanitising ------------------------------------------------
#
# The standard-14 PDF fonts encode WinAnsi (windows-1252), which covers Latin-1
# plus the typographic quotes, dashes, ellipsis, and bullet - but not arrows, box
# drawing, or check marks, all of which turn up in technical prose. Rather than
# let one arrow abort a whole book, transliterate what has an obvious ASCII
# reading and replace the rest with a question mark.
#
# The pass is layered so the common case costs one call: try the whole document,
# then fall back to the offending line, then to the offending rune. Practically
# every line is clean, so the per-rune loop - which would be far too slow over
# megabytes of Markdown - only ever runs on the handful of lines that need it.

def const CODEC as string init "windows-1252";

def const TRANSLITERATIONS as map of string to string init {
    "←": "<-",
    "→": "->",
    "↔": "<->",
    "⇐": "<=",
    "⇒": "=>",
    "⇔": "<=>",
    "↑": "^",
    "↓": "v",
    "↵": "\\n",
    "⏎": "\\n",
    "≤": "<=",
    "≥": ">=",
    "≠": "!=",
    "≡": "==",
    "≈": "~=",
    "∞": "inf",
    "−": "-",
    "─": "-",
    "━": "-",
    "│": "|",
    "┃": "|",
    "┌": "+",
    "┐": "+",
    "└": "+",
    "┘": "+",
    "├": "+",
    "┤": "+",
    "┬": "+",
    "┴": "+",
    "┼": "+",
    "═": "=",
    "║": "|",
    "✓": "yes",
    "✔": "yes",
    "✗": "no",
    "✘": "no",
    "✅": "yes",
    "❌": "no",
    "❤": "<3",
    "♥": "<3",
    "★": "*",
    "☆": "*",
    "▶": ">",
    "◀": "<",
    "●": "*",
    "■": "*",
    "…": "...",
    "␣": "_",
    "α": "alpha",
    "β": "beta",
    "γ": "gamma",
    "δ": "delta",
    "θ": "theta",
    "λ": "lambda",
    "π": "pi",
    "σ": "sigma",
    "φ": "phi",
    "ω": "omega"
};

# encodable reports whether the PDF font encoding can carry the whole string.
func encodable(s as string) {
    try {
        def probe as bytes init encoding.encode($s, CODEC);
        return len($probe) >= 0;
    } catch (e) {
        return false;
    }
}

# Codepoints that carry no glyph of their own: the emoji and text variation
# selectors, a zero-width joiner or space, a byte-order mark. They have no ASCII
# reading because they say nothing on their own - the character they modify does.
# Dropping them beats printing a question mark for something that was invisible
# to begin with.
func invisible(ch as string) {
    def cp as int init convert.toCodepoint($ch);
    return $cp == 0xFE0E or $cp == 0xFE0F or $cp == 0x200B or $cp == 0x200D or $cp == 0xFEFF;
}

func asciiFor(ch as string) {
    if (maps.has(TRANSLITERATIONS, $ch)) {
        return TRANSLITERATIONS[$ch];
    }
    if (invisible($ch)) {
        return "";
    }
    return "?";
}

func sanitizeLine(line as string) {
    if (encodable($line)) {
        return $line;
    }
    def out as list of string;
    for (def ch in strings.chars($line)) {
        if (encodable($ch)) {
            $out[] = $ch;
        } else {
            $out[] = asciiFor($ch);
        }
    }
    return strings.join($out, "");
}

/**
 * Replace every character the PDF font encoding cannot carry with an ASCII
 * reading, so a stray arrow or box-drawing rune cannot abort the whole render.
 * @param text {string} the text to sanitise
 * @return {string} text the standard-14 fonts can encode
 */
export func sanitize(text as string) {
    if (encodable($text)) {
        return $text;
    }
    def out as list of string;
    for (def line in strings.split($text, "\n")) {
        $out[] = sanitizeLine($line);
    }
    return strings.join($out, "\n");
}

# quotePrefix returns a line's leading blockquote markers (`> `, `> > `), which
# have to come off before the line can be read as anything else. A fenced block
# written inside a blockquote carries the marker on every line, the fences
# included - miss that and the fence is never recognised, and the code inside it
# gets rewritten as if it were prose.
func quotePrefix(line as string) {
    def out as list of string;
    for (def ch in strings.chars($line)) {
        if ($ch == ">" or $ch == " " or $ch == "\t") {
            $out[] = $ch;
            continue;
        }
        break;
    }
    def prefix as string init strings.join($out, "");
    if (not strings.contains($prefix, ">")) {
        return "";
    }
    return $prefix;
}

# fenceAt reports whether a line opens or closes a fenced code block, inside a
# blockquote or not. Headings and rules inside a fence are content, not
# structure, so every transform below has to know where the fences are.
func fenceAt(line as string) {
    def t as string init strings.trim($line);
    def prefix as string init quotePrefix($t);
    if ($prefix != "") {
        $t = strings.trim(strings.substring($t, len($prefix), len($t)));
    }
    return strings.startsWith($t, "```") or strings.startsWith($t, "~~~");
}

# headingLevel returns the ATX heading depth of a line, or 0 when it is not a
# heading.
func headingLevel(line as string) {
    def n as int init 0;
    for (def ch in strings.chars($line)) {
        if ($ch == "#") {
            $n = $n + 1;
        } else {
            break;
        }
    }
    if ($n == 0 or $n > 6) {
        return 0;
    }
    def rest as string init strings.substring($line, $n, len($line));
    if ($rest == "" or strings.startsWith($rest, " ")) {
        return $n;
    }
    return 0;
}

# --- links in print -------------------------------------------------
#
# The PDF layout does not nest inline spans, so a link inside `**bold**` arrives
# as flat text and is typeset as the literal `[label](target.md)`. Rewriting the
# links before layout fixes that, and is the right call for print anyway: a
# cross-reference to another chapter is not clickable on paper, so it should read
# as its label alone, while an external URL is worth keeping in parentheses
# because the URL is the only way a reader can follow it.

# An inline link or image: an optional `!`, a bracketed label, and a target with
# an optional quoted title.
def const LINK_INTERNAL as string init '!?\[([^\]]*)\]\(' +
    '(?:[^)\s]*\.md(?:#[^)\s]*)?|#[^)\s]*)(?:\s+"[^"]*")?\)';
def const LINK_OTHER as string init '!?\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)';

func printLinks(line as string) {
    if (not strings.contains($line, "](")) {
        return $line;
    }
    def out as string init regex.replace(LINK_INTERNAL, $line, "$1");
    return regex.replace(LINK_OTHER, $out, "$1 ($2)");
}

/**
 * Apply every print-only inline rewrite to one line, which means resolving links
 * for paper and nothing else: the layout nests inline spans itself, and hard-folds
 * a token too wide for its column, so neither needs help here. Exported so the
 * rewrite can be exercised directly, since it is the one place a bad pattern
 * mangles prose rather than failing loudly.
 * @param line {string} one line of Markdown, outside any fenced code block
 * @return {string} the rewritten line
 */
export func printLine(line as string) {
    return printLinks($line);
}

# prepare demotes a chapter's headings by `by` levels, resolves its links for
# paper, and leaves everything else exactly as written.
#
# "Exactly as written" is load-bearing: every line keeps its own indentation.
# Reflowing a paragraph here - gathering its lines and trimming each one - would
# strip the indent from a continuation line, and an indented continuation that
# loses its indent stops belonging to its list item and becomes a paragraph of
# its own, stranded between the items. The layout reflows paragraphs anyway.
func prepare(md as string, by as int) {
    def out as list of string;
    def inFence as bool init false;
    # Transliterate before the layout sees the text: the module substitutes a
    # single character for anything it cannot encode, which turns an arrow into
    # `?`, while `->` says what the arrow said.
    def source as string init sanitize($md);
    for (def line in strings.split($source, "\n")) {
        if (fenceAt($line)) {
            $inFence = not $inFence;
            $out[] = $line;
            continue;
        }
        # Inside a fence every line is content: no rewrite, and no folding either -
        # the layout folds a code line to the column width itself.
        if ($inFence) {
            $out[] = $line;
            continue;
        }
        def level as int init headingLevel($line);
        if ($level > 0) {
            def target as int init $level + $by;
            if ($target > 6) {
                $target = 6;
            }
            $out[] = strings.repeat("#", $target) +
                printLine(strings.substring($line, $level, len($line)));
            continue;
        }
        # Every other line keeps its own shape, indentation included: the layout
        # reflows paragraphs itself, and an indented line is how a continuation
        # stays inside the list item it belongs to.
        $out[] = printLine($line);
    }
    return strings.join($out, "\n");
}

# hasTitle reports whether a chapter carries its own level-one heading; one that
# does not gets its outline title inserted, so no chapter lands in the PDF
# unlabelled.
func hasTitle(md as string) {
    def inFence as bool init false;
    for (def line in strings.split($md, "\n")) {
        if (fenceAt($line)) {
            $inFence = not $inFence;
            continue;
        }
        if (not $inFence and headingLevel($line) == 1) {
            return true;
        }
    }
    return false;
}

# coverText prepares one configured value for the cover, which is assembled as
# Markdown and then parsed like any other page.
#
# The angle brackets matter. `mplx <jennifer@mplx.dev>` is the conventional way to
# write a name and an address, and it is also a CommonMark email autolink - so
# left alone it parses as a link and the brackets vanish, leaving `mplx
# jennifer@mplx.dev` on the title page. A backslash escape is no help here, since
# the module emits `\<` literally; a character reference is, because the parser
# resolves one back to the character it names.
#
# `&` goes first, or escaping it afterwards would corrupt the `&lt;` just written.
func coverText(value as string) {
    def out as string init strings.replace($value, "&", "&amp;");
    $out = strings.replace($out, "<", "&lt;");
    return strings.replace($out, ">", "&gt;");
}

# cover is the first page: title, description, authors, and the build date.
func cover(c as config.Config) {
    def out as list of string;
    $out[] = "# " + coverText($c.title);
    $out[] = "";
    if ($c.description != "") {
        $out[] = "*" + coverText($c.description) + "*";
        $out[] = "";
    }
    def authors as string init config.authorCredit($c);
    if ($authors != "") {
        $out[] = "**" + coverText($authors) + "**";
        $out[] = "";
    }
    # The build date, and only the build date: the tool credit belongs in the
    # document metadata, not on the reader's title page.
    $out[] = time.format(time.now(), "%Y-%m-%d");
    $out[] = "";
    return strings.join($out, "\n");
}

# The layout's page-break directive: a raw HTML comment on a line of its own,
# which the Markdown module parses into a page_break node. A comment because the
# same source still has to render as HTML, where a browser shows nothing.
def const PAGE_BREAK as string init "<!-- pagebreak -->";

# excluded reports whether a chapter is one the book keeps out of print.
#
# A pattern is a source path relative to `src`, matched exactly; one ending in
# `/` excludes everything beneath it. That is deliberately less than a glob: the
# thing being named is a chapter or a section of the outline, and both are
# already paths.
#
# The case this exists for is a section that is worth having on the site and
# worth not having on paper - a generated API reference of several hundred pages
# of tables, a coverage report - where the alternative is building the book twice
# and rendering the PDF from the smaller one.
func excluded(c as config.Config, src as string) {
    def rel as string init strings.replace($src, "\\", "/");
    for (def pattern in $c.pdfExclude) {
        if ($pattern == "") {
            continue;
        }
        if (strings.endsWith($pattern, "/")) {
            if (strings.startsWith($rel, $pattern)) {
                return true;
            }
            continue;
        }
        if ($rel == $pattern) {
            return true;
        }
    }
    return false;
}

/**
 * Assemble the whole book as one Markdown document, ready for the PDF layout: a
 * cover, then each part heading, then each chapter.
 *
 * `[pdf] exclude` drops chapters here rather than earlier, so the site keeps
 * them. A part whose chapters are all excluded is dropped with them - its
 * heading is held back until a chapter survives to sit under it, so the printed
 * book never carries a part title with nothing beneath it.
 *
 * Every chapter opens a page of its own, by one of two mechanisms.
 *
 * A chapter outside the parts - a prefix or suffix chapter, or every chapter in a
 * book with no parts at all - keeps its level-one heading, and the layout starts
 * a fresh page at every level-one heading. That is also what gives the cover a
 * page to itself.
 *
 * A chapter **under a part** is demoted one level, so the part heading can take
 * the top of the outline and the PDF bookmarks get the same part / chapter /
 * section shape the sidebar has. A demoted heading no longer breaks the page, so
 * the break is asked for explicitly with a `<!-- pagebreak -->` directive. The
 * exception is the chapter that opens a part: the part heading is itself a
 * level-one heading and has just broken the page, and a second break there would
 * leave the part title alone on a sheet of its own.
 * @param c {config.Config} the book configuration
 * @param entries {list of summary.Entry} the book outline
 * @return {string} the combined Markdown source
 */
export func combine(c as config.Config, entries as list of summary.Entry) {
    def parts as list of string;
    if ($c.pdfTitlePage) {
        $parts[] = cover($c);
    }
    def underPart as bool init false;
    def opensPart as bool init false;
    def pendingPart as string init "";
    for (def e in $entries) {
        if ($e.kind == summary.partKind()) {
            $underPart = true;
            $opensPart = true;
            $pendingPart = $e.title;
            continue;
        }
        if ($e.kind != summary.pageKind()) {
            continue;
        }
        def file as string init path.join($c.srcDir, $e.src);
        if (not fs.isFile($file)) {
            continue;
        }
        if (excluded($c, $e.src)) {
            if ($c.verbose) {
                io.printf("  skipped %s (excluded from the PDF)\n", $e.src);
            }
            continue;
        }
        if ($pendingPart != "") {
            $parts[] = "";
            $parts[] = "# " + $pendingPart;
            $parts[] = "";
            $pendingPart = "";
        }
        def shift as int init 0;
        if ($underPart) {
            $shift = 1;
        }
        if ($c.verbose) {
            io.printf("  chapter %s\n", $e.src);
        }
        def source as string init fs.readString($file);
        def body as string init prepare($source, $shift);
        $parts[] = "";
        # A demoted chapter has to ask for its page; an undemoted one gets it from
        # its own level-one heading, and the first chapter of a part gets it from
        # the part heading above.
        if ($underPart and not $opensPart) {
            $parts[] = PAGE_BREAK;
            $parts[] = "";
        }
        $opensPart = false;
        if (not hasTitle($source)) {
            $parts[] = strings.repeat("#", 1 + $shift) + " " + $e.title;
            $parts[] = "";
        }
        $parts[] = $body;
    }
    return sanitize(strings.join($parts, "\n"));
}

# The Grimoire credit, carried in the PDF metadata rather than on the title page.
# `Creator` is where a generator signs its work and `Producer` names what wrote
# the bytes; both are Grimoire here, since it is the tool in both roles.
def const GRIMOIRE_URL as string init "https://grimoire.jennifer-lang.dev/";
def const PDF_CREDIT as string init "Made with Grimoire - " + GRIMOIRE_URL;

# fillOf turns a palette colour into a layout fill.
func fillOf(hex as string) {
    def c as palette.Rgb init palette.parseHex($hex);
    return markdown.rgb($c.r, $c.g, $c.b);
}

# tintOf turns a palette colour into a fill mixed toward white, for a bar that
# has to sit behind black text.
func tintOf(hex as string, percent as int) {
    def c as palette.Rgb init palette.tint(palette.parseHex($hex), $percent);
    return markdown.rgb($c.r, $c.g, $c.b);
}

# options builds the layout options: the configured paper size, tighter margins
# than the module default (a reference book wants the width), heading bars and a
# table header band drawn from the book's own theme, and the document metadata.
#
# The theme's **light** palette is the one used: paper is white, so the dark
# palette's near-black surfaces would print as slabs of toner. Heading bars are
# the accent mixed toward white, deepest at level one, so the hierarchy reads at
# a glance and each theme keeps its identity in print.
/**
 * The layout options for a book: paper size, margins, fonts, the theme-derived
 * heading and table fills, and the document metadata. Exported so a build can be
 * timed phase by phase without reaching into the module.
 * @param c {config.Config} the book configuration
 * @return {markdown.PdfOptions} the layout options
 */
export func pdfOptions(c as config.Config) {
    return options($c);
}

func options(c as config.Config) {
    def opts as markdown.PdfOptions init markdown.pdfDefaults();
    $opts.pageWidth = A4_WIDTH;
    $opts.pageHeight = A4_HEIGHT;
    if ($c.pdfPaper == "letter") {
        $opts.pageWidth = LETTER_WIDTH;
        $opts.pageHeight = LETTER_HEIGHT;
    }
    $opts.margin = 48;
    $opts.bodySize = 10;
    $opts.tablePad = 3;
    def light as palette.Palette init theme.byName($c.theme).light;
    $opts.tableHeaderFill = fillOf($light.surfaceAlt);
    $opts.headingStyles = [
        markdown.headingStyle(tintOf($light.accent, 22)),
        markdown.headingStyle(tintOf($light.accent, 12)),
        markdown.headingStyle(tintOf($light.accent, 6)),
        markdown.headingStyle(fillOf($light.surface)),
        markdown.headingStyle(markdown.noFill()),
        markdown.headingStyle(markdown.noFill())
    ];
    # A blockquote gets a tinted panel and an accent bar down its left edge, and a
    # code block a panel with a hairline. Both are the theme's own colours, and
    # both are mixed well toward white: these sit behind black body text for whole
    # paragraphs at a time, so they have to read as a tint rather than as a band.
    $opts.quoteFill = tintOf($light.accent, 8);
    $opts.quoteRule = fillOf($light.accent);
    $opts.codeFill = fillOf($light.codeBg);
    $opts.codeBorder = fillOf($light.border);
    $opts.title = $c.title;
    $opts.author = config.authorLine($c);
    $opts.subject = $c.description;
    $opts.creator = PDF_CREDIT;
    $opts.producer = PDF_CREDIT;
    $opts.bookmarkLevel = $c.pdfBookmarkLevel;
    # The module substitutes this for anything the standard-14 fonts cannot
    # encode. Grimoire transliterates the characters worth keeping (an arrow, a
    # box-drawing rule) before the text ever gets here, so this is the last
    # resort for the rest, and a visible marker beats a silent hole.
    $opts.unencodable = "?";
    return $opts;
}

# gitOut runs one git command inside `dir` and returns its trimmed output, or ""
# when there is no answer to be had: git missing from the PATH, the directory not
# a repository, the command failing, or - on `jennifer-tiny`, which ships no
# `os/exec` - the call throwing outright. A version stamp is a nicety, and none of
# those is a reason to fail a build over it.
func gitOut(dir as string, args as list of string) {
    def argv as list of string init ["git", "-C", $dir];
    for (def a in $args) {
        $argv[] = $a;
    }
    try {
        def result as os.Result init os.run($argv);
        if ($result.exitCode != 0) {
            return "";
        }
        return strings.trim($result.stdout);
    } catch (e) {
        return "";
    }
}

# stamp reads one footer slot: an environment variable if the build sets one,
# otherwise git.
#
# The environment comes first because the place most likely to want a version
# stamp is the place least likely to be able to run git for it - a container
# build. The official Jennifer image carries no git at all, so a CI job that
# mounts its checkout and builds inside the image gets nothing out of
# `git describe`, while the runner outside it knows the answer perfectly well and
# can hand it over.
func stamp(name as string, dir as string, args as list of string) {
    def fromEnv as string init strings.trim(os.getEnv($name));
    if ($fromEnv != "") {
        return $fromEnv;
    }
    return gitOut($dir, $args);
}

# footerText fills the `{version}` and `{commit}` slots of the configured footer
# template from the book's own checkout.
#
# Exactly one of the two is ever non-empty: on a tagged commit the build has a
# version and the commit id is noise, and off a tag it has no version and the
# commit is the only thing that identifies the build. That is what lets one
# template cover both - `"Grimoire {version} Manual {commit}"` reads as
# "Grimoire 1.0.0 Manual" on a tag and "Grimoire Manual 0e173c1" off one - and
# why the result is squeezed afterwards, to close the gap the empty slot leaves.
#
# A leading `v` comes off the tag, so `v1.0.0` and `1.0.0` both print as 1.0.0.
func footerText(c as config.Config) {
    def describe as list of string init ["describe", "--tags", "--exact-match"];
    def tag as string init stamp("GRIMOIRE_VERSION", $c.srcDir, $describe);
    if (strings.startsWith($tag, "v")) {
        $tag = strings.substring($tag, 1, len($tag));
    }
    def commit as string init "";
    if ($tag == "") {
        def head as list of string init ["rev-parse", "--short", "HEAD"];
        $commit = stamp("GRIMOIRE_COMMIT", $c.srcDir, $head);
    }
    # Raw strings: a cooked "..." would read `{version}` as an interpolation.
    def out as string init strings.replace($c.pdfFooterLeft, '{version}', $tag);
    return util.squeeze(strings.replace($out, '{commit}', $commit));
}

# footer draws the running page footer: the book's version stamp on the left, the
# page number on the right. Either side alone is enough to want one; neither
# means no footer at all.
#
# This is why the render below goes through `renderPdfDoc` rather than straight
# to bytes: a page number needs the total, and the total does not exist until the
# whole book has been laid out. The label sits inside the bottom margin, below the
# text block, in the theme's muted colour - a footer is for placing yourself, not
# for reading.
func footer(c as config.Config, doc as pdf.Document) {
    def left as string init "";
    if ($c.pdfFooterLeft != "") {
        $left = footerText($c);
    }
    def right as string init "";
    if ($c.pdfPageNumbers) {
        $right = "%page%/%pages%";
    }
    if ($left == "" and $right == "") {
        return $doc;
    }
    def label as pdf.PageLabel init pdf.pageLabel();
    $label.left = sanitize($left);
    $label.right = $right;
    $label.size = 8;
    $label.margin = FOOTER_MARGIN;
    def muted as palette.Rgb init palette.parseHex(theme.byName($c.theme).light.muted);
    $label.red = $muted.r;
    $label.green = $muted.g;
    $label.blue = $muted.b;
    return pdf.setFooter($doc, $label);
}

/**
 * Render the book to PDF bytes.
 * @param c {config.Config} the book configuration
 * @param entries {list of summary.Entry} the book outline
 * @return {bytes} the PDF document
 * @throws {Error} kind "markdown" or "pdf" when a document cannot be laid out
 */
export func render(c as config.Config, entries as list of summary.Entry) {
    def tree as markdown.Node init markdown.parse(combine($c, $entries));
    return pdf.render(footer($c, markdown.renderPdfDoc($tree, options($c))));
}
