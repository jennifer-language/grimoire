# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The `sixtyfour` theme, a tribute to the 8-bit home computers of the early
 * eighties. The dark mode is the screen they booted to: a blue page inside a
 * light-blue frame, with the frame colour as the ink. The light mode turns it
 * inside out - a page tinted with the frame, inked in the screen blue. Corners
 * are square, because a pixel is.
 *
 * The two anchor colours are sampled from that boot screen as an emulator draws
 * it: `#4242e7` for the screen and `#a5a5ff` for the frame and the text. They
 * are used exactly where nothing has to be read - the page, the rules - and in
 * code blocks, which sit on a deeper blue so that the original text colour
 * clears 4.5:1. Prose cannot have the original pairing: light blue on that blue
 * is under 3:1, so body and secondary text keep the hue and move toward white.
 *
 * Headings and code are monospace, the body sans: a whole page in fixed-width
 * glyphs is a screen, not a page.
 * @module sixtyfour
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
import "../palette.j" as palette;

/**
 * The theme definition.
 * @return {palette.Theme} the `sixtyfour` theme
 */
export func theme() {
    return palette.Theme{
        name: "sixtyfour",
        label: "Sixtyfour",
        description: "A retro 8-bit boot screen: blue framed in light blue, inverted by day.",
        light: palette.palette(
            "#f0f0ff",
            "#e4e4ff",
            "#d8d8fc",
            "#a5a5ff",
            "#1c1c6e",
            "#4a4a90",
            "#4242e7",
            "#4242e7",
            "#2a2aa8",
            "#ffffff",
            "#4242e7",
            "#e4e4ff",
            "rgba(165, 165, 255, 0.45)",
            "rgba(66, 66, 231, 0.16)"),
        dark: palette.palette(
            "#4242e7",
            "#3333b8",
            "#3b3bd3",
            "#a5a5ff",
            "#e0e0ff",
            "#d2d2ff",
            "#ffffff",
            "#aaffee",
            "#ffffff",
            "#20207a",
            "#a5a5ff",
            "#2a2aa8",
            "rgba(165, 165, 255, 0.45)",
            "rgba(10, 10, 60, 0.55)"),
        fontBody: palette.sans(),
        fontHeading: palette.mono(),
        fontMono: palette.mono(),
        radius: 0,
        contentWidth: 800
    };
}
