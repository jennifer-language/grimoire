<!-- The release-page blurb, and only that. `.github/workflows/release.yml` puts
     it above the install lines and the changelog for a tag, where it is read by
     someone deciding whether to take this version - so it stays short, and says
     nothing the README already says at length. The GHCR package page carries a
     separate one-sentence description; that one is in `Dockerfile` and
     `.github/workflows/docker.yml`, capped at 512 characters by the registry. -->

Build a documentation website - and a printable PDF - from a directory of
Markdown files. Written in [Jennifer](https://jennifer-lang.dev/).

A `SUMMARY.md` becomes the outline, or the directory tree is walked when there is
none. Out comes a self-contained static site - ten themes, light and dark,
searchable in eleven languages - that works from a web root, from a
subdirectory, or opened straight off the disk over `file://`, search included.
Nothing is fetched at build time unless you ask for it.

[Manual](https://grimoire.jennifer-lang.dev/) -
[Installation](https://grimoire.jennifer-lang.dev/installation.html) -
[Source and README](https://github.com/jennifer-language/grimoire)

LGPL-3.0-only. Copyright (C) 2026 mplx.
