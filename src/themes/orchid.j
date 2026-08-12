# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The `orchid` theme. A softer, warmer take on the neutral documentation look:
 * mauve-tinted paper and a violet-pink accent. Reads as approachable rather than
 * corporate, without giving up contrast.
 *
 * The cast is in the paper, not only in the accent. `obsidian` and `meridian`
 * both start from a pure white page and differ only in what the links are
 * coloured; this one tints every surface toward mauve and puts the accent on the
 * pink side of violet - around hue 310 against the 250 those two share - so the
 * three do not collapse into one cool-neutral look. The dark mode follows: plum
 * rather than the blue-black the rest of the cool themes use.
 * @module orchid
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
import "../palette.j" as palette;

/**
 * The theme definition.
 * @return {palette.Theme} the `orchid` theme
 */
export func theme() {
    return palette.Theme{
        name: "orchid",
        label: "Orchid",
        description: "Mauve-tinted paper with a violet-pink accent; friendly and light.",
        light: palette.palette(
            "#faf5f9",
            "#f3ebf2",
            "#ebe0ea",
            "#dccbdb",
            "#403345",
            "#756579",
            "#251a2b",
            "#a03a92",
            "#852f79",
            "#fff8fd",
            "#3d3342",
            "#f4ecf3",
            "rgba(160, 58, 146, 0.18)",
            "rgba(56, 30, 52, 0.16)"),
        dark: palette.palette(
            "#1a1220",
            "#231829",
            "#2f2136",
            "#402e48",
            "#e0d2e2",
            "#a08faa",
            "#f8ecf6",
            "#e492d5",
            "#f0b0e2",
            "#2a0b23",
            "#e0d2e2",
            "#1e1526",
            "rgba(228, 146, 213, 0.24)",
            "rgba(0, 0, 0, 0.66)"),
        fontBody: palette.sans(),
        fontHeading: palette.sans(),
        fontMono: palette.mono(),
        radius: 8,
        contentWidth: 770
    };
}
