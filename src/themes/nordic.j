# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The `nordic` theme. The Nord palette: arctic blue-greys, a frost-blue accent, and a dark mode
 * that is deliberately not black. Low glare and very even contrast, which suits
 * reading for an hour more than it suits a screenshot.
 * @module nordic
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
import "../palette.j" as palette;

/**
 * The theme definition.
 * @return {palette.Theme} the `nordic` theme
 */
export func theme() {
    return palette.Theme{
        name: "nordic",
        label: "Nordic",
        description: "Arctic blue-grey after the Nord palette; muted, even, low-glare.",
        light: palette.palette(
            "#fbfcfd",
            "#eff3f7",
            "#e3eaf1",
            "#d3dde7",
            "#3b4252",
            "#6b7688",
            "#2e3440",
            "#5e81ac",
            "#4c6d94",
            "#ffffff",
            "#3b4252",
            "#edf1f5",
            "rgba(94, 129, 172, 0.18)",
            "rgba(46, 52, 64, 0.14)"),
        dark: palette.palette(
            "#2e3440",
            "#343b48",
            "#3b4252",
            "#4c566a",
            "#d8dee9",
            "#93a1b5",
            "#eceff4",
            "#88c0d0",
            "#a3d4e2",
            "#22303c",
            "#d8dee9",
            "#313846",
            "rgba(136, 192, 208, 0.22)",
            "rgba(0, 0, 0, 0.55)"),
        fontBody: palette.sans(),
        fontHeading: palette.sans(),
        fontMono: palette.mono(),
        radius: 6,
        contentWidth: 780
    };
}
