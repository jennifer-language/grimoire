# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The theme model and the stylesheet generator. A `Theme` is a pair of
 * `Palette`s - one for light, one for dark - plus type and metric choices; the
 * generator turns it into a single stylesheet where every colour is a custom
 * property, so the dark mode is not an afterthought a theme can forget: writing
 * a theme means filling in both palettes.
 *
 * The layout rules themselves live in one constant sheet that only ever reads
 * `var(--gr-*)`, which is why a new theme is roughly thirty lines of colour and
 * nothing else.
 * @module palette
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use strings;
use convert;

/**
 * One colour scheme. Every field is a CSS colour, in whatever notation you
 * prefer, and every field is required - a theme that forgets one would render a
 * broken mode rather than a slightly different one.
 * @field bg {string} the page background
 * @field surface {string} raised surfaces: sidebar, code blocks, cards
 * @field surfaceAlt {string} hover and zebra-stripe fills
 * @field border {string} hairline rules and outlines
 * @field text {string} body text
 * @field muted {string} secondary text: captions, breadcrumbs, metadata
 * @field heading {string} heading text
 * @field accent {string} links, the active chapter, focus rings
 * @field accentHover {string} the accent under a pointer
 * @field onAccent {string} text drawn on top of an accent fill
 * @field codeText {string} code text
 * @field codeBg {string} inline-code and code-block background
 * @field selection {string} the text-selection highlight
 * @field shadow {string} the shadow colour, including its alpha
 */
export def struct Palette {
    bg as string,
    surface as string,
    surfaceAlt as string,
    border as string,
    text as string,
    muted as string,
    heading as string,
    accent as string,
    accentHover as string,
    onAccent as string,
    codeText as string,
    codeBg as string,
    selection as string,
    shadow as string
};

/**
 * A complete theme: identity, both colour schemes, the type stack, and the two
 * metrics that decide how the page is proportioned.
 * @field name {string} the identifier used in `grimoire.toml`
 * @field label {string} the human-readable name
 * @field description {string} a one-line summary, shown by `grimoire themes`
 * @field light {Palette} the light scheme
 * @field dark {Palette} the dark scheme
 * @field fontBody {string} the body font stack
 * @field fontHeading {string} the heading font stack
 * @field fontMono {string} the monospace font stack
 * @field radius {int} the corner radius, in pixels
 * @field contentWidth {int} the measure of the text column, in pixels
 */
export def struct Theme {
    name as string,
    label as string,
    description as string,
    light as Palette,
    dark as Palette,
    fontBody as string,
    fontHeading as string,
    fontMono as string,
    radius as int,
    contentWidth as int
};

# The three stacks every shipped theme draws from. Each ends in a generic family,
# so a host with none of the named faces still renders the intended shape.
def const STACK_SANS as string init 'ui-sans-serif, system-ui, -apple-system, "Segoe UI", ' +
    'Roboto, "Helvetica Neue", Arial, sans-serif';
def const STACK_SERIF as string init '"Iowan Old Style", "Palatino Linotype", Palatino, ' +
    '"Book Antiqua", Georgia, ui-serif, serif';
def const STACK_MONO as string init 'ui-monospace, "SF Mono", "JetBrains Mono", ' +
    '"Cascadia Code", Menlo, Consolas, "Liberation Mono", monospace';

/**
 * The default sans-serif stack.
 * @return {string} the font stack
 */
export func sans() {
    return STACK_SANS;
}

/**
 * The default serif stack.
 * @return {string} the font stack
 */
export func serif() {
    return STACK_SERIF;
}

/**
 * The default monospace stack.
 * @return {string} the font stack
 */
export func mono() {
    return STACK_MONO;
}

/**
 * Build a palette from its fourteen colours, in the order the struct declares
 * them. A positional builder keeps a theme file readable as a colour table.
 * @param bg {string} the page background
 * @param surface {string} raised surfaces
 * @param surfaceAlt {string} hover and stripe fills
 * @param border {string} hairlines
 * @param text {string} body text
 * @param muted {string} secondary text
 * @param heading {string} heading text
 * @param accent {string} links and active state
 * @param accentHover {string} the hovered accent
 * @param onAccent {string} text on an accent fill
 * @param codeText {string} code text
 * @param codeBg {string} code background
 * @param selection {string} the selection highlight
 * @param shadow {string} the shadow colour
 * @return {Palette} the palette
 */
export func palette(
    bg as string,
    surface as string,
    surfaceAlt as string,
    border as string,
    text as string,
    muted as string,
    heading as string,
    accent as string,
    accentHover as string,
    onAccent as string,
    codeText as string,
    codeBg as string,
    selection as string,
    shadow as string) {
    return Palette{
        bg: $bg,
        surface: $surface,
        surfaceAlt: $surfaceAlt,
        border: $border,
        text: $text,
        muted: $muted,
        heading: $heading,
        accent: $accent,
        accentHover: $accentHover,
        onAccent: $onAccent,
        codeText: $codeText,
        codeBg: $codeBg,
        selection: $selection,
        shadow: $shadow
    };
}

/**
 * A colour as three 0-255 channels - what the PDF layer wants, since it takes
 * `rgb(r, g, b)` integers rather than CSS notation.
 * @field r {int} red 0-255
 * @field g {int} green 0-255
 * @field b {int} blue 0-255
 */
export def struct Rgb {
    r as int,
    g as int,
    b as int
};

# hexDigit maps one hex character to its value, or -1. Written out rather than
# reached for through `convert`, which parses decimal only.
func hexDigit(ch as string) {
    def c as string init strings.lower($ch);
    def digits as string init "0123456789abcdef";
    def i as int init 0;
    for (def d in strings.chars($digits)) {
        if ($d == $c) {
            return $i;
        }
        $i = $i + 1;
    }
    return -1;
}

func hexPair(hex as string, at as int) {
    def hi as int init hexDigit(strings.substring($hex, $at, $at + 1));
    def lo as int init hexDigit(strings.substring($hex, $at + 1, $at + 2));
    if ($hi < 0 or $lo < 0) {
        return -1;
    }
    return $hi * 16 + $lo;
}

/**
 * Parse a `#rrggbb` palette colour into channels. A value in any other notation
 * - the `rgba(...)` a selection or shadow uses - has no single opaque colour to
 * report, so it comes back as mid grey rather than as an error: this is used to
 * tint a heading bar, and a slightly wrong bar beats a failed build.
 * @param hex {string} the colour, as `#rrggbb`
 * @return {Rgb} the channels
 */
export func parseHex(hex as string) {
    if (len($hex) != 7 or not strings.startsWith($hex, "#")) {
        return Rgb{r: 128, g: 128, b: 128};
    }
    def r as int init hexPair($hex, 1);
    def g as int init hexPair($hex, 3);
    def b as int init hexPair($hex, 5);
    if ($r < 0 or $g < 0 or $b < 0) {
        return Rgb{r: 128, g: 128, b: 128};
    }
    return Rgb{r: $r, g: $g, b: $b};
}

/**
 * Mix a colour toward white, keeping `percent` of it. This is what turns a theme
 * accent into a heading bar light enough to read black text on - and light enough
 * to survive a monochrome printer.
 * @param c {Rgb} the colour
 * @param percent {int} how much of the colour to keep, 0-100
 * @return {Rgb} the tinted colour
 */
export func tint(c as Rgb, percent as int) {
    def keep as int init $percent;
    if ($keep < 0) {
        $keep = 0;
    }
    if ($keep > 100) {
        $keep = 100;
    }
    def rest as int init 100 - $keep;
    return Rgb{
        r: ($c.r * $keep + 255 * $rest) // 100,
        g: ($c.g * $keep + 255 * $rest) // 100,
        b: ($c.b * $keep + 255 * $rest) // 100
    };
}

# The syntax palette. Unlike everything else here it is not per-theme: one pair
# tuned to sit on both a warm parchment and a cool slate surface reads better
# across ten themes than ten hand-tuned sets would, and it is one place to fix
# rather than ten. A book that wants different token colours can override the
# `--gr-syn-*` properties, or switch on highlight.js and pick any of its
# stylesheets - those load after this one and win.
def const SYNTAX_LIGHT as list of string init [
    "--gr-syn-comment: #9aa0a6",
    "--gr-syn-keyword: #a626a4",
    "--gr-syn-type: #0184bc",
    "--gr-syn-literal: #986801",
    "--gr-syn-string: #50a14f",
    "--gr-syn-number: #986801",
    "--gr-syn-variable: #e45649",
    "--gr-syn-symbol: #b26a00",
    "--gr-syn-builtin: #c18401",
    "--gr-syn-title: #4078f2"
];
def const SYNTAX_DARK as list of string init [
    "--gr-syn-comment: #7f848e",
    "--gr-syn-keyword: #c678dd",
    "--gr-syn-type: #56b6c2",
    "--gr-syn-literal: #d19a66",
    "--gr-syn-string: #98c379",
    "--gr-syn-number: #d19a66",
    "--gr-syn-variable: #e06c75",
    "--gr-syn-symbol: #e5c07b",
    "--gr-syn-builtin: #e5c07b",
    "--gr-syn-title: #61afef"
];

func syntaxVars(rows as list of string, indent as string) {
    def out as list of string;
    for (def row in $rows) {
        $out[] = $indent + $row + ";";
    }
    return strings.join($out, "\n");
}

# vars renders one palette as the custom-property block that a mode selector
# swaps in. Both modes define exactly the same property names, so nothing in the
# layout sheet ever has to know which mode is active.
func vars(p as Palette, indent as string) {
    def rows as list of string init [
        "--gr-bg: " + $p.bg,
        "--gr-surface: " + $p.surface,
        "--gr-surface-alt: " + $p.surfaceAlt,
        "--gr-border: " + $p.border,
        "--gr-text: " + $p.text,
        "--gr-muted: " + $p.muted,
        "--gr-heading: " + $p.heading,
        "--gr-accent: " + $p.accent,
        "--gr-accent-hover: " + $p.accentHover,
        "--gr-on-accent: " + $p.onAccent,
        "--gr-code-text: " + $p.codeText,
        "--gr-code-bg: " + $p.codeBg,
        "--gr-selection: " + $p.selection,
        "--gr-shadow: " + $p.shadow
    ];
    def out as list of string;
    for (def row in $rows) {
        $out[] = $indent + $row + ";";
    }
    return strings.join($out, "\n");
}

# The layout sheet: every rule the site needs, reading colour only through the
# custom properties above. It is deliberately one constant rather than a set of
# generated fragments - the cascade order matters, and a single sheet is far
# easier to read than the string concatenation that would produce it.
def const LAYOUT_CSS as string init '
*, *::before, *::after { box-sizing: border-box; }

html {
    color-scheme: light;
    scroll-behavior: smooth;
    -webkit-text-size-adjust: 100%;
}

html[data-theme="dark"] { color-scheme: dark; }

body {
    margin: 0;
    background: var(--gr-bg);
    color: var(--gr-text);
    font-family: var(--gr-font-body);
    font-size: 16px;
    line-height: 1.7;
    font-synthesis-weight: none;
    text-rendering: optimizeLegibility;
    -webkit-font-smoothing: antialiased;
}

::selection { background: var(--gr-selection); }

:focus-visible {
    outline: 2px solid var(--gr-accent);
    outline-offset: 2px;
    border-radius: 3px;
}

a { color: var(--gr-accent); text-decoration-thickness: 1px; text-underline-offset: 2px; }
a:hover { color: var(--gr-accent-hover); }

.gr-skip {
    position: absolute;
    left: -9999px;
    top: 0;
    z-index: 100;
    padding: 10px 16px;
    background: var(--gr-accent);
    color: var(--gr-on-accent);
    border-radius: 0 0 var(--gr-radius) 0;
    text-decoration: none;
}
.gr-skip:focus { left: 0; }

/* ---------- top bar ---------- */

.gr-topbar {
    position: sticky;
    top: 0;
    z-index: 40;
    display: flex;
    align-items: center;
    gap: 10px;
    height: var(--gr-topbar-h);
    padding: 0 16px;
    background: color-mix(in srgb, var(--gr-bg) 88%, transparent);
    backdrop-filter: saturate(180%) blur(12px);
    border-bottom: 1px solid var(--gr-border);
}

/* Everything else in the bar is order 0, so this is "last". A drawer that opens
   from the right edge is reached by a button on the right. */
.gr-topbar[data-nav="right"] #gr-menu { order: 9; }

.gr-brand {
    display: flex;
    align-items: center;
    gap: 10px;
    font-family: var(--gr-font-heading);
    font-weight: 650;
    font-size: 1.02rem;
    letter-spacing: -0.01em;
    color: var(--gr-heading);
    text-decoration: none;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

.gr-mark {
    flex: none;
    width: 26px;
    height: 26px;
    display: grid;
    place-items: center;
    border-radius: 7px;
    background: var(--gr-accent);
    color: var(--gr-on-accent);
    font-family: var(--gr-font-heading);
    font-size: 0.86rem;
    font-weight: 700;
}

/* A configured logo replaces the default glyph: no accent tile behind it, and a
   generous width so a wordmark fits as comfortably as a square icon. */
.gr-mark[data-logo="true"] {
    width: auto;
    max-width: 180px;
    background: none;
    border-radius: 0;
    color: inherit;
}
.gr-mark[data-logo="true"] svg,
.gr-mark[data-logo="true"] img {
    display: block;
    width: auto;
    height: 28px;
    max-width: 180px;
}

.gr-spacer { flex: 1 1 auto; }

.gr-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    height: 34px;
    padding: 0 10px;
    border: 1px solid var(--gr-border);
    border-radius: var(--gr-radius);
    background: var(--gr-surface);
    color: var(--gr-muted);
    font: inherit;
    font-size: 0.85rem;
    cursor: pointer;
    text-decoration: none;
    transition: color 120ms ease, border-color 120ms ease, background 120ms ease;
}
.gr-btn:hover { color: var(--gr-text); border-color: var(--gr-accent); }
.gr-btn svg { width: 16px; height: 16px; flex: none; }

.gr-icon-btn { width: 34px; padding: 0; }

.gr-searchbtn { min-width: 190px; justify-content: flex-start; }
.gr-searchbtn .gr-kbd { margin-left: auto; }

.gr-kbd {
    font-family: var(--gr-font-mono);
    font-size: 0.72rem;
    padding: 1px 6px;
    border: 1px solid var(--gr-border);
    border-bottom-width: 2px;
    border-radius: 5px;
    color: var(--gr-muted);
    background: var(--gr-bg);
}

/* ---------- colour-mode selector ---------- */

.gr-modes {
    display: inline-flex;
    padding: 2px;
    gap: 2px;
    border: 1px solid var(--gr-border);
    border-radius: calc(var(--gr-radius) + 2px);
    background: var(--gr-surface);
}

.gr-modes button {
    display: grid;
    place-items: center;
    width: 30px;
    height: 28px;
    border: 0;
    border-radius: var(--gr-radius);
    background: transparent;
    color: var(--gr-muted);
    cursor: pointer;
    transition: background 120ms ease, color 120ms ease;
}
.gr-modes button:hover { color: var(--gr-text); }
.gr-modes button svg { width: 15px; height: 15px; }
.gr-modes button[aria-checked="true"] {
    background: var(--gr-accent);
    color: var(--gr-on-accent);
}

/* ---------- shell ---------- */

/* A flex row rather than a grid of named columns, because either navigation
   column can be turned off: a grid has to be told how many columns it has and
   how wide each one is, so every combination of the two settings would need its
   own template. Flex takes the columns that are there, and `order` below is what
   puts them on the side the book asked for. */
.gr-shell {
    display: flex;
    align-items: flex-start;
    max-width: var(--gr-shell-w);
    margin: 0 auto;
}

/* The visual order of the row, left to right. The sidebar is outermost when
   both columns share a side: it belongs to the book, the contents list only to
   the page, and the wider scope reads better further out. */
.gr-shell[data-nav="left"] .gr-sidebar { order: 1; }
.gr-shell[data-toc="left"] .gr-toc { order: 2; }
.gr-main { order: 3; }
.gr-shell[data-toc="right"] .gr-toc { order: 4; }
.gr-shell[data-nav="right"] .gr-sidebar { order: 5; }

.gr-sidebar {
    position: fixed;
    inset: var(--gr-topbar-h) auto 0 0;
    z-index: 35;
    flex: none;
    width: var(--gr-sidebar-w);
    max-width: 86vw;
    padding: 18px 8px 40px 16px;
    overflow-y: auto;
    overscroll-behavior: contain;
    background: var(--gr-surface);
    border-right: 1px solid var(--gr-border);
    transform: translateX(-102%);
    transition: transform 180ms ease;
}
.gr-sidebar[data-open="true"] { transform: none; box-shadow: 0 12px 40px var(--gr-shadow); }

/* A right-hand sidebar is the same drawer hinged on the other edge, and the
   border moves with it so it always faces the text. */
.gr-shell[data-nav="right"] .gr-sidebar {
    inset: var(--gr-topbar-h) 0 0 auto;
    padding: 18px 16px 40px 8px;
    border-right: 0;
    border-left: 1px solid var(--gr-border);
    transform: translateX(102%);
}
.gr-shell[data-nav="right"] .gr-sidebar[data-open="true"] { transform: none; }
.gr-shell[data-nav="right"] .gr-nav > ol { padding-right: 0; padding-left: 6px; }

.gr-backdrop {
    position: fixed;
    inset: 0;
    z-index: 34;
    background: rgba(0, 0, 0, 0.4);
    opacity: 0;
    pointer-events: none;
    transition: opacity 180ms ease;
}
.gr-backdrop[data-open="true"] { opacity: 1; pointer-events: auto; }

.gr-nav ol { list-style: none; margin: 0; padding: 0; }
.gr-nav > ol { padding-right: 6px; }

.gr-part {
    margin: 22px 0 8px;
    padding: 0 10px;
    font-family: var(--gr-font-heading);
    font-size: 0.7rem;
    font-weight: 700;
    letter-spacing: 0.09em;
    text-transform: uppercase;
    color: var(--gr-muted);
}
.gr-part:first-child { margin-top: 4px; }

.gr-sep { margin: 12px 10px; border: 0; border-top: 1px solid var(--gr-border); }

.gr-nav a, .gr-nav .gr-draft {
    display: flex;
    gap: 8px;
    padding: 5px 10px;
    border-radius: var(--gr-radius);
    color: var(--gr-text);
    text-decoration: none;
    font-size: 0.895rem;
    line-height: 1.45;
}
.gr-nav a:hover { background: var(--gr-surface-alt); color: var(--gr-text); }
.gr-nav .gr-draft { color: var(--gr-muted); cursor: not-allowed; }

.gr-nav a[aria-current="page"] {
    background: color-mix(in srgb, var(--gr-accent) 14%, transparent);
    color: var(--gr-accent);
    font-weight: 600;
    box-shadow: inset 2px 0 0 var(--gr-accent);
}

.gr-num {
    flex: none;
    min-width: 1.9em;
    color: var(--gr-muted);
    font-variant-numeric: tabular-nums;
    font-size: 0.82rem;
    padding-top: 0.08em;
}
.gr-nav a[aria-current="page"] .gr-num { color: inherit; }

.gr-nav li[data-level="1"] > a, .gr-nav li[data-level="1"] > .gr-draft { padding-left: 26px; }
.gr-nav li[data-level="2"] > a, .gr-nav li[data-level="2"] > .gr-draft { padding-left: 42px; }
.gr-nav li[data-level="3"] > a, .gr-nav li[data-level="3"] > .gr-draft { padding-left: 58px; }

/* ---------- main column ---------- */

/* min-width: 0 lets the text column shrink below the width of its widest
   unbreakable child - a long code line - instead of pushing the row wider. */
.gr-main { flex: 1 1 auto; min-width: 0; padding: 8px 20px 64px; }

.gr-content {
    max-width: var(--gr-content-w);
    margin: 0 auto;
}

.gr-breadcrumb {
    margin: 18px 0 0;
    font-size: 0.8rem;
    color: var(--gr-muted);
}
.gr-breadcrumb a { color: inherit; text-decoration: none; }
.gr-breadcrumb a:hover { color: var(--gr-accent); }

.gr-content h1, .gr-content h2, .gr-content h3,
.gr-content h4, .gr-content h5, .gr-content h6 {
    font-family: var(--gr-font-heading);
    color: var(--gr-heading);
    line-height: 1.25;
    letter-spacing: -0.015em;
    scroll-margin-top: calc(var(--gr-topbar-h) + 16px);
    position: relative;
}

.gr-content h1 { font-size: 2.05rem; margin: 24px 0 18px; font-weight: 700; }
.gr-content h2 {
    font-size: 1.45rem;
    margin: 44px 0 14px;
    padding-bottom: 7px;
    border-bottom: 1px solid var(--gr-border);
    font-weight: 650;
}
.gr-content h3 { font-size: 1.16rem; margin: 32px 0 10px; font-weight: 650; }
.gr-content h4 { font-size: 1rem; margin: 26px 0 8px; font-weight: 650; }
.gr-content h5, .gr-content h6 {
    font-size: 0.9rem;
    margin: 22px 0 6px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--gr-muted);
}

.gr-anchor {
    position: absolute;
    left: -0.85em;
    width: 0.85em;
    opacity: 0;
    color: var(--gr-muted);
    text-decoration: none;
    font-weight: 400;
    transition: opacity 120ms ease;
}
.gr-content h1:hover .gr-anchor, .gr-content h2:hover .gr-anchor,
.gr-content h3:hover .gr-anchor, .gr-content h4:hover .gr-anchor,
.gr-content h5:hover .gr-anchor, .gr-content h6:hover .gr-anchor,
.gr-anchor:focus { opacity: 1; }
.gr-anchor:hover { color: var(--gr-accent); }

.gr-content p { margin: 0 0 16px; }
.gr-content ul, .gr-content ol { margin: 0 0 16px; padding-left: 1.5em; }
.gr-content li { margin: 4px 0; }
.gr-content li > ul, .gr-content li > ol { margin: 4px 0 0; }

.gr-content img { max-width: 100%; height: auto; border-radius: var(--gr-radius); }

.gr-content hr {
    margin: 34px 0;
    border: 0;
    border-top: 1px solid var(--gr-border);
}

.gr-content blockquote {
    margin: 0 0 18px;
    padding: 2px 0 2px 18px;
    border-left: 3px solid var(--gr-accent);
    color: var(--gr-muted);
}
.gr-content blockquote > :last-child { margin-bottom: 0; }

.gr-content code {
    font-family: var(--gr-font-mono);
    font-size: 0.875em;
    background: var(--gr-code-bg);
    color: var(--gr-code-text);
    padding: 0.15em 0.38em;
    border-radius: 5px;
    overflow-wrap: break-word;
}

.gr-codeblock {
    position: relative;
    margin: 0 0 20px;
    border: 1px solid var(--gr-border);
    border-radius: calc(var(--gr-radius) + 2px);
    background: var(--gr-code-bg);
    overflow: hidden;
}

.gr-codeblock pre {
    margin: 0;
    padding: 14px 16px;
    overflow-x: auto;
    font-size: 0.855rem;
    line-height: 1.6;
    tab-size: 4;
}
.gr-codeblock pre code {
    background: none;
    padding: 0;
    border-radius: 0;
    font-size: inherit;
}

/* A highlight.js stylesheet paints its own background and padding on `.hljs`,
   which would sit as a mismatched slab inside the themed block. Let the theme
   own the frame and let highlight.js own only the token colours. */
.gr-codeblock pre code.hljs {
    background: none;
    padding: 0;
}

/* Token colours for the built-in highlighter. These use highlight.js class
   names, so a highlight.js stylesheet loaded from a CDN - which is appended to
   the head at runtime, after this file - simply overrides them. */
.hljs-comment, .hljs-quote { color: var(--gr-syn-comment); font-style: italic; }
.hljs-keyword, .hljs-selector-tag { color: var(--gr-syn-keyword); }
.hljs-type, .hljs-class .hljs-title { color: var(--gr-syn-type); }
.hljs-literal, .hljs-boolean { color: var(--gr-syn-literal); }
.hljs-string, .hljs-subst { color: var(--gr-syn-string); }
.hljs-number { color: var(--gr-syn-number); }
.hljs-variable, .hljs-template-variable { color: var(--gr-syn-variable); }
.hljs-symbol, .hljs-attr { color: var(--gr-syn-symbol); }
.hljs-built_in, .hljs-builtin-name { color: var(--gr-syn-builtin); }
.hljs-title, .hljs-section, .hljs-function .hljs-title { color: var(--gr-syn-title); }
.hljs-meta { color: var(--gr-syn-comment); }
.hljs-emphasis { font-style: italic; }
.hljs-strong { font-weight: 600; }

.gr-lang {
    position: absolute;
    top: 0;
    right: 0;
    padding: 3px 9px;
    border-left: 1px solid var(--gr-border);
    border-bottom: 1px solid var(--gr-border);
    border-radius: 0 calc(var(--gr-radius) + 1px) 0 6px;
    background: var(--gr-surface);
    color: var(--gr-muted);
    font-family: var(--gr-font-mono);
    font-size: 0.68rem;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    pointer-events: none;
}

.gr-copy {
    position: absolute;
    top: 6px;
    right: 8px;
    display: grid;
    place-items: center;
    width: 30px;
    height: 28px;
    border: 1px solid var(--gr-border);
    border-radius: var(--gr-radius);
    background: var(--gr-surface);
    color: var(--gr-muted);
    cursor: pointer;
    opacity: 0;
    transition: opacity 120ms ease, color 120ms ease;
}
.gr-codeblock:hover .gr-copy, .gr-copy:focus { opacity: 1; }
.gr-copy:hover { color: var(--gr-accent); }
.gr-copy svg { width: 15px; height: 15px; }
.gr-copy[data-copied="true"] { color: var(--gr-accent); opacity: 1; }
.gr-codeblock:hover .gr-lang { opacity: 0; }

.gr-tablewrap { overflow-x: auto; margin: 0 0 20px; }

.gr-content table {
    border-collapse: collapse;
    width: 100%;
    font-size: 0.9rem;
}
.gr-content th, .gr-content td {
    padding: 8px 12px;
    border: 1px solid var(--gr-border);
    text-align: left;
    vertical-align: top;
}
.gr-content th {
    background: var(--gr-surface-alt);
    font-family: var(--gr-font-heading);
    font-weight: 650;
    color: var(--gr-heading);
}
.gr-content tbody tr:nth-child(even) { background: var(--gr-surface); }
.gr-content td[data-align="right"], .gr-content th[data-align="right"] { text-align: right; }
.gr-content td[data-align="center"], .gr-content th[data-align="center"] { text-align: center; }

/* ---------- pager and footer ---------- */

.gr-pager {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
    max-width: var(--gr-content-w);
    margin: 46px auto 0;
}

.gr-pager a {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 12px 16px;
    border: 1px solid var(--gr-border);
    border-radius: calc(var(--gr-radius) + 2px);
    background: var(--gr-surface);
    text-decoration: none;
    transition: border-color 120ms ease, transform 120ms ease;
}
.gr-pager a:hover { border-color: var(--gr-accent); transform: translateY(-1px); }
.gr-pager .gr-next { text-align: right; grid-column: 2; }
.gr-pager .gr-dir {
    font-size: 0.72rem;
    text-transform: uppercase;
    letter-spacing: 0.07em;
    color: var(--gr-muted);
}
.gr-pager .gr-title { color: var(--gr-heading); font-weight: 600; }

.gr-footer {
    max-width: var(--gr-content-w);
    margin: 40px auto 0;
    padding-top: 18px;
    border-top: 1px solid var(--gr-border);
    display: flex;
    flex-wrap: wrap;
    gap: 6px 18px;
    align-items: baseline;
    font-size: 0.8rem;
    color: var(--gr-muted);
}
.gr-footer a { color: var(--gr-muted); }
.gr-footer a:hover { color: var(--gr-accent); }

/* ---------- on-this-page ---------- */

.gr-toc { display: none; flex: none; width: var(--gr-toc-w); }

/* The column has to span the whole row, not just its own content: a sticky child
   can only travel inside the box of its parent, so a column that ends where the
   list ends takes the list off-screen with it a few hundred pixels down the
   page. See align-self on .gr-toc below, which overrides the align-items that
   the shell sets for the main column. */
.gr-toc-inner {
    position: sticky;
    top: calc(var(--gr-topbar-h) + 18px);
    max-height: calc(100vh - var(--gr-topbar-h) - 40px);
    overflow-y: auto;
    overscroll-behavior: contain;
    padding: 22px 16px 30px 0;
}

.gr-toc h2 {
    margin: 0 0 10px;
    font-family: var(--gr-font-heading);
    font-size: 0.7rem;
    font-weight: 700;
    letter-spacing: 0.09em;
    text-transform: uppercase;
    color: var(--gr-muted);
}

.gr-toc ol { list-style: none; margin: 0; padding: 0; }
.gr-toc a {
    display: block;
    padding: 3px 10px;
    border-left: 2px solid var(--gr-border);
    color: var(--gr-muted);
    font-size: 0.82rem;
    line-height: 1.5;
    text-decoration: none;
}
.gr-toc a:hover { color: var(--gr-text); }
.gr-toc a[aria-current="true"] {
    color: var(--gr-accent);
    border-left-color: var(--gr-accent);
    font-weight: 550;
}
.gr-toc li[data-level="3"] a { padding-left: 22px; }
.gr-toc li[data-level="4"] a { padding-left: 34px; }
.gr-toc li[data-level="5"] a, .gr-toc li[data-level="6"] a { padding-left: 46px; }

/* The gutter belongs between the list and the text, so it changes sides with the
   column. The rule on the links does not: their left border is the position
   marker rather than a frame, and it stays where the indentation starts. */
.gr-shell[data-toc="left"] .gr-toc-inner { padding: 22px 0 30px 16px; }

/* ---------- search ---------- */

.gr-search[hidden] { display: none; }

.gr-search {
    position: fixed;
    inset: 0;
    z-index: 60;
    display: flex;
    justify-content: center;
    padding: 10vh 16px 16px;
    background: rgba(0, 0, 0, 0.45);
    backdrop-filter: blur(3px);
}

.gr-search-panel {
    display: flex;
    flex-direction: column;
    width: min(680px, 100%);
    max-height: 76vh;
    border: 1px solid var(--gr-border);
    border-radius: calc(var(--gr-radius) + 6px);
    background: var(--gr-bg);
    box-shadow: 0 24px 70px var(--gr-shadow);
    overflow: hidden;
}

.gr-search-head {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 12px 14px;
    border-bottom: 1px solid var(--gr-border);
    color: var(--gr-muted);
}
.gr-search-head svg { width: 18px; height: 18px; flex: none; }

.gr-search-head input {
    flex: 1;
    border: 0;
    background: none;
    color: var(--gr-text);
    font: inherit;
    font-size: 1rem;
    outline: none;
}

.gr-results { list-style: none; margin: 0; padding: 6px; overflow-y: auto; }

.gr-results a {
    display: flex;
    flex-direction: column;
    gap: 1px;
    padding: 9px 12px;
    border-radius: var(--gr-radius);
    text-decoration: none;
    color: var(--gr-text);
}
.gr-results li[data-active="true"] a, .gr-results a:hover { background: var(--gr-surface-alt); }

.gr-r-crumb {
    font-size: 0.7rem;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    color: var(--gr-muted);
}
.gr-r-title {
    font-family: var(--gr-font-heading);
    font-weight: 600;
    color: var(--gr-heading);
    line-height: 1.35;
}
/* Two lines of context is enough to judge a hit; more and the list stops being
   scannable. The clamp degrades to a plain overflow where it is unsupported. */
.gr-r-body {
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    font-size: 0.8rem;
    line-height: 1.5;
    color: var(--gr-muted);
}
.gr-results mark {
    background: color-mix(in srgb, var(--gr-accent) 26%, transparent);
    color: inherit;
    border-radius: 3px;
    padding: 0 1px;
}

.gr-search-foot {
    display: flex;
    gap: 14px;
    padding: 8px 14px;
    border-top: 1px solid var(--gr-border);
    background: var(--gr-surface);
    font-size: 0.74rem;
    color: var(--gr-muted);
}
.gr-empty { padding: 26px 14px; text-align: center; color: var(--gr-muted); font-size: 0.9rem; }

/* ---------- responsive ---------- */

/* Wide enough for the sidebar to stop being a drawer and become a column. The
   right-hand variant needs saying again rather than inheriting: its off-canvas
   rules are the more specific ones, so they would otherwise survive the
   breakpoint and leave the column parked outside the viewport. */
@media (min-width: 1080px) {
    .gr-sidebar {
        position: sticky;
        top: var(--gr-topbar-h);
        height: calc(100vh - var(--gr-topbar-h));
        transform: none;
    }
    .gr-shell[data-nav="right"] .gr-sidebar {
        inset: var(--gr-topbar-h) auto auto auto;
        transform: none;
    }
    .gr-sidebar[data-open="true"] { box-shadow: none; }
    .gr-backdrop { display: none; }
    #gr-menu { display: none; }
    .gr-main { padding-left: 34px; padding-right: 34px; }
    /* Without a sidebar there is 302px of room going spare, so the contents
       column does not have to wait for the wider breakpoint below. */
    .gr-shell[data-nav="off"] .gr-toc { display: block; align-self: stretch; }
}

@media (min-width: 1400px) {
    .gr-toc { display: block; align-self: stretch; }
}

@media (max-width: 640px) {
    .gr-searchbtn { min-width: 0; }
    .gr-searchbtn span, .gr-searchbtn .gr-kbd { display: none; }
    .gr-searchbtn { width: 34px; padding: 0; }
    .gr-pager { grid-template-columns: 1fr; }
    .gr-pager .gr-next { grid-column: 1; }
    .gr-content h1 { font-size: 1.7rem; }
}

@media (prefers-reduced-motion: reduce) {
    html { scroll-behavior: auto; }
    *, *::before, *::after {
        transition-duration: 0.01ms !important;
        animation-duration: 0.01ms !important;
    }
}

@media print {
    .gr-topbar, .gr-sidebar, .gr-toc, .gr-pager,
    .gr-backdrop, .gr-search, .gr-copy, .gr-skip { display: none !important; }
    .gr-shell { display: block; max-width: none; }
    .gr-main { padding: 0; }
    .gr-content { max-width: none; }
    body { background: #fff; color: #000; }
    .gr-codeblock, .gr-content table { break-inside: avoid; }
}
';

/**
 * Render a theme as a complete stylesheet: the shared metrics, the light palette
 * on `:root`, the dark palette under both the `prefers-color-scheme` media query
 * and an explicit `data-theme` attribute (so the in-page selector can override
 * the system preference in either direction), and the layout rules.
 * @param t {Theme} the theme
 * @return {string} the stylesheet source
 */
export func stylesheet(t as Theme) {
    def out as list of string;
    $out[] = "/* grimoire theme: " + $t.label + " (" + $t.name + ") */";
    $out[] = ':root {';
    $out[] = "    --gr-font-body: " + $t.fontBody + ";";
    $out[] = "    --gr-font-heading: " + $t.fontHeading + ";";
    $out[] = "    --gr-font-mono: " + $t.fontMono + ";";
    $out[] = "    --gr-radius: " + convert.toString($t.radius) + "px;";
    $out[] = "    --gr-content-w: " + convert.toString($t.contentWidth) + "px;";
    $out[] = "    --gr-sidebar-w: 302px;";
    $out[] = "    --gr-toc-w: 232px;";
    $out[] = "    --gr-topbar-h: 54px;";
    $out[] = "    --gr-shell-w: 1720px;";
    $out[] = vars($t.light, "    ");
    $out[] = syntaxVars(SYNTAX_LIGHT, "    ");
    $out[] = '}';
    $out[] = "";
    $out[] = '@media (prefers-color-scheme: dark) {';
    $out[] = '    :root:not([data-theme="light"]) {';
    $out[] = vars($t.dark, "        ");
    $out[] = '    }';
    $out[] = '}';
    $out[] = "";
    $out[] = ':root[data-theme="dark"] {';
    $out[] = vars($t.dark, "    ");
    $out[] = syntaxVars(SYNTAX_DARK, "    ");
    $out[] = '}';
    $out[] = "";
    $out[] = ':root[data-theme="light"] {';
    $out[] = vars($t.light, "    ");
    $out[] = syntaxVars(SYNTAX_LIGHT, "    ");
    $out[] = '}';
    $out[] = LAYOUT_CSS;
    return strings.join($out, "\n");
}
