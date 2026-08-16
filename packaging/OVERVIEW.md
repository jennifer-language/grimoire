# Grimoire

Build a documentation website - and a printable PDF - from a directory of
Markdown files. Written in [Jennifer](https://jennifer-lang.dev/).

Point it at Markdown. A `SUMMARY.md` becomes the outline (the mdBook shape); with
no `SUMMARY.md` the directory tree is walked instead (the way MkDocs does). Out
comes a self-contained static site - ten themes, light and dark, searchable in
eleven languages - that works from a web root, from a subdirectory, or opened
straight off the disk over `file://`, search included. Nothing is fetched from
anywhere unless you ask for it.

## Run it

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" \
    ghcr.io/jennifer-language/grimoire build --pdf

podman run --rm --userns=keep-id -v "$PWD:/work:Z" \
    ghcr.io/jennifer-language/grimoire build --pdf
```

The book is whatever you mount at `/work`, and everything after the image name is
a Grimoire command with its flags:

```sh
init my-book     scaffold a book
build            build the site
build --pdf      the site and the printable book
pdf              the printable book on its own
serve            build, then preview on :8080
themes           list the built-in themes
```

`serve` inside a container needs a published port and an address to bind:
`-p 8080:8080 ... serve --addr 0.0.0.0:8080`.

Multi-arch: `linux/amd64` and `linux/arm64`.

## Elsewhere

| | |
| - | - |
| [Manual](https://grimoire.jennifer-lang.dev/) | every command, every setting, the themes |
| [Source](https://github.com/jennifer-language/grimoire) | the repository, and the full README |
| [Installation](https://grimoire.jennifer-lang.dev/installation.html) | a checkout, an Arch package, or this image |

Grimoire is Jennifer source with a shebang - nothing is compiled - so a checkout
runs under the plain `ghcr.io/jennifer-language/jennifer` image with no image
build at all. That is the one to use when the point is to change Grimoire rather
than to use it.

LGPL-3.0-only. Copyright (C) 2026 mplx.
