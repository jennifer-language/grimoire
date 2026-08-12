# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The `grimoire` theme - the default. Warm parchment and ink by day, a dim
 * lamp-lit study by night, with a rust accent and old-style serif headings over
 * a system sans body. Copy this file to start a theme of your own: a theme is
 * two palettes, three font stacks, and two metrics.
 * @module grimoire
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
import "../palette.j" as palette;

/**
 * The theme definition.
 * @return {palette.Theme} the `grimoire` theme
 */
export func theme() {
    return palette.Theme{
        name: "grimoire",
        label: "Grimoire",
        description: "Warm parchment and ink with a rust accent; serif headings.",
        light: palette.palette(
            "#fbf7f0",
            "#f4ede1",
            "#ece2d2",
            "#ded1bd",
            "#3a332b",
            "#7d7263",
            "#241f19",
            "#a8531f",
            "#8a4218",
            "#fff8ef",
            "#4a4038",
            "#f3ece0",
            "rgba(168, 83, 31, 0.20)",
            "rgba(60, 44, 24, 0.18)"),
        dark: palette.palette(
            "#171412",
            "#1f1b18",
            "#2a2521",
            "#372f29",
            "#ddd3c6",
            "#9b8e7e",
            "#f5ede1",
            "#e8974e",
            "#f4b071",
            "#221709",
            "#ddd3c6",
            "#1c1917",
            "rgba(232, 151, 78, 0.25)",
            "rgba(0, 0, 0, 0.60)"),
        fontBody: palette.sans(),
        fontHeading: palette.serif(),
        fontMono: palette.mono(),
        radius: 7,
        contentWidth: 760
    };
}
