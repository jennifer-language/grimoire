# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Keyword extraction for the `keywords` meta tag: what a page is about, in ten
 * words, worked out from the page itself.
 *
 * The scoring is structural rather than statistical. A classic TF-IDF pass would
 * need corpus-wide document frequencies, and chapters are rendered in parallel
 * and written as they finish - there is no point in the build where one worker
 * knows about the others' text. More to the point, a documentation page already
 * says what it is about in places prose statistics cannot see: its title, its
 * headings, and the identifiers it puts in code spans. Weighting those beats
 * counting words, and it needs one pass over one page.
 *
 * A term scores the sum of its weighted occurrences:
 *
 * | where it appears | weight |
 * | ---------------- | -----: |
 * | the page title   | 8 |
 * | a level-2 heading | 4 |
 * | a deeper heading | 3 |
 * | a code span | 3 |
 * | body text | 1 |
 *
 * So a word in the title outranks eight mentions in prose, and an identifier the
 * page discusses outranks three - which is the right answer for a reference page
 * whose subject is named twice and used everywhere.
 * @module keywords
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use strings;
use lists;
use maps;
use convert;
use regex;

import "./content.j" as content;
import "./util.j" as util;

# The weights above.
def const W_TITLE as int init 8;
def const W_H2 as int init 4;
def const W_HEADING as int init 3;
def const W_CODE as int init 3;
def const W_BODY as int init 1;

# A term shorter than this is noise in every language this is likely to meet.
def const MIN_LENGTH as int init 3;

# How much of a section's body is read. Body text is the weakest signal here -
# one point against a title's eight - and a section states its subject in its
# opening sentences or not at all, so reading further buys ranking that does not
# change and costs a pass over the whole book. The search index truncates its
# records for the same reason.
def const BODY_CHARS as int init 600;

# Folded into the sort key so a higher score sorts first; it only has to exceed
# any score a single page can produce.
def const SCORE_SCALE as int init 1000000;

# Words that carry no subject on their own. Deliberately English-only and
# deliberately short: this is a stop list, not a linguistic model, and a term
# that survives it still has to outscore the page's real subject to appear.
#
# The literals at the end are here because code spans score 3: a configuration
# page full of `enabled = false` would otherwise rank `false` above the settings
# it is describing.
def const STOPWORDS as list of string init [
    "a",
    "about",
    "above",
    "after",
    "again",
    "against",
    "all",
    "also",
    "am",
    "an",
    "and",
    "any",
    "are",
    "as",
    "at",
    "be",
    "because",
    "been",
    "before",
    "being",
    "below",
    "between",
    "both",
    "but",
    "by",
    "can",
    "cannot",
    "could",
    "did",
    "do",
    "does",
    "doing",
    "done",
    "down",
    "during",
    "each",
    "either",
    "else",
    "enough",
    "even",
    "every",
    "few",
    "for",
    "from",
    "further",
    "get",
    "gets",
    "give",
    "gives",
    "had",
    "has",
    "have",
    "having",
    "he",
    "her",
    "here",
    "hers",
    "him",
    "his",
    "how",
    "however",
    "i",
    "if",
    "in",
    "into",
    "is",
    "it",
    "its",
    "itself",
    "just",
    "keep",
    "keeps",
    "let",
    "like",
    "make",
    "makes",
    "many",
    "may",
    "me",
    "might",
    "more",
    "most",
    "much",
    "must",
    "my",
    "need",
    "needs",
    "no",
    "nor",
    "not",
    "now",
    "of",
    "off",
    "on",
    "once",
    "one",
    "only",
    "onto",
    "or",
    "other",
    "others",
    "our",
    "ours",
    "out",
    "over",
    "own",
    "per",
    "put",
    "rather",
    "same",
    "see",
    "she",
    "should",
    "since",
    "so",
    "some",
    "still",
    "such",
    "take",
    "takes",
    "than",
    "that",
    "the",
    "their",
    "theirs",
    "them",
    "then",
    "there",
    "these",
    "they",
    "thing",
    "things",
    "this",
    "those",
    "though",
    "through",
    "to",
    "too",
    "under",
    "until",
    "up",
    "use",
    "used",
    "uses",
    "using",
    "very",
    "was",
    "way",
    "ways",
    "we",
    "well",
    "were",
    "what",
    "when",
    "where",
    "whether",
    "which",
    "while",
    "who",
    "whom",
    "why",
    "will",
    "with",
    "within",
    "without",
    "would",
    "you",
    "your",
    "yours",
    "true",
    "false",
    "null",
    "nil",
    "none"
];

# The code spans on a page, read back out of the rendered HTML.
#
# Reading the output rather than the tree is a shortcut, but a safe one: this
# module is the only consumer and `content` is the only producer, so the pattern
# matches markup Grimoire wrote itself, three lines away from where it wrote it.
# A span holding markup rather than text is skipped - it would be a nested tag,
# which a code span cannot contain.
def const CODE_SPAN as string init '<code>([^<>]*)</code>';

# unescape turns the five character references `content` emits back into the
# characters they stand for.
#
# Without this the tag picks up the *entity names*: a code span holding `a&b`
# reaches here as `a&amp;b`, and `amp` scores as though the page were about it.
# `&amp;` goes last, so a literal `&amp;amp;` in the source cannot be unescaped
# twice.
func unescape(text as string) {
    def out as string init strings.replace($text, "&lt;", "<");
    $out = strings.replace($out, "&gt;", ">");
    $out = strings.replace($out, "&quot;", '"');
    $out = strings.replace($out, "&#39;", "'");
    return strings.replace($out, "&amp;", "&");
}

# A term: starts and ends on a letter or digit, and may carry `.`, `-`, or `_`
# inside. Anchoring both ends is what keeps `join,` and `(spawn` and `module.`
# out without a separate trimming pass.
#
# Extracting terms with one regex rather than a character loop is not a
# micro-optimisation. A loop over `strings.chars` of every section of every
# chapter runs in the interpreter, and on a 2.3 MiB book it tripled the build;
# the same work inside the regex engine is free by comparison.
def const TERM as string init '[a-z0-9](?:[a-z0-9._-]*[a-z0-9])?';

# A term that is only digits and separators - a version number, a page count -
# names nothing on its own.
def const NUMERIC as string init '^[0-9._-]+$';

# stopSet turns the stop list into a set, once per page. Every term on the page
# is tested against it, so the difference between a hash lookup and a walk down a
# 140-element list is the difference between a keyword pass that costs nothing
# and one that doubles the build.
#
# `extra` is the book's own additions. The built-in list can only know about
# English; a book knows what is furniture in *its* subject - the keywords of the
# language it documents, the name of its own product on every page - and those
# are exactly the terms that describe every chapter equally and so describe none.
func stopSet(extra as list of string) {
    def out as map of string to int;
    for (def word in STOPWORDS) {
        $out[$word] = 1;
    }
    for (def word in $extra) {
        def clean as string init strings.lower(strings.trim($word));
        if ($clean != "") {
            $out[$clean] = 1;
        }
    }
    return $out;
}

# scoreable reports whether a term has the shape of one worth scoring: long
# enough, and not a bare number.
#
# It deliberately does **not** take the stop set, which the caller tests instead.
# Maps are values in Jennifer, so a map handed to a function is deep-copied into
# it - and this is called once per token, which made a 145-entry copy per word of
# the book and a sixth of the site build. The lookup is a hash either way; it is
# the crossing of the call boundary that costs.
#
# The order inside is by cost. The length test is free; the regex runs only for a
# term that starts with a digit, which is the only kind that can be all digits
# and separators.
func scoreable(term as string) {
    if (len($term) < MIN_LENGTH) {
        return false;
    }
    def first as string init strings.substring($term, 0, 1);
    if ($first < "0" or $first > "9") {
        return true;
    }
    return not regex.matches(NUMERIC, $term);
}

# terms splits a run of text into scoreable terms.
func terms(text as string) {
    def out as list of string;
    for (def m in regex.findAll(TERM, strings.lower($text))) {
        $out[] = $m.text;
    }
    return $out;
}

# One run of text and what an occurrence in it is worth.
def struct Run {
    text as string,
    weight as int
};

# foldPlurals merges a plural into its singular when the page uses both, keeping
# the combined score under the singular. Cheap and safe where a stemmer would be
# neither: only an exact trailing `s` counts, and only when the singular is a
# term the page actually used - so `modules` folds into `module`, while `strings`
# stays put unless `string` is there too.
func foldPlurals(scores as map of string to int) {
    def folded as map of string to int;
    for (def term in maps.keys($scores)) {
        if (not strings.endsWith($term, "s") or len($term) <= MIN_LENGTH) {
            continue;
        }
        def single as string init strings.substring($term, 0, len($term) - 1);
        if (maps.has($scores, $single)) {
            $folded[$term] = $scores[$term];
        }
    }
    def out as map of string to int;
    for (def term in maps.keys($scores)) {
        if (maps.has($folded, $term)) {
            continue;
        }
        def total as int init $scores[$term];
        if (maps.has($folded, $term + "s")) {
            $total = $total + $folded[$term + "s"];
        }
        $out[$term] = $total;
    }
    return $out;
}

# ranked orders the scored terms: highest score first, and alphabetically within
# a score, so the same page always produces the same list. The sort is over a
# padded key rather than a comparator, which `lists.sort` does not take.
func ranked(scores as map of string to int) {
    def keys as list of string;
    for (def term in maps.keys($scores)) {
        def inverted as int init SCORE_SCALE - $scores[$term];
        $keys[] = convert.toString($inverted) + ":" + $term;
    }
    def out as list of string;
    for (def key in lists.sort($keys)) {
        def at as int init strings.indexOf($key, ":");
        $out[] = strings.substring($key, $at + 1, len($key));
    }
    return $out;
}

/**
 * The keywords for one rendered page, most significant first.
 *
 * @param r {content.Rendered} the rendered page
 * @param limit {int} how many keywords to return at most
 * @param extra {list of string} further stop words, from the book's configuration
 * @return {list of string} the keywords, highest scoring first
 */
export func extract(r as content.Rendered, limit as int, extra as list of string) {
    def runs as list of Run;
    $runs[] = Run{text: $r.title, weight: W_TITLE};
    for (def h in $r.headings) {
        if ($h.level <= 1) {
            continue;
        }
        def weight as int init W_HEADING;
        if ($h.level == 2) {
            $weight = W_H2;
        }
        $runs[] = Run{text: $h.text, weight: $weight};
    }
    for (def s in $r.sections) {
        $runs[] = Run{text: util.truncate($s.text, BODY_CHARS), weight: W_BODY};
    }
    for (def m in regex.findAll(CODE_SPAN, $r.html)) {
        $runs[] = Run{text: unescape($m.groups[0]), weight: W_CODE};
    }
    # Two maps that stay here. Maps are values in Jennifer, so a helper that took
    # the scores and handed them back would copy every entry on the way in and on
    # the way out - once per heading and once per section - and a helper that
    # merely *read* the stop set would copy it once per token. Both are filled
    # and tested where they live; on a book of any size that copying, not the
    # tokenizing, is the whole cost.
    def stops as map of string to int init stopSet($extra);
    def scores as map of string to int;
    for (def run in $runs) {
        for (def term in terms($run.text)) {
            if (not scoreable($term) or maps.has($stops, $term)) {
                continue;
            }
            if (maps.has($scores, $term)) {
                $scores[$term] = $scores[$term] + $run.weight;
            } else {
                $scores[$term] = $run.weight;
            }
        }
    }
    def out as list of string;
    for (def term in ranked(foldPlurals($scores))) {
        if (len($out) >= $limit) {
            break;
        }
        $out[] = $term;
    }
    return $out;
}

/**
 * The keywords for one rendered page as a `keywords` meta tag value ("" when the
 * page yields none).
 * @param r {content.Rendered} the rendered page
 * @param limit {int} how many keywords to include at most
 * @param extra {list of string} further stop words, from the book's configuration
 * @return {string} the comma-separated keyword list
 */
export func line(r as content.Rendered, limit as int, extra as list of string) {
    return strings.join(extract($r, $limit, $extra), ", ");
}
