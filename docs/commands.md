# Commands

Five commands. Every flag has a long form; the common ones have a short form
too, and `--help` on any command prints the same table.

```sh
grimoire --help          # the command list
grimoire build --help    # one command's flags
grimoire --version
```

A flag always wins over [`grimoire.toml`](configuration.md), so a one-off build
needs no edit to the file.

## `grimoire build`

Render the site.

| Flag | Default | What it does |
| ---- | ------- | ------------ |
| `-c`, `--config PATH` | `grimoire.toml` | which configuration file to read |
| `-s`, `--src DIR` | from config | the directory of Markdown to build |
| `-o`, `--out DIR` | from config | where to write the site |
| `-t`, `--theme NAME` | from config | theme to use; `grimoire themes` lists them |
| `-m`, `--mode MODE` | from config | first-visit colour mode: `auto`, `light`, `dark` |
| `--pdf` | off | also render the book to PDF |
| `--no-search` | off | skip the search index and the search UI |
| `-j`, `--jobs N` | `0` | chapters to render in parallel; `0` is one per CPU |
| `-v`, `--verbose` | off | report each chapter as it is rendered |
| `-q`, `--quiet` | off | print nothing on success |

```sh
grimoire build
grimoire build --theme nordic --out /tmp/preview
grimoire build --pdf --jobs 4
```

The exit status is `1` when the outline names a chapter with no file behind it -
the rest of the book still builds, and the missing entries are reported on
stderr.

## `grimoire pdf`

Render only the PDF, skipping the site.

| Flag | Default | What it does |
| ---- | ------- | ------------ |
| `-c`, `--config PATH` | `grimoire.toml` | which configuration file to read |
| `-s`, `--src DIR` | from config | the directory of Markdown to build |
| `-o`, `--out DIR` | from config | where to write the PDF |
| `-v`, `--verbose` | off | report each chapter as it is laid out |
| `--output FILE` | from config | PDF filename, relative to the output directory |
| `--paper SIZE` | from config | `a4` or `letter` |

```sh
grimoire pdf
grimoire pdf --paper letter --output manual.pdf
```

## `grimoire serve`

Build, then serve the result on a local address until interrupted.

| Flag | Default | What it does |
| ---- | ------- | ------------ |
| `-c`, `--config PATH` | `grimoire.toml` | which configuration file to read |
| `-s`, `--src DIR` | from config | the directory of Markdown to build |
| `-o`, `--out DIR` | from config | which directory to serve |
| `-v`, `--verbose` | off | report each chapter as it is rendered |
| `-a`, `--addr ADDR` | `127.0.0.1:8080` | address to listen on |
| `--no-build` | off | serve what is already there, without rebuilding |

```sh
grimoire serve
grimoire serve --addr 0.0.0.0:9000 --no-build
```

The server runs a small pool of accept loops, because a browser asks for the
page, the stylesheet, the runtime, and (on the first search) the index in
parallel; a single-threaded loop would serialise them. It needs the default
`jennifer` binary - `jennifer-tiny` stubs `httpd` and says so.

## `grimoire init [dir]`

Write a starter book - `grimoire.toml`, a `SUMMARY.md`, and three chapters -
into `dir`, or into the current directory if none is given.

```sh
grimoire init my-book
```

Existing files are never overwritten. Running it twice is safe: the second run
reports each file it kept, which also makes it a way to add the pieces you
deleted back.

## `grimoire themes`

List the built-in themes with a one-line description of each. See
[Themes](themes.md) for what they look like.

## Verbose output

`--verbose` names each chapter as it goes, which is how you find the one that is
slow or throwing:

```
$ grimoire build --verbose --jobs 1
building docs -> site (theme grimoire, 13 chapters, 1 job)
  render  index.md  ->  index.html
  render  guide/syntax.md  ->  guide/syntax.html
  ...
  assets  stylesheet, runtime, search index
  copied  2 files from docs
```

Chapters render in parallel, so with the default `--jobs` the lines arrive in
the order chapters *finish*, not the order they are listed. Pass `--jobs 1` when
you want outline order.

`--verbose` and `--quiet` are not exclusive: verbose adds progress, quiet
suppresses the closing summary. Passing both gives progress and no summary.
