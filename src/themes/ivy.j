# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The `ivy` theme. A printed-book register: cream paper, a forest-green accent,
 * and serif type for body as well as headings, on a narrower measure that suits
 * long-form prose more than API tables.
 * @module ivy
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
import "../palette.j" as palette;

/**
 * The theme definition.
 * @return {palette.Theme} the `ivy` theme
 */
export func theme() {
    return palette.Theme{
        name: "ivy",
        label: "Ivy",
        description: "Cream paper and forest green; serif body for long-form prose.",
        light: palette.palette(
            "#fdfdf8",
            "#f3f5ee",
            "#e8ece1",
            "#d9e0d0",
            "#2f342c",
            "#6e7768",
            "#1a2018",
            "#2f6b42",
            "#245433",
            "#f6fbf5",
            "#333a30",
            "#f1f4ec",
            "rgba(47, 107, 66, 0.18)",
            "rgba(30, 45, 28, 0.16)"),
        dark: palette.palette(
            "#10130f",
            "#171b15",
            "#20251b",
            "#2b3226",
            "#ccd4c6",
            "#8b9584",
            "#eef3ea",
            "#78c48d",
            "#96d8a7",
            "#0c1a10",
            "#ccd4c6",
            "#141812",
            "rgba(120, 196, 141, 0.22)",
            "rgba(0, 0, 0, 0.60)"),
        fontBody: palette.serif(),
        fontHeading: palette.serif(),
        fontMono: palette.mono(),
        radius: 4,
        contentWidth: 700
    };
}
