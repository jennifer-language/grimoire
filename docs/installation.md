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
./grimoire build          # builds this documentation, which is the repository's own book
```

That is the whole install. The repository is its own worked example: its
`grimoire.toml` builds `docs/` into `site/`, so a fresh clone has something to
build before you have written anything.

### On your `PATH`

The launcher resolves its imports relative to itself, and it resolves through a
symlink first, so it runs from any working directory under any name:

```sh
ln -s "$PWD/grimoire" ~/.local/bin/grimoire
```

The leading `./` goes away after that, and `grimoire` works inside whichever
book directory you happen to be in.

### With the embeddable interpreter

`jennifer-tiny` is the TinyGo build - smaller, embeddable, and missing the
network stack. It runs everything except `serve`. The shebang names the default
binary, so invoke the interpreter directly rather than the launcher:

```sh
jennifer-tiny run ./grimoire build
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

### A checkout, with no image build

The interpreter image plus a bind mount runs the checkout directly, which is the
fastest way to test a change to Grimoire without building anything. The `:dev`
tag is deliberate - Grimoire requires Jennifer 0.25.0 and `:latest` is still
0.24.0, so drop the tag once 0.25.0 is released:

```sh
# From the Grimoire checkout: build the book mounted at /work.
docker run --rm --user "$(id -u):$(id -g)" \
    -v "$PWD:/work" \
    ghcr.io/jennifer-language/jennifer:dev run ./grimoire build --pdf

podman run --rm --userns=keep-id \
    -v "$PWD:/work:Z" \
    ghcr.io/jennifer-language/jennifer:dev run ./grimoire build --pdf
```

The launcher is handed to the interpreter rather than executed, because the
image may have no `/usr/bin/env` to resolve a shebang with.

To build a book that lives somewhere else, mount both:

```sh
docker run --rm --user "$(id -u):$(id -g)" \
    -v "$PWD:/grimoire" -v "/path/to/my-book:/work" \
    ghcr.io/jennifer-language/jennifer:dev run /grimoire/grimoire build
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
docker build --build-arg JENNIFER_TAG=static -t grimoire:static .   # smaller base

podman build -t grimoire .
```

Nothing is compiled - Grimoire is Jennifer source, so the image is a copy and an
entrypoint on top of `ghcr.io/jennifer-language/jennifer`.

`JENNIFER_TAG` defaults to `dev` for the version reason above, and becomes
`latest` when 0.25.0 ships. The `static` line will work then too - the distroless
variant tracks the release, so today it is still 0.24.0 and there is no
`dev-static` to stand in for it.

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

A pull request runs the build and the test but never publishes. Pushes to the
default branch and tags publish to `ghcr.io/jennifer-language/grimoire`.
