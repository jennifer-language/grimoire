# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>

/**
 * Distances and areas on a plane.
 *
 * Small on purpose: it exists so the demo has something to document.
 * @module geo
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use math;

/**
 * A point on the plane.
 * @field x {float} the horizontal coordinate
 * @field y {float} the vertical coordinate
 */
export def struct Point {
    x as float,
    y as float
};

/**
 * The straight-line distance between two points.
 * @param a {Point} one point
 * @param b {Point} the other
 * @return {float} the distance, never negative
 */
export func distance(a as Point, b as Point) {
    def dx as float init $b.x - $a.x;
    def dy as float init $b.y - $a.y;
    return math.sqrt($dx * $dx + $dy * $dy);
}

/**
 * The area of the triangle three points describe.
 * @param a {Point} the first corner
 * @param b {Point} the second corner
 * @param c {Point} the third corner
 * @return {float} the area, zero when the points are collinear
 */
export func area(a as Point, b as Point, c as Point) {
    def twice as float init ($b.x - $a.x) * ($c.y - $a.y) - ($c.x - $a.x) * ($b.y - $a.y);
    return math.abs($twice) / 2.0;
}
