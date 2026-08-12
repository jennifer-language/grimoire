# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The `ember` theme. Maximum contrast on near-white and near-black, an orange
 * accent, square corners, and a wide measure - built for dense reference pages
 * full of wide tables rather than for reading chapter after chapter.
 * @module ember
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
import "../palette.j" as palette;

/**
 * The theme definition.
 * @return {palette.Theme} the `ember` theme
 */
export func theme() {
    return palette.Theme{
        name: "ember",
        label: "Ember",
        description: "High-contrast mono-neutral with an orange accent; wide measure.",
        light: palette.palette(
            "#ffffff",
            "#fafafa",
            "#f0f0f0",
            "#e2e2e2",
            "#2b2b2b",
            "#6b6b6b",
            "#111111",
            "#d2451e",
            "#b03718",
            "#ffffff",
            "#262626",
            "#f6f6f6",
            "rgba(210, 69, 30, 0.18)",
            "rgba(0, 0, 0, 0.16)"),
        dark: palette.palette(
            "#0a0a0a",
            "#131313",
            "#1c1c1c",
            "#2a2a2a",
            "#d4d4d4",
            "#8a8a8a",
            "#fafafa",
            "#ff7a45",
            "#ff9668",
            "#1a0d05",
            "#d4d4d4",
            "#101010",
            "rgba(255, 122, 69, 0.24)",
            "rgba(0, 0, 0, 0.70)"),
        fontBody: palette.sans(),
        fontHeading: palette.sans(),
        fontMono: palette.mono(),
        radius: 3,
        contentWidth: 860
    };
}
