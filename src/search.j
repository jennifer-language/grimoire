# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The search index. Each record is one section of one page - everything from a
 * heading to the next - which is what makes a hit land on the paragraph a reader
 * wanted rather than at the top of a long chapter.
 *
 * The index ships as a JavaScript file that assigns a global, not as JSON
 * fetched at runtime, so search works on a site opened over `file://`. Records
 * are positional arrays rather than objects: on a book the size of a language
 * reference that alone saves a fifth of the file.
 * @module search
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use json;

import "./util.j" as util;

/**
 * One indexed section.
 * @field path {string} the page path, relative to the site root
 * @field title {string} the page title
 * @field heading {string} the section heading ("" for a page lead-in)
 * @field anchor {string} the heading's anchor id ("" for a page lead-in)
 * @field body {string} the section text, squeezed and truncated
 */
export def struct Record {
    path as string,
    title as string,
    heading as string,
    anchor as string,
    body as string
};

/**
 * Build one record, squeezing and truncating the body to `bodyChars` so a single
 * enormous section cannot dominate the index.
 * @param path {string} the page path
 * @param title {string} the page title
 * @param heading {string} the section heading
 * @param anchor {string} the anchor id
 * @param body {string} the raw section text
 * @param bodyChars {int} the body-length budget, in runes
 * @return {Record} the record
 */
export func record(
    path as string,
    title as string,
    heading as string,
    anchor as string,
    body as string,
    bodyChars as int) {
    return Record{
        path: $path,
        title: $title,
        heading: $heading,
        anchor: $anchor,
        body: util.truncate(util.squeeze($body), $bodyChars)
    };
}

/**
 * Render the index as the JavaScript the runtime loads. The records become an
 * array of five-element arrays in the field order the client reads them.
 * @param records {list of Record} the indexed sections
 * @return {string} the JavaScript source for `assets/search-index.js`
 */
export func script(records as list of Record) {
    def rows as list of list of string;
    for (def r in $records) {
        $rows[] = [$r.path, $r.title, $r.heading, $r.anchor, $r.body];
    }
    return 'window.grimoireIndex = {"docs": ' + json.encode($rows) + '};' + "\n";
}
