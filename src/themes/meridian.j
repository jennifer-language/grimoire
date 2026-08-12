# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The `meridian` theme. A calm navy-on-white register with a steel-blue accent -
 * the look of a product handbook meant to be read at a desk. Sans throughout,
 * low chrome.
 *
 * The page stays white, because that is the register; everything drawn on it is
 * navy rather than slate. That is also what keeps it apart from `obsidian`, the
 * other white-paged sans theme: the ink here is a true deep blue, the panels are
 * visibly blue-tinted rather than neutral grey, the accent is a dark steel blue
 * at hue 207 against that theme's violet at 249, and the dark mode is navy
 * instead of blue-black.
 * @module meridian
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
import "../palette.j" as palette;

/**
 * The theme definition.
 * @return {palette.Theme} the `meridian` theme
 */
export func theme() {
    return palette.Theme{
        name: "meridian",
        label: "Meridian",
        description: "Deep navy on white with a steel-blue accent; the product-handbook register.",
        light: palette.palette(
            "#ffffff",
            "#eef3fa",
            "#e1eaf6",
            "#c8d7ea",
            "#1e3050",
            "#5a6d8c",
            "#0a1e3d",
            "#175c96",
            "#114a7c",
            "#ffffff",
            "#213652",
            "#eff4fb",
            "rgba(23, 92, 150, 0.18)",
            "rgba(10, 30, 61, 0.14)"),
        dark: palette.palette(
            "#0d1b30",
            "#132540",
            "#1b3153",
            "#264066",
            "#c4d5ea",
            "#7d95b5",
            "#e9f2ff",
            "#6fb2e8",
            "#96caf3",
            "#04203a",
            "#c4d5ea",
            "#101f36",
            "rgba(111, 178, 232, 0.24)",
            "rgba(0, 0, 0, 0.65)"),
        fontBody: palette.sans(),
        fontHeading: palette.sans(),
        fontMono: palette.mono(),
        radius: 6,
        contentWidth: 790
    };
}
