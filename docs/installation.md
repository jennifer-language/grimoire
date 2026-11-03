# Installation

Grimoire is Jennifer source with a shebang on the front. Nothing is compiled,
there is no build step and no package to install, so "installing" it means only
putting the interpreter and a checkout where they can find each other - or
skipping both and running a container.

Pick whichever fits:

| | |
| - | - |
| [A checkout](#from-a-checkout) | the usual way, and the one to use while writing a book |
| [A package](#from-a-package) | Arch Linux, with a `PKGBUILD` in the repository |
| [A container](#in-a-container) | nothing on the machine but Docker or Podman |

## Requirements

**Jennifer 0.25.0 or newer.** `build`, `pdf`, `init`, and `themes` run on both
the default binary and `jennifer-tiny`; `serve` needs the default binary, since
`jennifer-tiny` stubs `httpd`.

The container images carry a suitable interpreter, so nothing below the
container section needs Jennifer on the host.

## From a checkout

```sh
git clone https://github.com/jennifer-language/grimoire
cd grimoire
bin/grimoire build          # builds this documentation, which is the repository's own book
```

That is the whole install. The repository is its own worked example: its
`grimoire.toml` builds `docs/` into `site/`, so a fresh clone has something to
build before you have written anything.

### On your `PATH`

The launcher resolves its imports relative to itself, and it resolves through a
symlink first, so it runs from any working directory under any name:

```sh
ln -s "$PWD/bin/grimoire" ~/.local/bin/grimoire
```

The leading `./` goes away after that, and `grimoire` works inside whichever
book directory you happen to be in.

### With the embeddable interpreter

`jennifer-tiny` is the TinyGo build - smaller, embeddable, and missing the
network stack. It runs everything except `serve`. The shebang names the default
binary, so invoke the interpreter directly rather than the launcher:

```sh
jennifer-tiny run bin/grimoire build
```

## From a package

**Arch Linux.** `packaging/arch/PKGBUILD` in the repository builds one:

```sh
cd packaging/arch
updpkgsums          # the checksum placeholder is deliberate, see the README there
makepkg -si
```

It lands the program in `/usr/lib/grimoire` with a symlink at `/usr/bin/grimoire`,
which is the same arrangement as the `ln -s` above and for the same reason - the
launcher looks for `src/` beside its own resolved path. Its `check()` lints the
sources and then builds this documentation with `--pdf`, so a mismatch between
the package and the installed interpreter fails at build time rather than at
first use. `packaging/arch/README.md` covers the rest, including a `-git`
variant.

There is no package for any other distribution yet. The container images below
are the portable answer in the meantime.

## In a container

Two images are involved, and which one you want depends on whether you are
running Grimoire or working on it:

- **`ghcr.io/jennifer-language/grimoire`** has Grimoire baked in and Grimoire as
  its entrypoint. Mount a book, name a command, done. This is the one to use.
- **`ghcr.io/jennifer-language/jennifer`** is the plain interpreter image. It
  already carries every module Grimoire imports, so a Grimoire checkout runs
  under it as-is with no image build - which is what you want when the point is
  to change Grimoire rather than to use it.

Both are multi-arch (`linux/amd64` and `linux/arm64`).

Docker and Podman both run them, and the command lines differ by one flag. Each
recipe below is written out for both.

### The Grimoire image

The book is the only thing you mount:

```sh
# Docker
docker run --rm --user "$(id -u):$(id -g)" \
    -v "$PWD:/work" ghcr.io/jennifer-language/grimoire build --pdf

# Podman, rootless
podman run --rm --userns=keep-id \
    -v "$PWD:/work:Z" ghcr.io/jennifer-language/grimoire build --pdf
```

The entrypoint is Grimoire itself, so everything after the image name is a
[Grimoire command](commands.md) with its flags. Pass `--entrypoint sh` if you
want a shell in there instead.

| Tag | What it is |
| --- | ---------- |
| `latest` | the newest release - what the commands above pull |
| `0.4.0` | one release, unchanging |
| `0.4` | the newest release of that line |
| `dev` | the tip of the default branch, unreleased; `main` is the same image |

`latest` follows the highest release rather than the last one tagged, so a
patch to an older line does not take it back.

Serving needs a published port and an address to bind:

```sh
# Docker
docker run --rm -p 8080:8080 -v "$PWD:/work" \
    ghcr.io/jennifer-language/grimoire serve --addr 0.0.0.0:8080

# Podman, rootless
podman run --rm -p 8080:8080 -v "$PWD:/work:Z" \
    ghcr.io/jennifer-language/grimoire serve --addr 0.0.0.0:8080
```

`serve` binds `127.0.0.1` by default, which inside a container means nothing
outside it can connect - hence the explicit `--addr 0.0.0.0:8080`. That is the
container's loopback being a different loopback from yours, not a Grimoire
setting worth changing in `grimoire.toml`.

### Plugins in the image

The twelve plugins that [ship with Grimoire](plugins.md) are in the image already,
at `/opt/grimoire/plugins`, found by name the way they are in any other install.
A book enables one the only way any book does - by naming it:

```toml
[renderer.epub]
output = "book.epub"
```

```sh
docker run --rm --user "$(id -u):$(id -g)" \
    -v "$PWD:/work" ghcr.io/jennifer-language/grimoire build
```

Nothing else is needed, and nothing is enabled that a book does not ask for.
`docker run --rm ghcr.io/jennifer-language/grimoire plugins` run against a
mounted book lists what that book would execute.

**Anything else is a third-party plugin, and the image treats it as one.**
`/opt/grimoire-plugins` is a directory of plugin directories the image can carry,
and it is switched off: `GRIMOIRE_PLUGINS` links the named ones onto `PATH` at
startup, and the book's own table still has to name them. Two decisions, neither
of them a default, because an image that mounts your directory and runs programs
over it should ask twice.

```sh
docker run --rm --user "$(id -u):$(id -g)" \
    -e GRIMOIRE_PLUGINS=mermaid \
    -v "$PWD:/work" ghcr.io/jennifer-language/grimoire build
```

The official image carries no such collection, so `GRIMOIRE_PLUGINS` there
refuses every name and says which ones it has. To use it, put the plugin
directories into `plugins-src/` before building the image, or add them in a layer
of your own:

```dockerfile
FROM ghcr.io/jennifer-language/grimoire
USER root
COPY grimoire-mermaid /opt/grimoire-plugins/grimoire-mermaid
USER jennifer
```

Names are given without the `grimoire-` prefix, separated by commas or spaces. A
name the image does not carry is refused before the build starts. `GRIMOIRE_PLUGIN_DIR`
moves the link directory, which matters under `--read-only`: the default is
`/tmp/grimoire-plugins`, so that image needs `--tmpfs /tmp` or a writable
directory named here.

**Some plugins need a program the image has not got**, and say so at startup
when a `NEEDS` file names it. `grimoire-feed` and `grimoire-lastmod` date
chapters from `git log`, and the base image carries no git; `grimoire-mermaid`
needs `mmdc` and `grimoire-katex` needs `katex`. Add what you use in a layer of
your own:

```dockerfile
FROM ghcr.io/jennifer-language/grimoire
USER root
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*
USER jennifer
```

### A checkout, with no image build

The interpreter image plus a bind mount runs the checkout directly, which is the
fastest way to test a change to Grimoire without building anything. Name the
release line, `:0.25`, rather than leaving the tag off: Jennifer's `latest` is
currently its distroless `static` image, which has no `/usr/bin/env` to start a
plugin with.

```sh
# From the Grimoire checkout: build the book mounted at /work.
docker run --rm --user "$(id -u):$(id -g)" \
    -v "$PWD:/work" \
    ghcr.io/jennifer-language/jennifer:0.25 run bin/grimoire build --pdf

podman run --rm --userns=keep-id \
    -v "$PWD:/work:Z" \
    ghcr.io/jennifer-language/jennifer:0.25 run bin/grimoire build --pdf
```

The launcher is handed to the interpreter rather than executed, because the
image may have no `/usr/bin/env` to resolve a shebang with.

To build a book that lives somewhere else, mount both:

```sh
docker run --rm --user "$(id -u):$(id -g)" \
    -v "$PWD:/grimoire" -v "/path/to/my-book:/work" \
    ghcr.io/jennifer-language/jennifer:0.25 run /grimoire/grimoire build
```

### Why the two flags differ

Everything else is the same command, so the difference is worth knowing rather
than copying.

**Docker** runs the container through a root daemon, and the base image runs as
`nonroot`. Files written into a bind mount would land owned by that user rather
than by you, and `--user "$(id -u):$(id -g)"` is what makes the built site
yours.

**Rootless Podman** already runs inside a user namespace, and by default maps
your host UID to root inside the container - so the image's `nonroot` user comes
out as one of your subordinate UIDs on the host, and the built site belongs to
nobody you can name. `--userns=keep-id` maps your UID to itself instead, which
gets the same result as Docker's `--user` and makes that flag unnecessary. Under
`sudo podman` the mapping question does not arise and the Docker line is the
right one.

**`:Z`** on the mount asks Podman to relabel it for SELinux, which matters on
Fedora, RHEL, CentOS Stream, and anywhere else running SELinux in enforcing
mode; without it the container is denied the mount it was just given. It is
harmless where SELinux is not enforcing. Docker wants the same suffix on the
same distributions - it is listed only on the Podman lines above because that is
where the pairing is most often needed, not because Docker is exempt.

### Building the image yourself

With the `Dockerfile` at the repository root:

```sh
docker build -t grimoire .

podman build -t grimoire .
```

Nothing is compiled - Grimoire is Jennifer source, so the image is a copy and an
entrypoint on top of `ghcr.io/jennifer-language/jennifer`.

The twelve plugins that ship are in `plugins/` and are copied in with the rest of
Grimoire. `plugins-src/` is the third-party collection, empty in a checkout: put
plugin directories there before building to bake them into the image, or leave it
alone and the image carries none, which `GRIMOIRE_PLUGINS` then reports instead
of failing later.

The entrypoint is a shell script, because something has to read
`GRIMOIRE_PLUGINS` before Grimoire starts. That is the second thing in the
`Dockerfile` needing a shell, and both are what a distroless `:static` base would
have to solve differently - plugins are processes, so a distroless image could
not run one anyway.

`JENNIFER_TAG` defaults to `0.25`, the Jennifer release line Grimoire's sources
require. Not `latest`, which Jennifer currently publishes as its distroless
`static` image: the distroless variant is no base for this one, because both the
`RUN` that installs the launcher and the entrypoint need a shell.

### The CI pipeline

`.github/workflows/docker.yml` builds that image on every push and pull request.

It builds a **single-arch image first and smoke-tests it** - `--version`,
`themes`, and a real book built end to end with `--pdf`, asserting the HTML, the
PDF, and the stylesheet all landed - and only then builds the multi-arch
(`linux/amd64` + `linux/arm64`) manifest and pushes it to GHCR. Testing before
the expensive emulated arm64 build is the point of the two-stage shape: a broken
image fails in a minute rather than after the whole matrix.

The test runs the image the way a reader would, with
`--user "$(id -u):$(id -g)"` and a bind-mounted book, so a permissions
regression in the image is caught by CI rather than by the first person to
try it.

A pull request runs the build and the test but never publishes. A push to the
default branch publishes `dev` and `main`; a release tag publishes its version,
its `MAJOR.MINOR`, and `latest` if it is the highest release.

## Publishing to GitHub Pages

`.github/workflows/docs-pages.yml` is a reusable workflow that publishes a book
to GitHub Pages from its **latest release** rather than from the tip of the
default branch. A reader who installs the latest release then reads the
documentation of that release, not of options merged since.

A release is a tag in plain semver - `MAJOR.MINOR.PATCH`, no leading `v`, no
pre-release suffix - and the highest one wins, compared number by number:
`0.10.0` outranks `0.9.3`, and a patch to an older line does not take the site
back to it. A pull request is built and checked but never published.

```yaml
on:
  push:
    tags: ["[0-9]+.[0-9]+.[0-9]+"]
  pull_request:
  workflow_dispatch:

jobs:
  pages:
    permissions:
      contents: read
      pages: write
      id-token: write
    uses: jennifer-language/grimoire/.github/workflows/docs-pages.yml@<release>
    with:
      image: ghcr.io/jennifer-language/grimoire:<release>
      args: --pdf
```

The repository needs two settings, once:

1. **Settings, Pages:** the source is *GitHub Actions*.
2. **Settings, Environments, `github-pages`:** allow deployments from tags.
   GitHub usually creates the environment with the default branch as its only
   deployment branch, and a deploy started by a tag is then refused with *Tag
   "1.2.0" is not allowed to deploy to github-pages due to environment
   protection rules*. Add a tag rule, `[0-9]*.[0-9]*.[0-9]*`.

The project needs one release tag of its own before the first publish.

| Input | Default | |
| ----- | ------- | - |
| `image` | `grimoire:latest` | the container the book is built in; pin it |
| `launcher` | `""` | a Grimoire launcher in the repository, run with a plain Jennifer `image` instead |
| `directory` | `.` | where `grimoire.toml` is |
| `args` | `""` | extra flags for `grimoire build` |
| `plugins` | `""` | `GRIMOIRE_PLUGINS` for the Grimoire image |
| `dev` | `false` | also build the default branch, under `/dev/` |
| `check` | `""` | a shell script that fails the run before anything is published |

`check` runs in the checkout the book was built from, with the output directory
in `SITE`, the release in `RELEASE`, and the container in `IMAGE`. The caller has
to grant the `permissions`: a called workflow can narrow them but never widen
them. Pin `uses` to a Grimoire release rather than `main`, for the same reason
the workflow exists. 0.4.0 is the first release that carries `docs-pages.yml`,
so it is the oldest `<release>` can name.

Pin `image` to the same release. `latest` is the newest Grimoire release, never
unreleased code, but it moves: a book republished after a Grimoire release is
built by that release, and may come out different from the build its own
release got. With both pinned, a Grimoire upgrade is a one-line change the
project chooses to make.

With `dev: true`, add `branches: [main]` to the trigger, so a merge publishes the
new `/dev/` - without it, a push to the default branch would only republish the
same release. Nothing marks the `/dev/` pages as unreleased to a search engine:
expect them to be indexed beside the release, and the sitemap a `sitemap`
renderer writes into `/dev/` to list the release's addresses rather than its
own.
