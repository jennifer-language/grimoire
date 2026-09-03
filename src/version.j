# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Grimoire's version number, and nothing else.
 *
 * A module of its own because the number is wanted in more than one place and
 * the places cannot reach each other. `src/grimoire.j` prints it for
 * `--version`; anything further down the import graph - the layout, say, which
 * `grimoire.j` reaches through `build.j` - cannot import `grimoire.j` back
 * without a cycle. A leaf module that imports nothing can be imported by all of
 * them.
 *
 * It is also the copy the pipeline reads. `deck.toml` carries the same number,
 * the registry requires that one to match the tag a release is published from,
 * and `.github/workflows/version.yml` compares all three against each other and
 * against the tag. That workflow is called by the release and the image builds
 * before either publishes anything, so a number that drifted stops a tag rather
 * than being reported after it shipped. It reads `NUMBER` below with a regular
 * expression, so the literal stays on one line with nothing computed around it.
 * @module version
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */

# The number, in one place. Bump it here, in `deck.toml`, and in
# `packaging/arch/PKGBUILD`, then tag - CI fails the tag if the four disagree.
def const NUMBER as string init "0.3.0";

/**
 * The version on its own, as `deck.toml` and a release tag spell it.
 * @return {string} a dotted SemVer number, with no leading "v"
 */
export func number() {
    return NUMBER;
}

/**
 * The version as `--version` prints it: the command name and the number, which
 * is the form a reader quotes back in a bug report.
 * @return {string} the command name and its version
 */
export func line() {
    return "grimoire " + NUMBER;
}
