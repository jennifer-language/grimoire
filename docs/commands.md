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
| `--nav WHERE` | from config | the book-contents column: `left`, `right`, `off` |
| `--toc WHERE` | from config | the on-this-page column: `left`, `right`, `off` |
| `-L`, `--ui-language TAG` | from config | language for Grimoire's own strings |
| `--clean` | from config | empty the output directory before building |
| `--no-clean` | from config | keep what is already in the output directory |
| `--pdf` | off | also render the book to PDF |
| `--no-search` | off | skip the search index and the search UI |
| `-j`, `--jobs N` | `0` | chapters to render in parallel; `0` is one per CPU |
| `-v`, `--verbose` | off | report each chapter as it is rendered |
| `-q`, `--quiet` | off | print nothing on success |

```sh
grimoire build
grimoire build --theme nordic --out /tmp/preview
grimoire build --pdf --jobs 4
grimoire build --nav right --toc off
grimoire build --clean
```

`--clean` empties the output directory before building, so a chapter deleted
from the book stops being published. It keeps top-level dotfiles and refuses
outright to empty a filesystem root, the working directory, or anything holding
the sources - see
[Configuration](configuration.md#emptying-the-output-directory) for the whole
rule and for `[build] clean`, which is where the setting belongs once a book has
decided. `--no-clean` is how a single run opts out of that setting.

`--nav` and `--toc` place the two navigation columns, or leave them out. Both
are covered in [Configuration](configuration.md#the-two-navigation-columns),
which is where the setting belongs once a book has decided; the flags are for
trying an arrangement before writing it down.

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
| `--nav WHERE` | from config | the book-contents column: `left`, `right`, `off` |
| `--toc WHERE` | from config | the on-this-page column: `left`, `right`, `off` |
| `--clean` | from config | empty the output directory before the first build |
| `--no-clean` | from config | keep what is already in the output directory |
| `-L`, `--ui-language TAG` | from config | language for Grimoire's own strings |
| `-w`, `--watch` | off | rebuild whenever a source file changes |
| `--no-reload` | off | with `--watch`, do not reload the browser |
| `--no-build` | off | serve what is already there, without rebuilding |

```sh
grimoire serve
grimoire serve --watch
grimoire serve --watch --nav right --toc left
grimoire serve --addr 0.0.0.0:9000 --no-build
```

Only the build `serve` does on the way in prunes. A `--watch` rebuild never
does: it would empty the directory being served on every save, and a reader who
reloaded at the wrong moment would get a 404 rather than a page.

The two column flags are here as well as on `build` because trying an
arrangement is what `--watch` is for. The override lives as long as the process
does: the watch loop rebuilds with the configuration `serve` started with, so
every rebuild keeps it. It does nothing under `--no-build`, which serves what is
already on disk.

`--watch` watches the source tree and rebuilds when it changes, naming the file
that caused it:

```
$ grimoire serve --watch
built 7 pages into site/
watching docs/ for changes (the page reloads itself)
serving site/ at http://127.0.0.1:8080/ (ctrl-c to stop)
docs/commands.md modified - rebuilding
rebuilt 7 pages into site/
```

A change that lands on several files at once - a `git checkout`, a search and
replace across the book - is one rebuild, reported as `and 3 more`. Writing the
site is not a change: the output directory is left out of the watch, so a book
that builds into its own source tree does not rebuild itself for ever.

### The browser reloads itself

With `--watch`, every page served carries a small script that polls for the
build and reloads when it changes, so a save in the editor shows up in the
window without a keystroke. `--no-reload` turns it off and leaves the watching.

Two properties are worth knowing, because they are the reason it is built this
way:

- **The script never touches the disk.** It is spliced into the response on its
  way out, so the files in the output directory are the same bytes a publish
  would upload. This is why it is not simply written into the page at build
  time: a preview build that had quietly grown a polling loop would be a bad
  thing to `rsync`. Nothing outside `serve --watch` ever emits it.
- **It polls rather than holding a socket open.** The `httpd` engine answers a
  request once and has no streaming, so there is no WebSocket and no event
  stream to push down; the script asks a `/.grimoire-reload` endpoint every 700
  ms, and the endpoint answers with one `stat` of the stylesheet - the file every
  successful build rewrites. A failed build does not move it, so a page never
  reloads into a broken one. It also reconnects for free: restart the server
  under a waiting tab and it simply starts answering again.

The published site is untouched by all of this. It carries no reload script, no
endpoint, and nothing that polls.

A build that fails does not stop the loop; it reports and waits for the next
change, which is the moment a watch loop is most useful. Editing `grimoire.toml`
is noticed but **not** applied - the loop holds the configuration resolved when
`serve` started, command-line overrides included, so it says so rather than
rebuilding with the old theme and looking like it worked:

```
grimoire.toml modified - restart serve to pick it up
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
