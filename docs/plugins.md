# Plugins

A plugin is a program Grimoire runs while it builds. It reads the book on
standard input as JSON, writes the rewritten chapters back on standard output,
and can be written in any language.

It is a program rather than a module because Jennifer resolves `import` at parse
time: an installed Grimoire cannot load code it was not built with. Running a
program is the extension point that leaves, and it costs one process and one
JSON round trip per plugin per build.

There are two kinds:

| | |
| - | - |
| **preprocessor** | rewrites the Markdown before anything renders, so what it changes reaches the site, the search index and the printable book alike |
| **renderer** | runs once the site is written, and makes something else out of the same book: a second edition, a sitemap, a check |

## Using one

Name it in `grimoire.toml`. An empty table is enough:

```toml
[preprocessor.include]
```

That runs `grimoire-include`: a plugin is an executable named `grimoire-NAME`,
looked for beside Grimoire - in the `plugins/` directory of wherever it is
installed - and then on `PATH`. The prefix is what makes one findable and its
name readable in a configuration file.

Set `command` for anything else, and `args` for arguments that come before the
request:

```toml
[preprocessor.mermaid]
command = "./tools/mermaid-to-svg"
args = ["--scale", "2"]
theme = "dark"
```

A `command` with a `/` in it is a path, used as written - which is how a book
points at a plugin it keeps in its own repository, needing nothing installed.
Every other key in the table is the plugin's own; Grimoire passes them through
without reading them.

A renderer is configured the same way, under `[renderer.NAME]`:

```toml
[renderer.sitemap]
baseUrl = "https://example.com/manual/"
```

Preprocessors run in the order the file lists them, each over what the last
produced, once for the whole book, before any chapter is rendered. Renderers run
after everything else, site and PDF both on disk. A plugin that exits non-zero
stops the build, and its standard error is reported:

```
grimoire: preprocessor include: exited 1: grimoire-include: nope.j: no such file
```

Nothing is discovered automatically. A program has to be named in the file
before Grimoire will run it - and once it is, it runs with your permissions and
can do anything you can. Grimoire itself reaches the network for nothing; a
plugin is your decision.

Which is why the build says what it runs rather than only that it ran:

```sh
grimoire plugins            # what this book would run, and where each came from
grimoire build --verbose    # the same path, printed as each one starts
```

A plugin whose program came from `PATH`, or from somewhere else on the machine,
is reported as a build warning - not refused, because the book naming it is the
gate, but said out loud, because that is the one part of a build that reading
the book's own repository does not show you. A program that ships with Grimoire
or sits inside the book passes without comment.

Preprocessors need the default `jennifer` binary. `jennifer-tiny` has no way to
start a process and says so rather than building a book with the plugin silently
skipped.

## What ships

Twelve, installed with Grimoire in its own `plugins/` directory rather than onto
`PATH`. They are found by name anyway, and `grimoire` stays the only command
installed - `grimoire<TAB>` completes to a word rather than stopping at a prefix
shared with every plugin. **None of them is enabled by default**; a plugin runs
because `grimoire.toml` names it, and `grimoire plugins` says which ones this
book would run.

| | | |
| - | - | - |
| `grimoire-include` | preprocessor | pulls a file, or a range of its lines, into a chapter |
| `grimoire-apiref` | preprocessor | writes reference chapters from Jennifer docblocks |
| `grimoire-glossary` | preprocessor | links the first use of each glossary term to its definition |
| `grimoire-lastmod` | preprocessor | adds a `Last updated` line to each chapter, from git |
| `grimoire-macros` | preprocessor | replaces `{{ version }}` with what the book says it is |
| `grimoire-figure` | preprocessor | writes the caption a picture already carries under it |
| `grimoire-emoji` | preprocessor | turns `:rocket:` into the character it stands for |
| `grimoire-sitemap` | renderer | writes `sitemap.xml` from the outline, and a `robots.txt` pointing at it |
| `grimoire-epub` | renderer | builds an EPUB from the same book |
| `grimoire-feed` | renderer | writes an RSS feed of what changed, from git |
| `grimoire-linkcheck` | renderer | fails the build on a dead cross-reference |
| `grimoire-redirects` | renderer | writes meta-refresh stubs for pages that moved |

Ten of the twelve need nothing installed. `grimoire-feed` and `grimoire-lastmod`
ask git for dates and write nothing without a checkout; `grimoire-linkcheck`
reaches the network only when `external` is on.

Each one has a book of its own under `examples/` in the Grimoire repository,
small enough to read in one screen, which the pipeline builds on every push.

**Two more are maintained separately**, because each drives a program that would
otherwise have to be installed alongside Grimoire:

| | | |
| - | - | - |
| [`grimoire-mermaid`](https://github.com/jennifer-language/grimoire-mermaid) | preprocessor | draws `mermaid` fences while the book is built (needs `mmdc`) |
| [`grimoire-katex`](https://github.com/jennifer-language/grimoire-katex) | preprocessor | typesets `$$ ... $$` display maths to MathML (needs `katex`) |

Both are Jennifer apps, so [jvc](https://github.com/jennifer-language/jvc)
installs them and puts the command where Grimoire looks:

```sh
jvc app install https://github.com/jennifer-language/grimoire-mermaid
```

`--scope project` installs one beside a single book instead, at
`bin/grimoire-mermaid`, which is then what `command` points at. Without jvc, a
checkout and a path in `grimoire.toml` work the same way.

### `grimoire-include`

It pulls a file into a chapter:

```markdown
{{#include examples/hello.j}}          the whole file
{{#include examples/hello.j:3:12}}     lines 3 to 12
{{#include examples/hello.j:5}}        line 5 onwards
```

A snippet pasted into a chapter is wrong the day the code changes and nobody
notices; a file read at build time is either right or a failed build. Put the
directive inside a fence to include code as code:

````markdown
```jennifer
{{#include examples/hello.j:1:12}}
```
````

The directive has to be alone on its line. Paths are relative to `book.src`, and
one that climbs out of the book with `..` is refused. A backslash in front of a
directive at the start of a line prints it instead of following it, which is how
this page shows the syntax. Includes are resolved once: an included file's own
directives are left alone.

### `grimoire-apiref`

It writes reference chapters from Jennifer docblocks. Where a chapter says

```markdown
{{#apiref src}}
```

the directive is replaced by the documentation of every `.j` file under that
path: the module summary, then each exported struct, function and constant, with
the types and descriptions its docblocks carry. A directory is walked in sorted
order so two builds agree, and test overlays are skipped - they document the
tests, not the module.

```toml
[preprocessor.apiref]
depth = 2        # heading level for the module; members go one deeper
private = true   # also document what the module does not export
```

The chapter is still a chapter: it keeps its title, its prose around the
directive, and its place in `SUMMARY.md`. Paths are relative to where the build
runs rather than to the book, because source usually sits beside a book instead
of inside it. Nothing undocumented is ever listed.

### `grimoire-glossary`

It links the first use of each glossary term on a page to its definition. The
terms are the headings of the glossary chapter, so the list maintains itself: a
definition added there starts being linked on the next build, and one renamed
stops.

```toml
[preprocessor.glossary]
chapter = "glossary.md"    # where the definitions are
depth = 2                  # the heading level they sit at
terms = "docs/terms.toml"  # optional: aliases, for the words that are not headings
```

Only the **first** use on a page is linked: a term linked at every mention is a
page of blue text, and the second link is never the one a reader follows. The
glossary chapter itself, headings, fenced code, inline code and anything already
inside a link are left alone, and a term only matches as a whole word - `index`
is not found inside `indexed`. Terms are tried longest first, so `search index`
is linked before `index` can take its first word.

The aliases file maps a spelling to the term it means, and one that names a term
the glossary does not define is an error rather than a link into nothing:

```toml
[terms]
outlines = "outline"
"search indexes" = "search index"
```

### `grimoire-lastmod`

It adds a line to the foot of each chapter, dated by the last commit that
touched it:

```markdown
*Last updated: 2026-03-01*
```

```toml
[preprocessor.lastmod]
format = "%Y-%m-%d"     # a strftime layout, handed to git as written
label = "Last updated"  # the words in front of the date
```

The date comes from git rather than from the filesystem, because a fresh
checkout stamps every file with the moment it was cloned - a build from one
would claim the whole book changed today. A chapter with no commit behind it
gets no line, and a book built from a tarball gets no dates and no error.

**A month name follows the machine's locale.** `%B` gives `March` on one runner
and its translation on another, so a book that has to build identically
everywhere wants a numeric format.

Needs `git`, and a checkout rather than an export.

### `grimoire-macros`

It replaces `{{ version }}` with what the book says it is. A version number
written by hand is wrong the day after it is written, and nobody notices until a
reader copies it.

```toml
[preprocessor.macros]
strict = true              # an unknown name stops the build
env = ["CI_COMMIT_TAG"]    # the environment variables this book may read

[preprocessor.macros.vars]
version = "1.4.0"
minimum = "0.25.0"
```

Three sources, looked up in that order: the book itself (`{{ book.title }}`,
`{{ book.description }}`, `{{ book.language }}`, `{{ book.authors }}`), the
`vars` table, and `{{ env.NAME }}` for the variables `env` names. The
environment is an allow-list on purpose - a build that can print any variable it
likes is one careless page away from publishing a token - and a named variable
that is not set stops the build rather than expanding to nothing.

A name with nothing behind it stops the build too, naming the chapter that asked
for it, because a placeholder that reaches a reader is worse than a build that
stopped. `strict = false` leaves it as written, for a book that writes braces
for some other reason.

Fenced code is left alone, so a page showing what a macro looks like still shows
it. Elsewhere a backslash does the same for one occurrence: `\{{ version }}`
prints itself.

### `grimoire-figure`

It writes the caption a picture already carries. An image standing alone in a
paragraph gets its title - or its alt text, if there is no title - written
underneath; an image inside a sentence is part of the sentence and is left
alone.

```toml
[preprocessor.figure]
caption = "auto"   # or "title", or "alt"
html = false       # true writes a <figure> instead
```

`auto` prefers the title and falls back to the alt text, which is what a book
that writes both means by writing both:

```markdown
![A build, end to end](pipeline.png "How a book is built")
```

The caption is **Markdown** by default - an emphasised line under the picture -
because that is the form that reaches every edition: the site, the EPUB and the
printable book. `html = true` writes a `<figure>` with a `<figcaption>`, which
is better markup and **disappears from the PDF**: the printable build draws
pictures and text and skips a block of HTML it cannot read. A book with no
printable edition should turn it on; one with a PDF should not.

### `grimoire-emoji`

It turns `:rocket:` into the character it stands for, so a book can be written
in plain ASCII and still read the way its author meant.

```toml
[preprocessor.emoji]

[preprocessor.emoji.extra]
grimoire = "*"     # a book's own, which also redefines one of ours
```

The table is the shortcodes documentation actually uses - a status, a warning, a
direction, a piece of the toolchain - and a book adds its own with `extra`,
which wins over the built-in of the same name.

A colon is punctuation long before it is markup, so `10:30`, `3:2`,
`std::vector`, `https://example.com` and `Note: a thing` all keep their colons:
a name is replaced only when it is a whole shortcode with a boundary on each
side, and one the table does not know is left as written. Fenced code is left
alone.

**Check the printable book after turning this on.** It draws what its fonts
carry, and an emoji reaches the page as whatever `TRANSLITERATIONS` in
`src/pdfbook.j` says, or as a question mark if it says nothing - which is
exactly what `jennifer run scripts/check-print.j` reports.

### `grimoire-sitemap`

The reference renderer. It writes `sitemap.xml` from the
outline, and a `robots.txt` pointing at it unless the output directory already
has one - a hand-written robots file is the author's, not a plugin's to replace.

The document is built as a tree and encoded by the `xml` library rather than
assembled as text: a published path can hold an ampersand, and one unescaped is
a document no crawler will read.

A book does not know where it is published, so `baseUrl` is required. Without it
the renderer writes nothing and says so, which surfaces as a build warning:

```
grimoire: sitemap: no baseUrl configured, nothing written
```

### `grimoire-epub`

It builds an EPUB from the same outline: a third edition beside the site and the
printable book, reflowable, for a reader that is not a browser.

```toml
[renderer.epub]
output = "book.epub"
cover = "assets/cover.png"      # optional
stylesheet = "assets/epub.css"  # optional; a default is built in
```

It takes the Markdown from the request rather than the built HTML, so what it
renders is what the book says. Links between chapters are rewritten to the files
inside the archive, fragments included, and pictures are carried in. Nothing has
to be installed: an EPUB is a zip of XHTML and two small XML files, and the
interpreter ships everything that takes - `markdown.toXhtml` writes the chapters
as the well-formed XML a content document has to be, and the `xml` library builds
the package and the navigation.

A chapter's own raw HTML is escaped rather than passed through, which is the one
place the EPUB differs from the site. A hand-written `<div>` need only be valid
HTML5 to reach a page; an EPUB reader refuses a content document that is not
valid XML, so every chapter is parsed back before it goes into the archive and a
book that would produce one is a failed build rather than a file nothing opens.

The archive is written by hand rather than with `archive.pack`, because the
container format requires the `mimetype` entry to come first and be **stored**
rather than deflated, and there is no per-entry compression setting. The
identifier is derived from the title and the language, so a rebuild produces the
same bytes.

### `grimoire-feed`

It writes an RSS feed of what changed: one item per chapter, dated by the last
commit that touched it and titled by that commit's subject, newest first.

```toml
[renderer.feed]
baseUrl = "https://example.com/manual/"   # required
output = "feed.xml"
limit = 20
```

A book does not know where it is published, so `baseUrl` is required: without it
the feed would carry relative links, which a reader has nothing to resolve
against, and the renderer writes nothing and says so as a build warning.

The dates come from git for the same reason `grimoire-lastmod` uses it. A
chapter with no commit behind it is left out; it joins the feed the first time it
is committed.

A chapter title and a commit subject are somebody's prose, so the feed is built
as a tree and encoded rather than assembled as text - one ampersand against a
hand-written `<title>` is a feed no reader will parse.

Needs `git`, and a checkout rather than an export.

### `grimoire-linkcheck`

It fails the build on a dead cross-reference. A build reports a chapter whose
file is missing, but nothing reports a link inside one that goes nowhere: the
page is written, it looks right, and the link is dead until a reader finds it.

```toml
[renderer.linkcheck]
external = false   # true also checks http(s) links
```

It walks the built site, resolves every relative `href` and `src`, checks the
fragments too, and exits non-zero with the whole list rather than the first
finding:

```
site/index.html: missing.html -> no such file
site/index.html: two.html#nowhere -> no such anchor
grimoire-linkcheck: 2 dead link(s)
```

**Code spans are cut out before anything is read.** A page that documents an
`href` puts the literal string in its own output, and a checker cannot tell that
from a link a reader can click. Without this the check fires on every page about
HTML, which is how a check ends up switched off.

`external` is the one thing in a Grimoire build that reaches the network. URLs
are checked once each, deduplicated across the site, HEAD first and GET second,
because a server refusing HEAD is common enough to be worth the second round
trip.

### `grimoire-redirects`

It writes meta-refresh stubs for pages that moved. A URL that was published once
is a promise, and a static host has no server to answer with a 301.

```toml
[renderer.redirects]
"old-start.html" = "index.html"
"guide/old-syntax.html" = "syntax.html"
```

Every key is an old path and every value a new one, both relative to the site
root. The target is written relative to the stub, so a book published under a
subdirectory keeps working; a value that is a full URL is used as written.

Three things are refused, each as a build warning rather than silently: a path
outside the site, a chapter of the book (the outline says which those are, and a
stub there would replace a page with a redirect away from itself), and any other
file already in place. Its own stubs carry a `generator` tag and are rewritten
without comment, which is what keeps a build that is not `--clean` quiet.

## Writing one

The request arrives on stdin as a single JSON object:

```json
{"api": 1,
 "book": {"title": "...", "description": "...", "authors": ["Ada"],
          "language": "en", "src": "docs", "out": "site"},
 "plugin": {"name": "include", "settings": {"theme": "dark"}},
 "entries": [{"kind": "page", "title": "Introduction", "src": "index.md",
              "out": "index.html", "level": 0, "number": "1"}],
 "chapters": [{"src": "index.md", "content": "# Introduction\n..."}]}
```

`kind` is `"preprocessor"` or `"renderer"`, so one program can implement both
and tell which it is being asked for. A renderer gets the same request once the
site exists, with `book.out` holding the directory it was built into.

A preprocessor replies with the chapters it changed:

```json
{"api": 1, "chapters": [{"src": "index.md", "content": "# Introduction\n..."}]}
```

A renderer writes its own files and reports rather than rewrites:

```json
{"api": 1, "written": ["book.epub"], "warnings": ["no cover image"]}
```

Both lists are optional. `written` is printed with the build's other lines under
`--verbose`; `warnings` joins the build's own, each prefixed with the renderer's
name.

| | |
| - | - |
| `api` | the contract version, `1`. Refuse a request whose version you do not know, and Grimoire refuses a reply that does not claim its own |
| `entries` | the whole outline, parts and separators included, so a plugin can see where a chapter sits |
| `chapters` | every chapter the build resolved, in outline order |
| a preprocessor's reply | may be sparse: a chapter it does not mention is unchanged. Naming one the book does not have is an error |
| a renderer's reply | `written` and `warnings`, both optional; the files themselves are the renderer's to write |
| exit code | `0`, or the build stops |

Two rules the contract cannot enforce. A plugin has to be **deterministic** -
the same request gives the same reply - because byte-identical output at any
`--jobs` is a promise Grimoire makes and a plugin is now part of it. And it
should write nothing but the reply to stdout; diagnostics belong on stderr,
where a failing build will show them.

Adding or reordering chapters is not part of this version. Only the `chapters`
in a preprocessor's reply are read back, so a plugin changes what a chapter says,
never which chapters exist.

## Versions

The request carries `"api": 1`. Read it and refuse a number you do not know
rather than guessing at a shape; Grimoire refuses a reply that does not claim the
same number. It changes when the request or the reply changes shape, not when
Grimoire does, so a plugin that works with api 1 keeps working until that number
moves.

## Publishing one

Anything that reads stdin and writes stdout will do, in any language, and a
checkout plus a path in `grimoire.toml` is a complete way to ship one.

A Jennifer plugin is a launcher and the module beside it. Write it that way from
the start: `jennifer test` splices a `NAME_test.j` into the `NAME.j` it names, so
a plugin written as one script cannot be tested at all. The launcher reads stdin
and exits the status of `run(request)`; the module never calls `exit`, because an
`exit` inside a module takes the test runner with it.

```
bin/grimoire-NAME     the launcher: read stdin, import the module, exit its status
src/NAME.j            the module, where the work is
src/NAME_test.j       the white-box overlay
deck.toml             the manifest, if you publish it with jvc
```

That layout is also a Jennifer **app**, which is how
[jvc](https://github.com/jennifer-language/jvc) installs a program: an unscoped
`name` in `deck.toml` and `bin` pointing at the launcher.

```sh
jvc app install https://github.com/you/grimoire-NAME             # onto PATH
jvc app install https://github.com/you/grimoire-NAME --scope project  # beside one book
```

The command an install leaves behind is the package name, and that is the name
Grimoire looks for when a book writes `[preprocessor.NAME]` with no `command`.
Renaming the package renames the command and breaks that. An app is installed
from its repository rather than from the registry, which indexes decks - trees of
modules that are vendored and imported, never run.

Ship it with a README showing the `grimoire.toml` table that enables it and any
keys of its own, the api version it speaks, a licence, and a note if it needs
anything at build time that a build otherwise does not: network access, a binary
like `dot` or `pandoc`, a font. That last one matters more than it sounds.
Grimoire fetches nothing while it builds, and a book that adds a plugin changes
that promise for itself. A `NEEDS` file beside the launcher, one command per
line, says the same thing to the container image, which checks it and warns.
