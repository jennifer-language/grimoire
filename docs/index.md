# Jennifer's Grimoire

Build a documentation website - and a printable PDF - from a directory of
Markdown files. What mdBook, MkDocs, and similar tools do - written in
[Jennifer](https://jennifer-lang.dev/).

> **A grimoire is a book of magical knowledge** - astrological rules, lists of
> angels and demons, spells, and instructions for making talismans - copied and
> recopied across Europe from the late Middle Ages into the eighteenth century.
> The best known are the *Clavicula Salomonis*, the *Grimorium Verum*, and the
> *Grand Grimoire*.
>
> The word comes from Old French *gramaire*, which is also the root of *grammar*
> and of *glamour*: a book of rules that, to anyone who could not read it, looked
> like sorcery. This one only makes websites.

Point it at a directory of Markdown. If that directory holds a `SUMMARY.md` it
is used as the book outline, in the mdBook shape; if it does not, the outline is
derived from the directory tree, the way MkDocs does. The output is a
self-contained static site - themed, searchable, with a colour-mode selector -
plus, on request, the whole book as one paginated PDF.

```sh
./grimoire init my-book     # scaffold a book
./grimoire build            # build the site
./grimoire build --pdf      # site plus the printable book
./grimoire pdf              # the printable book on its own
./grimoire serve            # build, then preview on :8080
./grimoire themes           # list the built-in themes
```

`grimoire` is a Jennifer script with a shebang; the program itself is
`src/main.j`. It runs from any working directory and through any symlink, so
either put the checkout on your `PATH` or link the launcher into a directory
already on it, and the leading `./` goes away:

```sh
ln -s "$PWD/grimoire" ~/.local/bin/grimoire
```

A built site is a directory of files that works served from a web root, served
from a subdirectory, or **opened straight off the disk over `file://`** - search
included. Nothing is fetched from anywhere unless you opt in, and the only
setting that reaches off the machine at all is `[highlightjs]`, which is off by
default.

> **[Read this manual as a single PDF](grimoire.pdf).** Every page in one
> paginated file, with a clickable outline in your reader's bookmark panel and
> `page/total` in the footer - handy for reading offline. It is built from these
> same pages on every build, so it never drifts from the site.

## What it does

- **Two outline styles.** `SUMMARY.md` with part headings, nested entries,
  prefix and suffix chapters, drafts, and separators; or no `SUMMARY.md` at all,
  in which case the directory tree becomes the outline.
- **Anchors that match mdBook and GitHub exactly**, so hand-written
  cross-references survive a migration. ``### REPL (`cmd/jennifer/repl.go`)``
  anchors at `#repl-cmdjenniferreplgo`, not `#repl-cmd-jennifer-repl-go`.
- **Links rewritten**: `[x](guide/syntax.md#anchor)` becomes
  `guide/syntax.html#anchor`; a directory `README.md` folds onto its
  `index.html`.
- **Client-side search** over per-section records, so a hit lands on the
  paragraph rather than the top of a long chapter. Opens with `/` or `Ctrl-K`,
  arrow keys to move, `Enter` to open. No search library: the index and the
  scorer are both Grimoire's own, and the index loads as a script rather than a
  `fetch` so it works over `file://`.
- **A preview that reloads itself.** `serve --watch` rebuilds on save and
  reloads the open page, with the script that does it spliced into the response
  rather than written to disk - the published files never carry it.
- **[Eleven interface languages](configuration.md#the-interface-language).** The
  twenty-odd words Grimoire adds around your text - "Search", "On this page",
  "Previous" - follow the book's `language`, with English wherever no
  translation exists yet.
- **[Ten themes](themes.md)**, each with a light and a dark palette.
- **A mandatory dark mode.** Every theme ships both palettes; the selector in
  the top bar offers light, dark, and follow-the-system, and the choice is
  stamped on the document before the first paint, so there is no white flash on
  navigation.
- **Syntax highlighting in two layers.** `[highlight]` alone highlights Jennifer
  **while the site is built** - no CDN, no JavaScript, nothing to load, and it
  works with scripting off. `[highlightjs]` additionally pulls highlight.js from
  a configurable CDN for the other languages. Both are off by default, and the
  second does nothing without the first.
- **A logo** beside the title: an SVG is inlined, so it inherits the colour mode
  and costs no extra request.
- **A printable book**: every chapter in one PDF, with a cover page, chapters
  starting on fresh pages, a nested bookmark outline, and document metadata. It
  wears the book's theme too - heading bars, table headers, code panels, and the
  tint and rule on a blockquote all come from the theme's light palette.
- **Chapters render in parallel**, one task per CPU, with the work split
  longest-chapter-first. With `--pdf`, the PDF is laid out *alongside* the site
  rather than after it.
- **Deterministic output.** The same input produces byte-identical files -
  including the search index, whose order does not depend on how the work was
  split across jobs.

## Where to go next

| | |
| - | - |
| [Commands](commands.md) | every subcommand and flag |
| [Configuration](configuration.md) | `grimoire.toml`, key by key |
| [Themes](themes.md) | the ten themes, with screenshots, and how to write one |
| [Docker](docker.md) | running from the official image, and the Grimoire image |
| [Internals](internals.md) | the source layout, and what Grimoire does to the Markdown |
| [Performance](performance.md) | where the time goes, and why it scales the way it does |

## Requirements

Jennifer 0.25.0 or newer.

`build`, `pdf`, `init`, and `themes` run on both the default binary and
`jennifer-tiny`; `serve` needs the default binary, since `jennifer-tiny` stubs
`httpd`. To pick the embeddable interpreter, invoke it directly rather than
through the shebang:

```sh
jennifer-tiny run ./grimoire build
```

## License

LGPL-3.0-only. Copyright (C) 2026 mplx &lt;jennifer@mplx.dev&gt;.
