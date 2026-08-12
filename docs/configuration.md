# Configuration

`grimoire.toml` sits next to the book, and every key in it is optional -
a directory of Markdown files builds with no configuration file at all. Point
`--config` elsewhere to use a different one.

Two rules hold throughout:

- **A command-line flag wins over the file**, so a one-off build needs no edit.
- **A key of the wrong type keeps its default** rather than failing the build,
  and an unknown key is ignored. A half-written table degrades to the defaults
  instead of aborting a build that would otherwise have succeeded.

## The whole file

Every key, with its default:

```toml
[book]
title = "Documentation"
description = ""
authors = []
authorsLabel = "Written by"
language = "en"
src = "docs"

[build]
out = "site"
jobs = 0                # 0 = one render task per CPU

[html]
theme = "grimoire"
mode = "auto"           # auto | light | dark
uiLanguage = "en"       # defaults to book.language
tocDepth = 3
sectionNumbers = true
footer = "Rendered with <a href=\"...\">Grimoire</a>"
repoUrl = ""
repoLabel = "Source"
editUrl = ""
favicon = ""
logo = ""
keywords = true
keywordStopwords = []

[highlight]
enabled = false

[highlightjs]
enabled = false
cdn = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1"
style = "github"
styleDark = "github-dark"
languages = ["bash", "go", "json", "yaml", "xml", "ini", "nginx"]

[search]
enabled = true
bodyChars = 1200

[pdf]
enabled = false
output = "book.pdf"
paper = "a4"            # a4 | letter
bookmarkLevel = 3
pageNumbers = false
footerLeft = ""
titlePage = true
exclude = []
```

## `[book]`

| Key | Type | Default | Meaning |
| --- | ---- | ------- | ------- |
| `title` | string | `"Documentation"` | shown in the sidebar and in every page title; also the PDF cover and `Title` |
| `description` | string | `""` | emitted as a `description` meta tag, and as the PDF `Subject` |
| `authors` | list of string | `[]` | the `author` meta tag, the PDF `Author` field, and the reader-facing credit |
| `authorsLabel` | string | `"Written by"` | what introduces those names where a reader sees them; `""` prints them alone |
| `language` | string | `"en"` | the BCP 47 tag on the `html` element, and the language Grimoire's own words are printed in |
| `src` | string | `"docs"` | the directory of Markdown to build, relative to the working directory |

`src` is where the outline comes from. If it holds a `SUMMARY.md`, that file is
the outline; if not, the directory tree is walked instead.

`authors` is used two ways, and only one of them is labelled. The `author` meta
tag and the PDF `Author` field want the names alone, because those are read by
software. The page footer and the PDF cover want a credit, because a name
standing on its own says nothing about what it is - so `authorsLabel` goes in
front of it:

```toml
authors = ["Ada Lovelace", "Grace Hopper"]
authorsLabel = "Built with love by"   # -> Built with love by Ada Lovelace, Grace Hopper
authorsLabel = ""                     # -> Ada Lovelace, Grace Hopper
```

## `[build]`

| Key | Type | Default | Meaning |
| --- | ---- | ------- | ------- |
| `out` | string | `"site"` | where the site is written |
| `jobs` | int | `0` | chapters rendered in parallel; `0` means one task per CPU |

The output directory is created if it is missing. Files already there are left
alone unless the build writes over them, so an unrelated file in `site/`
survives - but so does a chapter you deleted from the book, which is worth
knowing before publishing.

`jobs` above the chapter count simply idles the extra workers. See
[Performance](performance.md) for what raising it actually buys.

## `[html]`

| Key | Type | Default | Meaning |
| --- | ---- | ------- | ------- |
| `theme` | string | `"grimoire"` | one of the [ten themes](themes.md); an unknown name falls back to `grimoire` |
| `mode` | string | `"auto"` | the colour mode a first-time reader gets: `auto`, `light`, `dark` |
| `uiLanguage` | string | from `book.language` | the language Grimoire's own words are printed in, when it differs from the book's |
| `tocDepth` | int | `3` | deepest heading level in the per-page contents; clamped to 1-6 |
| `sectionNumbers` | bool | `true` | number the chapters in the sidebar |
| `footer` | string | the Grimoire credit | HTML placed in the page footer; `""` for no footer |
| `repoUrl` | string | `""` | a source-repository link in the top bar; `""` for none |
| `repoLabel` | string | `"Source"` | the label on that link |
| `editUrl` | string | `""` | an edit-this-page URL with a `{path}` slot; `""` for none |
| `favicon` | string | `""` | a favicon path, copied into the site |
| `logo` | string | `""` | a logo shown beside the title, relative to `src` |
| `keywords` | bool | `true` | derive a `keywords` meta tag for each page from the page itself |
| `keywordStopwords` | list of string | `[]` | further words the keyword pass should ignore |

`mode` only decides the **first** visit. Once a reader touches the selector,
their choice is remembered and this setting no longer applies to them. Whatever
it resolves to is stamped on the document before the first paint, so navigating
a dark site never flashes white.

### The interface language

Grimoire puts about twenty words of its own on a page - "Search", "On this page",
"Previous", the colour-mode buttons, the keyboard hints in the search dialog, the
label on the copy-code button - and they follow `book.language`:

| | | | |
| - | - | - | - |
| `de` German | `es` Spanish | `fr` French | `it` Italian |
| `ja` Japanese | `nl` Dutch | `pl` Polish | `pt` Portuguese |
| `ru` Russian | `zh` Chinese | `en` English | |

A region is read as its base language, so `pt-BR` gets Portuguese and `de-AT`
German. A book in a language not on that list still builds - the interface stays
English, and the build says so once on stderr rather than filling the page with
untranslated key names.

`uiLanguage` is for when the two should differ: a book written in German whose
readers expect English furniture, or the reverse.

```toml
[book]
language = "de"     # what the chapters are written in, and the html lang attribute

[html]
uiLanguage = "en"   # but Search and On this page stay English
```

None of this touches the book's own text, and none of it reaches the PDF - the
printed book carries the author's words and the two strings configured around
them, `authorsLabel` and `[pdf] footerLeft`.

`editUrl` substitutes the chapter's source path for `{path}`:

```toml
editUrl = "https://github.com/me/book/edit/main/docs/{path}"
```

`logo` pointing at an SVG gets **inlined** into the page, so it inherits the
colour mode through `currentColor` and costs no extra request; any other format
is linked as an `img`. The path is resolved against `src`, and `../` out of it
is fine:

```toml
logo = "../assets/wordmark.svg"
```

`keywords` gives each page a `<meta name="keywords">` worked out from its own
content. The scoring is structural rather than statistical - a term is worth the
sum of its weighted appearances:

| where it appears | weight |
| ---------------- | -----: |
| the page title | 8 |
| a level-2 heading | 4 |
| a deeper heading | 3 |
| a code span | 3 |
| body text | 1 |

So a word in the title outranks eight mentions in prose, and an identifier the
page discusses outranks three - which is the right answer for a reference page
whose subject is named twice and used everywhere. The top ten win.

There is no TF-IDF here, and that is deliberate twice over. Corpus-wide document
frequencies are not available: chapters render in parallel and are written as
they finish, so no worker knows about the others' text. And a documentation page
already declares its subject in places prose statistics cannot see - its title,
its headings, the identifiers it puts in code spans - so weighting those beats
counting words, in one pass over one page.

Three details make the difference on technical prose:

- **Qualified names survive whole.** A term may contain `.`, `-`, and `_`, so
  `strings.join`, `jennifer-tiny`, and `snake_case` stay single terms instead of
  being shredded into fragments. On the Jennifer library reference this is most
  of the value: `strings.substring`, `task.waitany`, `task.discard`.
- **Plurals fold into singulars** when the page uses both, so `module` and
  `modules` do not take two of the ten slots. Only an exact trailing `s` counts,
  and only when the singular is a term the page actually used.
- **Boolean literals are stopped.** Code spans score 3, so a configuration page
  full of `enabled = false` would otherwise rank `false` above the settings it is
  describing.

`keywordStopwords` adds to the built-in list, which can only know about English.
A book knows what is furniture in *its* subject - and those terms are exactly the
ones that describe every chapter equally, and so describe none. A language manual
is the clearest case:

```toml
keywordStopwords = ["def", "init", "return", "int"]
```

Without it, Jennifer's concurrency chapter offers
`task, spawn, task.discard, task.wait, return, task.waitall, def, init, int, task.waitany`;
with it, the three keywords give way to `concurrency, error, catch, try`. Entries
are lowercased and trimmed, so case in the config does not matter.

Only the first 600 characters of each section's body are read. Body text is the
weakest signal here - one point against a title's eight - and a section states
its subject in its opening sentences or not at all, so reading further buys
ranking that does not change and costs a pass over the whole book. With that cap
the whole pass is close to free - on a 155-chapter book, turning it off changes
the build by less than the difference between two runs of the same build. It
rides along with a render that has already parsed the chapter. `keywords = false`
turns it off, but there is little to save.

Ties break alphabetically, so the tag is byte-identical no matter what `--jobs`
was.

One caveat worth stating: **Google has ignored this tag since 2009.** It is still
read by some other engines, by site-internal search, and by tooling that
inventories a documentation set - which is what it is here. If none of those
apply to your book, `keywords = false` and the tag is not emitted at all.

`footer` is emitted **verbatim**, so it can carry HTML:

```toml
footer = "&copy; 2026 Example Ltd &middot; <a href=\"/imprint\">Imprint</a>"
```

That is deliberate - the footer is your own configuration, not untrusted input.
Everything else that renders text, including the book and chapter titles, goes
through the Markdown renderer and is escaped.

## `[highlight]` and `[highlightjs]`

Highlighting comes in two layers, and they are two tables because they have very
different consequences.

`[highlight]` is the switch; `[highlightjs]` describes the CDN layer, so every
key that only means something to highlight.js lives there.

| Key | Type | Default | Meaning |
| --- | ---- | ------- | ------- |
| `highlight.enabled` | bool | `false` | the master switch. On its own: the built-in Jennifer highlighter |
| `highlightjs.enabled` | bool | `false` | additionally load highlight.js from a CDN |
| `highlightjs.cdn` | string | cdnjs 11.11.1 | the CDN base URL, with no trailing slash |
| `highlightjs.style` | string | `"github"` | the highlight.js stylesheet used in light mode |
| `highlightjs.styleDark` | string | `"github-dark"` | the stylesheet used in dark mode |
| `highlightjs.languages` | list of string | `["bash", "go", "json", "yaml", "xml", "ini", "nginx"]` | extra highlight.js language packs to load |

**`[highlight]` alone** highlights Jennifer code **while the site is built**. The
spans are in the HTML that gets written, so there is no CDN, no JavaScript, and
nothing to load; it works with scripting off and over `file://`. This is the
layer to enable for a book that must make no third-party requests.

**`[highlightjs]` on top** pulls highlight.js from `cdn` and highlights the
languages the built-in highlighter does not know, loading the `languages` packs
and swapping `style` and `styleDark` with the mode selector. Blocks Grimoire
already highlighted are marked so highlight.js leaves them alone.

With `highlightjs.enabled = false`, the other three keys do nothing - there is no
stylesheet to choose and no grammar to fetch - which is exactly why they sit in
this table rather than beside the master switch.

`highlight.enabled` is the master switch:

| `highlight` | `highlightjs` | Result |
| ----------- | ------------- | ------ |
| off | off | no highlighting (the default) |
| on | off | Jennifer, at build time; nothing fetched |
| on | on | Jennifer at build time, everything else from the CDN |
| off | on | **no highlighting**, and the build says so |

The last row is a contradiction rather than an intent, and it resolves to off: a
book that says "no highlighting" should not start making third-party requests
because a second table was left enabled. The build reports the combination on
stderr instead of silently picking one of the two readings.

The default CDN URL pins a version rather than tracking latest. A documentation
build should render the same today and in a year, and a silent major-version
bump on a CDN is exactly the kind of change that breaks a language grammar.

## `[search]`

| Key | Type | Default | Meaning |
| --- | ---- | ------- | ------- |
| `enabled` | bool | `true` | build the search index and ship the search UI |
| `bodyChars` | int | `1200` | body text kept per indexed section; floored at 120 |

Indexing is per **section**, not per page, so a hit lands on the paragraph rather
than at the top of a long chapter. `bodyChars` trades index size against how
deep into a section a match can still be found. `--no-search` turns it off for a
single build without touching the file.

## `[pdf]`

| Key | Type | Default | Meaning |
| --- | ---- | ------- | ------- |
| `enabled` | bool | `false` | `grimoire build` also renders the PDF |
| `output` | string | `"book.pdf"` | the PDF path, relative to `build.out` |
| `paper` | string | `"a4"` | `a4` or `letter` |
| `bookmarkLevel` | int | `3` | bookmark headings down to this level; `0` disables the outline |
| `pageNumbers` | bool | `false` | print `page/total` at the outside edge of every page footer |
| `footerLeft` | string | `""` | a template for the other side of that footer; `""` leaves it empty |
| `titlePage` | bool | `true` | open the book with a title page; off starts it at the first chapter |
| `exclude` | list of string | `[]` | chapters to leave out of the PDF; the site still carries them |

`enabled` is what `--pdf` sets, and `grimoire pdf` renders the PDF regardless of
it. Expect the PDF to dominate the build - see
[Performance](performance.md).

`pageNumbers` needs the total page count, which does not exist until the whole
book has been laid out, so the build renders the document and *then* stamps the
footer on every page. The number is drawn inside the bottom margin in the theme's
muted colour - a footer is for placing yourself, not for reading.

`footerLeft` fills the other side, and carries two slots read from the book's own
git checkout:

| | |
| - | - |
| `{version}` | the tag the build sits on, with any leading `v` removed |
| `{commit}` | the short commit id - **only** when there is no tag |

Each is read from the environment first - `GRIMOIRE_VERSION` and
`GRIMOIRE_COMMIT` - and only then from git. That order matters for containers:
the official Jennifer image carries no git, so a build inside it would print the
template with both slots empty, while the CI job outside it knows the answer and
can pass it in.

Exactly one of the two is ever filled, which is what lets a single template cover
a release and a working build. This manual uses:

```toml
footerLeft = "Grimoire {version} Manual {commit}"
```

giving `Grimoire 1.0.0 Manual` on a tagged commit and `Grimoire Manual 0e173c1`
on anything else. The gap the empty slot leaves is closed before the line is
drawn. Where neither the environment nor git can answer - outside a checkout, or
on `jennifer-tiny`, which ships no `os/exec` - both slots come back empty and the
rest of the template still prints.

`titlePage` off drops the cover entirely and starts the PDF at the first chapter,
for a book that would rather supply its own front matter as a prefix chapter.

`exclude` names chapters that belong on the site but not on paper. Each entry is
a source path relative to `src`; one ending in `/` excludes everything beneath
it:

```toml
[pdf]
exclude = [
    "api/",              # a whole generated section
    "technical/coverage.md",
]
```

The case this exists for is a section worth publishing and not worth printing - a
generated API reference that runs to hundreds of pages of tables, a coverage
report - where the alternative is building the book twice and rendering the PDF
from the smaller one.

Two details worth knowing. Matching is by path, not by glob, because the thing
being named is a chapter or a branch of the outline and both are already paths.
And **a part whose chapters are all excluded is dropped with them**: the heading
is held back until a chapter survives to sit under it, so the printed book never
carries a part title with nothing beneath it. `--verbose` reports each chapter it
skips.

## A worked example

The `grimoire.toml` in this repository builds these pages - Grimoire renders its
own documentation:

```toml
[book]
title = "Grimoire"
description = "Build a documentation website, and a printable PDF, from a directory of Markdown files."
authors = ["mplx <jennifer@mplx.dev>"]
authorsLabel = "Written by"
language = "en"
src = "docs"

[build]
out = "site"

[html]
theme = "grimoire"
mode = "auto"
footer = 'Rendered with <a href="https://grimoire.jennifer-lang.dev/">Grimoire</a>, by itself.'
repoUrl = "https://github.com/jennifer-language/grimoire"
repoLabel = "Source"
editUrl = "https://github.com/jennifer-language/grimoire/edit/main/docs/{path}"
favicon = "favicon.ico"

[highlight]
enabled = true

[pdf]
enabled = true
output = "grimoire.pdf"
paper = "a4"
pageNumbers = true
footerLeft = "Grimoire {version} Manual {commit}"
titlePage = true
```

Note the single-quoted `footer`: TOML's literal strings take no escapes, which
makes an HTML attribute far easier to write than the `\"` of a basic string.
