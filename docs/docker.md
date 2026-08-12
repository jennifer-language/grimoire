# Docker

## From a source checkout, with no image build

The official Jennifer image already carries the interpreter and every module
Grimoire imports, so a checkout runs as-is. The `:dev` tag is deliberate -
Grimoire requires Jennifer 0.25.0 and `:latest` is still 0.24.0, so drop the tag
once 0.25.0 is released:

```sh
# From the Grimoire checkout: build the book mounted at /work.
docker run --rm --user "$(id -u):$(id -g)" \
    -v "$PWD:/work" \
    ghcr.io/jennifer-language/jennifer:dev run ./grimoire build --pdf
```

The base image runs as `nonroot`, so `--user "$(id -u):$(id -g)"` is what lets
it write into the bind mount as you rather than as a stranger. The launcher is
handed to the interpreter rather than executed, because the image may have no
`/usr/bin/env` to resolve a shebang with.

To build a book that lives somewhere else, mount both:

```sh
docker run --rm --user "$(id -u):$(id -g)" \
    -v "$PWD:/grimoire" -v "/path/to/my-book:/work" \
    ghcr.io/jennifer-language/jennifer:dev run /grimoire/grimoire build
```

## The Grimoire image

For everyday use there is a prebuilt image with Grimoire baked in, so the book
is the only thing you mount:

```sh
docker run --rm --user "$(id -u):$(id -g)" \
    -v "$PWD:/work" ghcr.io/jennifer-language/grimoire build --pdf

docker run --rm -p 8080:8080 \
    -v "$PWD:/work" ghcr.io/jennifer-language/grimoire serve --addr 0.0.0.0:8080
```

`serve` binds `127.0.0.1` by default, which inside a container means nothing
outside can reach it - hence the explicit `--addr 0.0.0.0:8080` above.

The entrypoint is Grimoire itself, so everything after the image name is a
[Grimoire command](commands.md); `--entrypoint sh` if you want a shell instead.

Build it yourself with the `Dockerfile` at the repository root:

```sh
docker build -t grimoire .
docker build --build-arg JENNIFER_TAG=static -t grimoire:static .   # smaller base
```

Nothing is compiled - Grimoire is Jennifer source, so the image is a copy and an
entrypoint on top of `ghcr.io/jennifer-language/jennifer`.

`JENNIFER_TAG` defaults to `dev` for the version reason above, and becomes
`latest` when 0.25.0 ships. The `static` line will work then too - the distroless
variant tracks the release, so today it is still 0.24.0 and there is no
`dev-static` to stand in for it.

## The CI pipeline

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
