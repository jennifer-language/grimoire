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

```sh
bin/grimoire init my-book     # scaffold a book
bin/grimoire build            # build the site
bin/grimoire build --pdf      # site plus the printable book
bin/grimoire pdf              # the printable book on its own
bin/grimoire serve            # build, then preview on :8080
bin/grimoire themes           # list the built-in themes
```

Point it at a directory of Markdown. If that directory holds a `SUMMARY.md` it
is used as the book outline (the mdBook shape); if it does not, the outline is
derived from the directory tree (the way MkDocs does). The output is a
self-contained static site - themed, searchable, with a mandatory dark mode -
that works served from a web root, served from a subdirectory, or opened
straight off the disk over `file://`, search included. Nothing is fetched from
anywhere unless you opt in.

The words Grimoire adds around your text - "Search", "On this page", the
colour-mode buttons - follow the book's `language`, in English and ten more.

Ten themes ship, each with a light and a dark palette:

![grimoire](docs/screenshots/grimoire.png)

## Documentation

Everything lives in [`docs/`](docs/index.md), which Grimoire builds with itself:

| | |
| - | - |
| [Introduction](docs/index.md) | what it does, in one page |
| [Installation](docs/installation.md) | from a checkout, or from a container with Docker or Podman |
| [Commands](docs/commands.md) | every subcommand and flag |
| [Configuration](docs/configuration.md) | `grimoire.toml`, key by key |
| [Themes](docs/themes.md) | the ten themes, with screenshots, and how to write one |
| [Internals](docs/internals.md) | the source layout, and what Grimoire does to the Markdown |
| [Performance](docs/performance.md) | where the time goes, and why it scales the way it does |

```sh
bin/grimoire build --src docs --out docs-site
```

## Requirements

Jennifer 0.25.0 or newer. `build`, `pdf`, `init`, and `themes` run on both the
default binary and `jennifer-tiny`; `serve` needs the default binary, since
`jennifer-tiny` stubs `httpd`.

Or none of it: the [installation page](docs/installation.md) has the Docker and
Podman lines, which need nothing on the machine but the container runtime.

## Trying it

`grimoire.toml` here builds `docs/` - this documentation - so the repository is
its own worked example:

```sh
bin/grimoire serve        # read it at http://127.0.0.1:8080/
```

## License

LGPL-3.0-only. Copyright (C) 2026 mplx &lt;jennifer@mplx.dev&gt;.
