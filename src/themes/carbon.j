# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The `carbon` theme. Graphite with a teal accent, designed dark-first - the light mode is the
 * translation, not the other way round. Neutral surfaces keep syntax colour and
 * table rules the only things competing for attention.
 * @module carbon
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
import "../palette.j" as palette;

/**
 * The theme definition.
 * @return {palette.Theme} the `carbon` theme
 */
export func theme() {
    return palette.Theme{
        name: "carbon",
        label: "Carbon",
        description: "Graphite and teal, dark-first; built for long technical reference.",
        light: palette.palette(
            "#fbfbfc",
            "#f2f3f5",
            "#e7e9ec",
            "#d8dbe0",
            "#31363f",
            "#6a7079",
            "#14171c",
            "#0f8f8f",
            "#0b7373",
            "#ffffff",
            "#2a2f36",
            "#f0f1f3",
            "rgba(15, 143, 143, 0.18)",
            "rgba(20, 23, 28, 0.15)"),
        dark: palette.palette(
            "#08090b",
            "#101216",
            "#181b21",
            "#24282f",
            "#c8ccd4",
            "#7b828d",
            "#f2f4f8",
            "#2fd4d4",
            "#5ee3e3",
            "#04201f",
            "#c8ccd4",
            "#0c0e11",
            "rgba(47, 212, 212, 0.20)",
            "rgba(0, 0, 0, 0.72)"),
        fontBody: palette.sans(),
        fontHeading: palette.sans(),
        fontMono: palette.mono(),
        radius: 5,
        contentWidth: 800
    };
}
