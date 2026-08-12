# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The `obsidian` theme. Cool slate and a violet accent, sans-serif throughout -
 * the neutral, product-documentation look, with a genuinely dark dark mode
 * rather than a dimmed grey one.
 * @module obsidian
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
import "../palette.j" as palette;

/**
 * The theme definition.
 * @return {palette.Theme} the `obsidian` theme
 */
export func theme() {
    return palette.Theme{
        name: "obsidian",
        label: "Obsidian",
        description: "Cool slate with a violet accent; sans-serif throughout.",
        light: palette.palette(
            "#ffffff",
            "#f7f8fa",
            "#eef0f4",
            "#e0e3ea",
            "#333a45",
            "#6c7686",
            "#10141b",
            "#5b46d6",
            "#4837b5",
            "#ffffff",
            "#2c3340",
            "#f4f5f8",
            "rgba(91, 70, 214, 0.18)",
            "rgba(16, 20, 27, 0.14)"),
        dark: palette.palette(
            "#0d1017",
            "#141924",
            "#1c2331",
            "#262f40",
            "#c6cedb",
            "#7e8a9d",
            "#f0f4fa",
            "#9d8bff",
            "#b6a8ff",
            "#14102e",
            "#c6cedb",
            "#111621",
            "rgba(157, 139, 255, 0.24)",
            "rgba(0, 0, 0, 0.66)"),
        fontBody: palette.sans(),
        fontHeading: palette.sans(),
        fontMono: palette.mono(),
        radius: 6,
        contentWidth: 780
    };
}
