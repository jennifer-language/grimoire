# Arch packaging

Two PKGBUILDs, in the same shape as jvc's:

| | |
| - | - |
| `PKGBUILD` | `grimoire`, from the release tarball published with each tag |
| `PKGBUILD-git` | `grimoire-git`, from the tip of `main` |

There is nothing to compile - Grimoire is Jennifer source - so both are
`arch=('any')`, and a package is a copy, a symlink, and the documentation. There
is no `-bin` variant, because the release tarball is already the runtime tree.

## What it installs

| Path | |
| ---- | - |
| `/usr/share/grimoire/bin/grimoire` | the launcher, executable |
| `/usr/share/grimoire/src/` | the program, including `src/themes/` and the bundled highlight.js grammar |
| `/usr/share/grimoire/plugins/` | the plugins that ship with Grimoire, found there by name |
| `/usr/bin/grimoire` | a symlink to the launcher |
| `/usr/share/licenses/grimoire/` | `LICENSE.md` |
| `/usr/share/doc/grimoire/` | `README.md` and the manual's Markdown |

The split matters. The launcher locates `src/` **relative to itself**, resolving
symlinks before it does, and it looks one directory *up* from itself - out of
`bin/`, then down into `src/`. That is what lets one file in `/usr/bin` stand in
for a tree in `/usr/share`. Installing the launcher directly into `/usr/bin`
would send it looking for `/usr/src`.

The plugins stay beside the launcher rather than in `/usr/bin`: Grimoire looks in
its own `plugins/` before `PATH`, so a bare `[preprocessor.include]` still finds
one, and `grimoire` stays the only command - `grimoire<TAB>` is a completed word,
not a prefix shared with twelve others. The test overlays are not installed;
nothing imports them at run time.

## The release package

**Every release publishes a ready `PKGBUILD`** beside the packages, with the tag
and the checksum filled in, and the built package itself. To install a release:

```sh
sudo pacman -U grimoire-0.4.0-1-any.pkg.tar.zst
```

or build it from that published `PKGBUILD`:

```sh
makepkg -si
```

The copy in this directory is the template the release pipeline stamps. Its
checksum is a deliberate placeholder of zeros - a wrong hash rather than `SKIP`,
so a build that skips verification fails instead of passing quietly - and
`updpkgsums` fills it in when you build from it by hand.

`source=` is the release tarball (`scripts/build-tarball.sh`), not GitHub's
source archive, which carries the tests, examples, packaging and CI config. The
tarball is reproducible - one timestamp, the tag's commit date, on every member -
so the published checksum stays true when the tag is rebuilt.

`check()` runs `jennifer lint` over the sources and then builds a small book with
`--pdf`, asserting that the HTML and the PDF landed. That is the failure this
package is most likely to have: an interpreter too old to parse the sources it
was just paired with. Nothing is fetched, so it is safe in a clean chroot.
`GRIMOIRE_VERSION` is how the PDF footer gets its version stamp there: the
environment is consulted before git, so that a build with no repository around
it can still say what it is.

Worth running before publishing to the AUR:

```sh
namcap PKGBUILD
namcap grimoire-*.pkg.tar.zst
makechrootpkg -c -r "$CHROOT"    # devtools, catches a missing dependency
```

## The VCS package

`PKGBUILD-git` builds the tip of `main`:

```sh
makepkg -si -p PKGBUILD-git
```

Its version is the newest release tag plus the commits since -
`0.4.0.r12.g1a2b3c4` - so it sorts above the release it is ahead of. `SKIP` is
correct for its checksum rather than sloppy: a git source is verified by its
ref, not by a hash of a tarball.

Its `check()` does more than the release package's can, because it has the whole
repository: the unit tests (`scripts/test.sh`, the plugins' included), the lint,
and a build of this repository's own manual with `--pdf`. The PDF footer stamp
comes for free there - `[pdf] footerLeft` is `"Grimoire {version} Manual
{commit}"`, and Grimoire fills those slots from `git describe`, which a checkout
can answer.

## The interpreter dependency

Both depend on `jennifer` **unversioned**, on purpose. Grimoire needs Jennifer
0.26.0 or later, but `jennifer-bin` and `jennifer-git` provide an unversioned
`jennifer`, so `jennifer>=0.26.0` would be unsatisfiable and pacman would refuse
the package. The interpreter enforces the floor itself, at load time, from the
`# pragma-jennifer-version` line in every source file. Add the version once the
interpreter packages declare `provides=("jennifer=$pkgver")`.

`git` is optional at run time: it stamps the PDF footer with the book's version,
and `grimoire-feed` and `grimoire-lastmod` date chapters from it. Without it
those are left out, and the book still builds.
