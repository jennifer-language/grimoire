# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The `terminal` theme. Monospace for body, headings, and code alike, with a phosphor-green accent
 * and square corners - a console rendered as a website. Best for command
 * references and anything already dense with code.
 * @module terminal
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
import "../palette.j" as palette;

/**
 * The theme definition.
 * @return {palette.Theme} the `terminal` theme
 */
export func theme() {
    return palette.Theme{
        name: "terminal",
        label: "Terminal",
        description: "Monospace everywhere with a phosphor-green accent; a console in a browser.",
        light: palette.palette(
            "#fcfdfb",
            "#f1f4ee",
            "#e5eae0",
            "#d3dbcc",
            "#2c3329",
            "#6b7566",
            "#131912",
            "#2f7d32",
            "#245f26",
            "#f4fbf3",
            "#2c3329",
            "#f1f4ee",
            "rgba(47, 125, 50, 0.18)",
            "rgba(19, 25, 18, 0.16)"),
        dark: palette.palette(
            "#07090a",
            "#0d1113",
            "#141a1c",
            "#1f272a",
            "#b9e6c2",
            "#6f8f78",
            "#d8ffe0",
            "#35e06a",
            "#62f08e",
            "#032009",
            "#b9e6c2",
            "#0a0d0f",
            "rgba(53, 224, 106, 0.20)",
            "rgba(0, 0, 0, 0.75)"),
        fontBody: palette.mono(),
        fontHeading: palette.mono(),
        fontMono: palette.mono(),
        radius: 2,
        contentWidth: 820
    };
}
