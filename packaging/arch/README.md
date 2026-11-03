# Arch packaging

`PKGBUILD` builds an Arch Linux package of Grimoire. There is nothing to
compile - Grimoire is Jennifer source - so `arch=('any')` and the package is a
copy, a symlink, and the documentation.

## What it installs

| Path | |
| ---- | - |
| `/usr/lib/grimoire/bin/grimoire` | the launcher, executable |
| `/usr/lib/grimoire/src/` | the program, including `src/themes/` and the bundled highlight.js grammar |
| `/usr/bin/grimoire` | a symlink to the launcher |
| `/usr/share/licenses/grimoire/` | `LICENSE.md` |
| `/usr/share/doc/grimoire/` | `README.md` and the `docs/` sources |

The split matters. The launcher locates `src/` **relative to itself**, resolving
symlinks before it does, and it looks one directory *up* from itself - out of
`bin/`, then down into `src/`. That is what lets one file in `/usr/bin` stand in
for a tree in `/usr/lib`. Installing the launcher directly into `/usr/bin` would
send it looking for `/usr/src`.

## Building it

The `source=` line points at the `$pkgver` tag - plain semver, no `v` - and the
checksum is the hash of GitHub's archive of that tag, so it can only be filled in
once the tag is pushed. Between a version bump and that point it is a deliberate
placeholder of zeros: a wrong hash rather than `SKIP`, so a build that skips
verification fails instead of passing quietly.

```sh
cd packaging/arch
makepkg -si
```

After tagging a release, fill it in and commit it:

```sh
cd packaging/arch
updpkgsums          # pacman-contrib
git commit -m "arch: checksum for X.Y.Z" -- PKGBUILD
```

A tag that is moved after that changes the archive, and the checksum has to be
filled in again.

`check()` runs `jennifer lint` over the sources and then builds the repository's
own documentation with `--pdf`, asserting the HTML, the PDF, and the stylesheet
all landed. That is the failure this package is most likely to have: an
interpreter too old to parse the sources it was just paired with. Nothing is
fetched during the build - `[highlightjs]` is off and the built-in highlighter
needs no network - so it is safe in a clean chroot.

Worth running before publishing anywhere:

```sh
namcap PKGBUILD
namcap grimoire-*.pkg.tar.zst
makechrootpkg -c -r "$CHROOT"    # devtools, catches a missing dependency
```

## The interpreter dependency

`depends=('jennifer>=0.25.0')` assumes the interpreter is packaged under the
name `jennifer`, which is what its binary is called. It is not in the official
repositories, so the package resolves against whatever provides that name -
check it before publishing, and adjust if upstream settles on something else.

Both this package and the one below need Jennifer 0.25.0 or later, the first
release Grimoire's sources run on.

## A VCS variant

For a `grimoire-git` package, keep `check()` and `package()` exactly as they are
apart from the directory they enter - `cd "${pkgname%-git}"` rather than
`cd "$pkgname-$pkgver"` - and replace the header with:

```sh
pkgname=grimoire-git
pkgver=0.1.0.r0.g0000000
pkgrel=1
pkgdesc="Build a documentation website, and a printable PDF, from a directory of Markdown files"
arch=('any')
url="https://github.com/jennifer-language/grimoire"
license=('LGPL-3.0-only')
depends=('jennifer>=0.25.0')
makedepends=('git')
provides=("grimoire=$pkgver")
conflicts=('grimoire')
source=("git+$url.git")
sha256sums=('SKIP')

pkgver() {
	cd "${pkgname%-git}"
	git describe --long --tags --abbrev=7 2>/dev/null |
		sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g' ||
		printf "0.r%s.g%s" "$(git rev-list --count HEAD)" \
			"$(git rev-parse --short=7 HEAD)"
}
```

`SKIP` is correct there rather than sloppy: a git source is verified by its ref,
not by a hash of a tarball.

The VCS package also gets the PDF footer stamp for free. `[pdf] footerLeft` in
this repository is `"Grimoire {version} Manual {commit}"`, and Grimoire fills
those slots from `git describe` - which a checkout can answer and a release
tarball cannot. That is why `check()` above sets `GRIMOIRE_VERSION`: the
environment is consulted before git precisely so that a build with no repository
around it can still say what it is. A `-git` package needs neither, since the
repository is right there.
