# Internals

## Source layout

```
grimoire            the launcher (a Jennifer script with a shebang)
Dockerfile          Grimoire on top of the official Jennifer image
grimoire.toml       the configuration that builds docs/ into site/
src/
  main.j            the CLI
  build.j           the build: render, write, report; parallel across chapters
  config.j          grimoire.toml -> Config, with defaults for everything
  summary.j         SUMMARY.md parser, and the directory-tree fallback
  content.j         Markdown -> HTML: anchors, link rewriting, code blocks
  highlight.j       the built-in, build-time Jennifer syntax highlighter
  layout.j          the page shell: top bar, sidebar, contents, pager, search
  palette.j         the theme model and the stylesheet generator
  theme.j           the theme registry
  themes/*.j        the ten shipped themes
  assets.j          the client runtime (mode selector, search, copy buttons)
  assets/           vendored: the Jennifer highlight.js grammar
  search.j          the search index
  pdfbook.j         the printable build
  serve.j           the local preview server
  util.j            slugs, paths, text helpers
scripts/
  screenshots.sh    regenerate the theme gallery
  theme-css.j       write one theme's stylesheet to a path
docs/               this documentation, and the book this repository builds
```

`grimoire` is a Jennifer program with a `#!/usr/bin/env -S jennifer run`
shebang - the same language as the rest of the tool - and it is deliberately
three lines of work. `src/main.j` is the program; the launcher only says where
Grimoire is installed and hands over the command line:

```jennifer
exit main.run(path.join(path.dir(os.ARGS[0]), "src"), os.ARGS);
```

That app directory is how the build finds the assets Grimoire ships - the
highlight.js grammar - without ever consulting the working directory. `main.j`
is a module rather than a script, so it takes the directory as an argument:
modules hold no mutable state in Jennifer, so there is nowhere for a program-wide
value like this to sit except a parameter.

Two things make that work from anywhere. The interpreter resolves the import
relative to the launcher's own file, so the working directory never matters. And
the launcher runs `os.ARGS[0]` through `fs.realpath` before taking its directory,
so a symlink on `PATH` - which is how a command normally gets installed - finds
the assets beside the **real** file rather than beside the link:

```sh
ln -s "$PWD/grimoire" ~/.local/bin/grimoire
```

An unresolvable path falls back to the invocation path. A book still builds
then; only the bundled highlight.js grammar would be missed, and the build says
so when it is.

## Notes on the Markdown

Rendering goes through the `markdown` module's document tree rather than its
`toHtml`, because a documentation site needs more than the plain translation:
stable heading anchors, `.md` links rewritten to `.html`, code blocks wrapped
with a language tag and a copy button, and scroll containers around tables.

The walk hands each block kind to its own renderer, and two of them are worth
calling out:

- An **`html_block`** is emitted **verbatim**, because writing one is a
  deliberate act by the book's author. It is the single exception: everything on
  the page that comes from anywhere else is escaped, and every link goes through
  `html.safeUrl`.
- A **`page_break`** renders as nothing. It is a directive for the printable
  build, and has nothing to draw on a web page.

Inline spans nest, so the children of a `**...**`, an emphasis, or a link label
are rendered as the nodes they are - which is what keeps `` **`json.Value`** ``
bold *and* monospaced, and what gets a link inside bold its `.md` rewritten to
`.html` like any other link.

## Anchors

Heading anchors follow **GitHub and mdBook exactly**, which is what lets a book
migrate without rewriting its cross-references. Punctuation is *dropped* rather
than folded to a dash, so

```markdown
### REPL (`cmd/jennifer/repl.go`)
```

anchors at `#repl-cmdjenniferreplgo`, not `#repl-cmd-jennifer-repl-go`. Getting
this wrong is quiet - the page still builds, and only the links break - so it is
worth stating: whitespace becomes a dash, runs of it are preserved, letters and
digits (including non-ASCII) are kept, and everything else vanishes. A repeated
heading gets a `-1`, `-2` suffix in document order.

Links are rewritten to match: `[x](guide/syntax.md#anchor)` becomes
`guide/syntax.html#anchor`, and a directory's `README.md` folds onto its
`index.html`, with the fragment carried through untouched.

## Search

The index is built from **sections**, not pages: a heading and the body text
under it up to `search.bodyChars`, so a hit lands on the paragraph rather than
the top of a long chapter. Both the index and the scorer are Grimoire's own -
there is no search library to load - and the index is delivered as a **script**
rather than fetched, because `fetch` on a `file://` page is blocked by every
browser and a book that cannot be read off a USB stick is a book with a
dependency it does not need.

Records are grouped per chapter and reassembled in outline order after the
parallel render, so the index is byte-identical no matter what `--jobs` was.

## The PDF

The printable build assembles every chapter into one Markdown document and hands
it to the `pdf` module, with a cover page, a nested bookmark outline, and every
chapter opening a page of its own.

That last part takes two mechanisms, because chapters are not all at the same
level. A chapter outside the parts keeps its level-one heading, and the layout
breaks the page at every level-one heading - which is also what gives the cover a
page to itself. A chapter **under a part** is demoted one level so the part
heading can own the top of the outline, and a demoted heading no longer breaks
anything; those chapters ask for the break explicitly with a `<!-- pagebreak -->`
directive, which the module parses into a `page_break` node. The chapter that
opens a part is the exception: the part heading has just broken the page, and a
second break would leave the part title alone on a sheet.

Writing the directive as an HTML comment is deliberate - the same combined source
still renders as HTML, where a browser shows nothing at all.

It picks up the book's theme throughout. Heading bars, the table header band,
the panel behind a code block, and the tint and rule on a blockquote are all
drawn from the selected theme's **light** palette - paper is white, so the dark
palette would print as slabs of toner - with heading bars taking the accent mixed
toward white, deepest at level one. So `terminal` prints with green heading bars
and a green quote rule, `sepia` with brown ones, and the hierarchy still reads at
a glance.

The tool credit lives in the document metadata rather than on the title page,
in `Creator` and `Producer`, where a reader's document properties show it.

Print differs from the site in two deliberate ways:

- **Raw HTML is dropped**, by the layout. A hand-written block has no rendering
  on paper, and left in place the Jennifer introduction's inline SVG wordmark
  typesets as a page and a half of path data before the reader reaches a
  sentence.
- **Links are resolved for paper.** A cross-reference is not clickable in print,
  so it reads as its label alone, while an external URL keeps its address in
  parentheses.

Beyond those, the print path passes each line through untouched, **indentation
included** - which matters more than it sounds. Reflowing a paragraph here, by
gathering its lines and trimming each one, would strip the indent from a
continuation line, and an indented continuation that loses its indent stops
belonging to its list item and becomes a stranded paragraph between the items.
The layout reflows paragraphs itself, so there is nothing to gain by trying.

Characters the standard-14 fonts cannot encode are transliterated here (`→` to
`->`, box drawing to `-` and `|`) before the layout sees them. The module would
substitute a single `?` for each, which is correct but says less: `->` says what
the arrow said. So Grimoire spends a transliteration table and leaves
`unencodable` as the last resort for the rest.

## What the layout does, and what it does not

Grimoire leans on the `markdown` module for more than the parse, and it is worth
knowing where the line falls - several things that look like they need code here
do not:

| | |
| - | - |
| `thematic_break`, `html_block` | a rule and a raw block are parsed, not guessed at from source |
| nested inline spans | `` **`json.Value`** `` keeps its code formatting |
| indented list continuations | a soft-wrapped item stays one item |
| autolinks | `<https://example.com>` is a link node |
| `pdf.foldLine` in the layout | a long code line folds to the column by itself |
| `quoteFill`, `quoteRule`, `codeFill`, `codeBorder` | themed panels in print |
| `creator`, `producer`, `unencodable` | metadata, and the encoding fallback |
| `page_break` / `<!-- pagebreak -->` | a demoted chapter can still open a page |

One thing the printable build cannot do: running headers and a "page N of M"
footer. `pdf.setHeader` / `setFooter` and the `%page%` / `%pages%` placeholders
exist, but `markdown.renderPdf` returns bytes rather than a `pdf.Document`, so
the document-level hooks are out of reach from the Markdown path. Having them
would mean Grimoire laying the book out page by page itself.

## Building this repository

`grimoire.toml` here builds `docs/` - the pages you are reading - so the
repository is its own worked example, and a change to the renderer shows up in
the next build of this manual:

```sh
./grimoire build        # the site and the PDF, into site/
./grimoire serve        # read it at http://127.0.0.1:8080/
```

`[pdf] enabled` is on, so a plain `build` produces `site/grimoire.pdf` as well -
which is what the download link on the [introduction](index.md) points at. Turn
it off and that link goes dead.

`.github/workflows/pages.yml` runs exactly that build on every push, in the
official Jennifer image, and publishes `site/` to GitHub Pages. It works the PDF
footer's version stamp out on the runner and passes it in as `GRIMOIRE_VERSION` /
`GRIMOIRE_COMMIT`, because the image has no git of its own. It asserts the
pieces a reader needs - the landing page, the stylesheet, the search index, a
non-empty PDF, and the link between the last two - so an empty publish fails in
CI rather than on the live site. A pull request builds and checks without
publishing.

`docs/CNAME` is what binds the custom domain, and it needs no special handling:
it is a non-Markdown file under `src`, so the ordinary asset copy puts it at
`site/CNAME`. It has to be **in the site** rather than only in the repository
settings, because a Pages deployment from an artifact publishes exactly what the
artifact holds - a build that dropped the file would quietly unbind the domain.
The pipeline asserts its contents for that reason.

Sources are formatted with `jennifer fmt` and clean under `jennifer lint`:

```sh
jennifer fmt --write src/*.j src/themes/*.j scripts/*.j
jennifer lint src/*.j src/themes/*.j scripts/*.j
```

## Possible extensions

Not built, but the shape is there for them: a link checker over the resolved
outline (the build already knows every output path and anchor), a `--watch`
rebuild loop for `serve`, and multi-language books.
