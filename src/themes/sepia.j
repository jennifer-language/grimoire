# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The `sepia` theme. Yellowed paper and coffee brown, serif throughout - the
 * archival register, and the gentlest of the ten on a bright screen. A narrow
 * measure keeps long prose comfortable.
 *
 * Where `grimoire` is warm-neutral parchment with a rust accent, this one commits
 * to the yellow: the paper is visibly aged rather than merely off-white, the
 * accent is a deep unlit brown instead of a bright rust, and the dark mode is
 * dark *brown* - old leather - rather than the near-black `grimoire` uses. The
 * two started out close enough to be mistaken for each other; they are not meant
 * to be alternatives of the same idea.
 * @module sepia
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
import "../palette.j" as palette;

/**
 * The theme definition.
 * @return {palette.Theme} the `sepia` theme
 */
export func theme() {
    return palette.Theme{
        name: "sepia",
        label: "Sepia",
        description: "Yellowed paper and deep coffee brown; full serif, warm through both modes.",
        light: palette.palette(
            "#f2e9d2",
            "#eae0c4",
            "#e2d5b4",
            "#cfbf9a",
            "#3d3222",
            "#6f6047",
            "#2a2114",
            "#7a4a24",
            "#613919",
            "#fdf8ec",
            "#463a28",
            "#ece2c8",
            "rgba(122, 74, 36, 0.22)",
            "rgba(72, 54, 30, 0.22)"),
        dark: palette.palette(
            "#221a12",
            "#2b2118",
            "#362a1e",
            "#453626",
            "#e6d8bd",
            "#a4906f",
            "#f6ecd6",
            "#cfa76a",
            "#e3bd85",
            "#241806",
            "#e6d8bd",
            "#261d14",
            "rgba(207, 167, 106, 0.24)",
            "rgba(0, 0, 0, 0.62)"),
        fontBody: palette.serif(),
        fontHeading: palette.serif(),
        fontMono: palette.mono(),
        radius: 5,
        contentWidth: 700
    };
}
