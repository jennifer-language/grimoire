# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The Grimoire build configuration: a `Config` value with a working default for
 * every field, plus the `grimoire.toml` reader that layers a book's own settings
 * on top. Every knob has a default, so a directory of Markdown files builds with
 * no configuration file at all.
 * @module config
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use toml;
use fs;
use strings;
use lists;
use convert;

/**
 * A resolved book configuration. The `book` fields describe the document, the
 * `html` fields the generated site, and the `pdf` fields the printable build.
 * @field title {string} the book title, shown in the sidebar and every page title
 * @field description {string} a one-line description, emitted as a meta tag
 * @field authors {list of string} the book's authors
 * @field authorsLabel {string} what introduces the author names where a reader
 *   sees them - the page footer and the PDF cover ("" for the names alone)
 * @field language {string} the BCP 47 language tag for the `html` element
 * @field uiLanguage {string} the language Grimoire's own strings are rendered in
 *   - "Search", "On this page", the colour-mode buttons. Follows `language`
 *   unless it is set, for the book written in one language whose reader-facing
 *   furniture should be in another
 * @field srcDir {string} the directory holding the Markdown sources
 * @field outDir {string} the directory the site is written to
 * @field theme {string} the built-in theme name
 * @field defaultMode {string} the initial colour mode: "auto", "light", or "dark"
 * @field tocDepth {int} the deepest heading level shown in the per-page contents
 * @field sectionNumbers {bool} whether the sidebar numbers its chapters
 * @field footer {string} HTML placed in the page footer, emitted verbatim ("" for none)
 * @field repoUrl {string} a source-repository URL linked from the top bar ("" for none)
 * @field repoLabel {string} the label for the repository link
 * @field editUrlTemplate {string} an edit-this-page URL with a `{path}` slot ("" for none)
 * @field favicon {string} a favicon path copied into the site ("" for none)
 * @field logo {string} a logo shown beside the title, relative to the source dir ("" for none)
 * @field keywords {bool} derive a `keywords` meta tag for each page from its own
 *   title, headings, and code spans
 * @field keywordStopwords {list of string} further words this book's keyword pass
 *   should ignore, on top of the built-in English stop list
 * @field search {bool} whether to build the search index and ship the search UI
 * @field searchBodyChars {int} how much body text each search record keeps
 * @field pdf {bool} whether `grimoire build` also renders the PDF
 * @field pdfOutput {string} the PDF path, relative to the output directory
 * @field pdfPaper {string} the page size: "a4" or "letter"
 * @field pdfBookmarkLevel {int} bookmark headings up to this level (0 disables)
 * @field pdfPageNumbers {bool} print "page/total" in the footer of every PDF page
 * @field pdfFooterLeft {string} a template for the left of the PDF page footer,
 *   with `{version}` and `{commit}` slots ("" leaves that side empty)
 * @field pdfTitlePage {bool} open the PDF with a title page; off starts it at the
 *   first chapter
 * @field pdfExclude {list of string} chapters to leave out of the PDF, as source
 *   paths relative to `src`; a trailing `/` excludes a whole directory
 * @field jobs {int} chapters to render in parallel (0 = one per CPU)
 * @field highlight {bool} whether code blocks are highlighted at all. On its own
 *   this is the built-in, build-time Jennifer highlighter: no CDN, no JavaScript,
 *   nothing fetched. Off by default
 * @field highlightJs {bool} additionally load highlight.js from a CDN, which is
 *   what highlights the languages the built-in highlighter does not know. Has no
 *   effect unless `highlight` is on
 * @field highlightCdn {string} the highlight.js CDN base URL, with no trailing slash
 * @field highlightStyle {string} the highlight.js stylesheet used in light mode;
 *   read from `[highlightjs]`, since it describes the CDN layer and nothing else
 * @field highlightStyleDark {string} the highlight.js stylesheet used in dark mode
 * @field highlightLanguages {list of string} extra highlight.js language packs to load
 * @field appDir {string} where Grimoire itself lives, for its own bundled assets;
 *   set by the CLI from the program path, never read from `grimoire.toml`
 * @field verbose {bool} report each chapter as it is rendered; set by the CLI,
 *   never read from `grimoire.toml` - it describes one run, not the book
 */
export def struct Config {
    title as string,
    description as string,
    authors as list of string,
    authorsLabel as string,
    language as string,
    uiLanguage as string,
    srcDir as string,
    outDir as string,
    theme as string,
    defaultMode as string,
    tocDepth as int,
    sectionNumbers as bool,
    footer as string,
    repoUrl as string,
    repoLabel as string,
    editUrlTemplate as string,
    favicon as string,
    logo as string,
    keywords as bool,
    keywordStopwords as list of string,
    search as bool,
    searchBodyChars as int,
    pdf as bool,
    pdfOutput as string,
    pdfPaper as string,
    pdfBookmarkLevel as int,
    pdfPageNumbers as bool,
    pdfFooterLeft as string,
    pdfTitlePage as bool,
    pdfExclude as list of string,
    jobs as int,
    highlight as bool,
    highlightJs as bool,
    highlightCdn as string,
    highlightStyle as string,
    highlightStyleDark as string,
    highlightLanguages as list of string,
    appDir as string,
    verbose as bool
};

# The default footer credit. Written as HTML because the footer is emitted
# verbatim: it comes from the book's own configuration, not from untrusted input,
# and a credit line that wants a link should be able to say so directly.
def const DEFAULT_FOOTER as string init 'Rendered with ' +
    '<a href="https://grimoire.jennifer-lang.dev/">Grimoire</a>';

# What introduces the author names on the page and on the PDF cover. A bare name
# standing on its own says nothing about what it is, so something has to; this is
# the least presumptuous phrasing that still reads as a credit. `book.authorsLabel`
# replaces it, and "" drops it and prints the names alone.
def const DEFAULT_AUTHORS_LABEL as string init "Written by";

# The highlight.js release Grimoire pins by default. A pinned version rather than
# a floating "latest": a documentation build should render the same today and in
# a year, and a silent major-version bump on a CDN is exactly the kind of change
# that breaks a language grammar.
def const HLJS_CDN as string init "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1";

/**
 * The default configuration: build `docs/` into `site/` with the `grimoire`
 * theme, a three-level page contents, search on, and the PDF off.
 * @return {Config} the defaults
 */
export func defaults() {
    return Config{
        title: "Documentation",
        description: "",
        authors: [],
        authorsLabel: DEFAULT_AUTHORS_LABEL,
        language: "en",
        uiLanguage: "en",
        srcDir: "docs",
        outDir: "site",
        theme: "grimoire",
        defaultMode: "auto",
        tocDepth: 3,
        sectionNumbers: true,
        footer: DEFAULT_FOOTER,
        repoUrl: "",
        repoLabel: "Source",
        editUrlTemplate: "",
        favicon: "",
        logo: "",
        keywords: true,
        keywordStopwords: [],
        search: true,
        searchBodyChars: 1200,
        pdf: false,
        pdfOutput: "book.pdf",
        pdfPaper: "a4",
        pdfBookmarkLevel: 3,
        pdfPageNumbers: false,
        pdfFooterLeft: "",
        pdfTitlePage: true,
        pdfExclude: [],
        jobs: 0,
        highlight: false,
        highlightJs: false,
        highlightCdn: HLJS_CDN,
        highlightStyle: "github",
        highlightStyleDark: "github-dark",
        highlightLanguages: ["bash", "go", "json", "yaml", "xml", "ini", "nginx"],
        appDir: ".",
        verbose: false
    };
}

# The typed readers below all take the "absent or wrong type keeps the default"
# stance: a config file is user input, and a half-written table should degrade to
# the default rather than abort a build that would otherwise succeed.
func strAt(doc as toml.Value, ptr as string, deflt as string) {
    if (toml.has($doc, $ptr) and toml.typeOf($doc, $ptr) == "string") {
        return toml.asString($doc, $ptr);
    }
    return $deflt;
}

func intAt(doc as toml.Value, ptr as string, deflt as int) {
    if (toml.has($doc, $ptr) and toml.typeOf($doc, $ptr) == "int") {
        return toml.asInt($doc, $ptr);
    }
    return $deflt;
}

func boolAt(doc as toml.Value, ptr as string, deflt as bool) {
    if (toml.has($doc, $ptr) and toml.typeOf($doc, $ptr) == "bool") {
        return toml.asBool($doc, $ptr);
    }
    return $deflt;
}

func stringsAt(doc as toml.Value, ptr as string, deflt as list of string) {
    if (not toml.has($doc, $ptr) or toml.typeOf($doc, $ptr) != "list") {
        return $deflt;
    }
    def out as list of string;
    for (def i in 0..toml.length($doc, $ptr)) {
        def item as string init $ptr + "/" + convert.toString($i);
        if (toml.typeOf($doc, $item) == "string") {
            $out[] = toml.asString($doc, $item);
        }
    }
    return $out;
}

# oneOf keeps an enumerated setting inside its allowed set, so a typo in the
# config falls back to the default instead of emitting a broken page.
func oneOf(value as string, allowed as list of string, deflt as string) {
    if (lists.contains($allowed, $value)) {
        return $value;
    }
    return $deflt;
}

/**
 * Layer a `grimoire.toml` document onto a base configuration. Unknown keys are
 * ignored and a key of the wrong type keeps the base value, so a partial or
 * slightly wrong config still builds.
 * @param base {Config} the configuration to layer onto
 * @param text {string} the TOML source
 * @return {Config} the merged configuration
 * @throws {Error} kind "toml" when the document does not parse
 */
export func apply(base as Config, text as string) {
    def doc as toml.Value init toml.decode($text);
    def c as Config init $base;
    $c.title = strAt($doc, "/book/title", $c.title);
    $c.description = strAt($doc, "/book/description", $c.description);
    $c.authors = stringsAt($doc, "/book/authors", $c.authors);
    $c.authorsLabel = strAt($doc, "/book/authorsLabel", $c.authorsLabel);
    $c.language = strAt($doc, "/book/language", $c.language);
    # Read after `language` because that is its default: a German book gets a
    # German interface without being told twice.
    $c.uiLanguage = strAt($doc, "/html/uiLanguage", $c.language);
    $c.srcDir = strAt($doc, "/book/src", $c.srcDir);
    $c.outDir = strAt($doc, "/build/out", $c.outDir);
    $c.theme = strAt($doc, "/html/theme", $c.theme);
    $c.defaultMode = oneOf(
        strAt($doc, "/html/mode", $c.defaultMode),
        ["auto", "light", "dark"],
        $c.defaultMode);
    $c.tocDepth = intAt($doc, "/html/tocDepth", $c.tocDepth);
    $c.sectionNumbers = boolAt($doc, "/html/sectionNumbers", $c.sectionNumbers);
    $c.footer = strAt($doc, "/html/footer", $c.footer);
    $c.repoUrl = strAt($doc, "/html/repoUrl", $c.repoUrl);
    $c.repoLabel = strAt($doc, "/html/repoLabel", $c.repoLabel);
    $c.editUrlTemplate = strAt($doc, "/html/editUrl", $c.editUrlTemplate);
    $c.favicon = strAt($doc, "/html/favicon", $c.favicon);
    $c.logo = strAt($doc, "/html/logo", $c.logo);
    $c.keywords = boolAt($doc, "/html/keywords", $c.keywords);
    $c.keywordStopwords = stringsAt($doc, "/html/keywordStopwords", $c.keywordStopwords);
    $c.search = boolAt($doc, "/search/enabled", $c.search);
    $c.searchBodyChars = intAt($doc, "/search/bodyChars", $c.searchBodyChars);
    $c.pdf = boolAt($doc, "/pdf/enabled", $c.pdf);
    $c.pdfOutput = strAt($doc, "/pdf/output", $c.pdfOutput);
    $c.pdfPaper = oneOf(strAt($doc, "/pdf/paper", $c.pdfPaper), ["a4", "letter"], $c.pdfPaper);
    $c.pdfBookmarkLevel = intAt($doc, "/pdf/bookmarkLevel", $c.pdfBookmarkLevel);
    $c.pdfPageNumbers = boolAt($doc, "/pdf/pageNumbers", $c.pdfPageNumbers);
    $c.pdfFooterLeft = strAt($doc, "/pdf/footerLeft", $c.pdfFooterLeft);
    $c.pdfTitlePage = boolAt($doc, "/pdf/titlePage", $c.pdfTitlePage);
    $c.pdfExclude = stringsAt($doc, "/pdf/exclude", $c.pdfExclude);
    $c.jobs = intAt($doc, "/build/jobs", $c.jobs);
    $c.highlight = boolAt($doc, "/highlight/enabled", $c.highlight);
    $c.highlightJs = boolAt($doc, "/highlightjs/enabled", $c.highlightJs);
    $c.highlightCdn = strAt($doc, "/highlightjs/cdn", $c.highlightCdn);
    $c.highlightStyle = strAt($doc, "/highlightjs/style", $c.highlightStyle);
    $c.highlightStyleDark = strAt($doc, "/highlightjs/styleDark", $c.highlightStyleDark);
    $c.highlightLanguages = stringsAt($doc, "/highlightjs/languages", $c.highlightLanguages);
    if ($c.tocDepth < 1) {
        $c.tocDepth = 1;
    }
    if ($c.tocDepth > 6) {
        $c.tocDepth = 6;
    }
    if ($c.searchBodyChars < 120) {
        $c.searchBodyChars = 120;
    }
    return $c;
}

/**
 * Read a configuration file, falling back to the defaults when it is absent.
 * @param path {string} the path to a `grimoire.toml`
 * @return {Config} the resolved configuration
 * @throws {Error} kind "toml" when the file exists but does not parse
 */
export func load(path as string) {
    if (not fs.isFile($path)) {
        return defaults();
    }
    return apply(defaults(), fs.readString($path));
}

/**
 * Whether the build should pull highlight.js from a CDN.
 *
 * `highlight` is the master switch: with it off there is no highlighting at all,
 * and turning `highlightjs` on by itself does nothing - a book that says "no
 * highlighting" should not start making third-party requests because a second
 * table was left enabled. The build reports that combination rather than
 * silently picking one of the two readings.
 * @param c {Config} the configuration
 * @return {bool} true when highlight.js should be loaded
 */
export func usesHighlightJs(c as Config) {
    return $c.highlight and $c.highlightJs and $c.highlightCdn != "";
}

/**
 * Whether the configuration asks for highlight.js while highlighting is off -
 * a contradiction worth telling the user about.
 * @param c {Config} the configuration
 * @return {bool} true when the two settings disagree
 */
export func highlightJsIgnored(c as Config) {
    return $c.highlightJs and not $c.highlight;
}

/**
 * The authors as a bare, comma-separated list ("" when there are none). This is
 * the machine-readable form: the HTML `author` meta tag and the PDF Info
 * dictionary both want the names alone, with no label in front of them.
 * @param c {Config} the configuration
 * @return {string} the joined author list
 */
export func authorLine(c as Config) {
    return strings.join($c.authors, ", ");
}

/**
 * The authors as a labelled credit line ("" when there are none) - the form a
 * reader sees, in the page footer and on the PDF cover. A bare name standing on
 * its own says nothing about what it is; the label is what makes it a credit,
 * and `book.authorsLabel` is what a book calls it. An empty label prints the
 * names alone, for a book that would rather say it in its own words.
 * @param c {Config} the configuration
 * @return {string} the labelled author line
 */
export func authorCredit(c as Config) {
    def names as string init authorLine($c);
    if ($names == "") {
        return "";
    }
    if (strings.trim($c.authorsLabel) == "") {
        return $names;
    }
    return strings.trim($c.authorsLabel) + " " + $names;
}
