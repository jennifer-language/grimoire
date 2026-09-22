# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `stopwords.j`, run by `jennifer test src/stopwords_test.j`.
 *
 * Nine word lists cannot be tested for being *right* - that is a judgement about
 * a language, and it is made when a word is added. What can be tested is the
 * shape they have to have to work at all, and every one of these has a way of
 * going wrong quietly:
 *
 * - a word with a capital in it never matches, because the scoring lowercases
 *   before it looks;
 * - a word with a space or an apostrophe in it never matches, because the term
 *   pattern breaks on both;
 * - a word shorter than the length floor is dead weight rather than a bug, but
 *   a *list* that is nothing but those is a list that does nothing;
 * - and English has to reach every book, or a German page loses `the` from its
 *   code spans.
 *
 * The lists are letters and nothing else. `scripts/check-style.sh` allows those,
 * and `scripts/check-print.j` never looks here - a stop word is consulted rather
 * than printed.
 * @module stopwords_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use lists;
use strings;
use maps;

# Every catalog, in the order `LANGUAGES` names them. A language added there and
# forgotten here is a length mismatch in the first test rather than an untested
# list.
func catalogs() {
    return [EN, DE, ES, FR, IT, NL, PL, PT, RU];
}

# --- the language list -----------------------------------------------

func testNineLanguagesEnglishFirst() {
    testing.assertEqual(len(names()), 9);
    testing.assertEqual(names()[0], "en");
}

func testTheCatalogListMatchesTheLanguageList() {
    testing.assertEqual(len(catalogs()), len(names()));
}

func testLanguageTagsAreUnique() {
    def seen as list of string;
    for (def lang in names()) {
        testing.assertFalse(lists.contains($seen, $lang));
        $seen[] = $lang;
    }
}

# Japanese and Chinese are in `src/locale.j` and deliberately not here: they
# write without spaces between words, so `keywords.j` skips those scripts rather
# than treat a clause as a term. A list added for either would be unreachable.
func testTheUnsegmentedScriptsHaveNoList() {
    testing.assertFalse(lists.contains(names(), "ja"));
    testing.assertFalse(lists.contains(names(), "zh"));
}

# --- the shape of every entry ----------------------------------------

# The scoring lowercases a page before it tokenizes it, so an entry with a
# capital in it can never match anything.
func testEveryEntryIsLowercase() {
    for (def catalog in catalogs()) {
        for (def word in $catalog) {
            testing.assertEqual(strings.lower($word), $word);
        }
    }
}

# A term is a run of letters and digits that may carry `.`, `-`, or `_` inside.
# An entry holding a space or an apostrophe is not a term and never will be, so
# French `d'un` is listed as `d` and `un`.
func testNoEntryHoldsASpaceOrAnApostrophe() {
    for (def catalog in catalogs()) {
        for (def word in $catalog) {
            testing.assertNotEqual($word, "");
            testing.assertEqual(strings.trim($word), $word);
            testing.assertFalse(strings.contains($word, " "));
            testing.assertFalse(strings.contains($word, "'"));
        }
    }
}

# Sorted by codepoint, which is what `lists.sort` gives and what keeps an
# addition landing in one place rather than wherever the diff was open. The
# accented forms trail the plain ones as a consequence - German `fuer` with an
# umlaut sits after `zwischen` - which looks odd and is the price of a rule a
# test can check.
func testEveryCatalogIsSorted() {
    for (def catalog in catalogs()) {
        testing.assertEqual(strings.join($catalog, " "), strings.join(lists.sort($catalog), " "));
    }
}

func testNoCatalogRepeatsAWord() {
    for (def catalog in catalogs()) {
        def seen as map of string to int;
        for (def word in $catalog) {
            testing.assertFalse(maps.has($seen, $word));
            $seen[$word] = 1;
        }
    }
}

func testEveryCatalogCarriesWordsAboveTheLengthFloor() {
    for (def catalog in catalogs()) {
        def long as int init 0;
        for (def word in $catalog) {
            if (len($word) >= 3) {
                $long = $long + 1;
            }
        }
        testing.assertTrue($long > 50);
    }
}

# --- forLanguage -----------------------------------------------------

# The words the report showed: a German book whose keyword tags read
# `und, willkommen, die, das, ist` was describing German, not itself.
func testGermanStopsTheWordsThatDescribedNothing() {
    def de as list of string init forLanguage("de");
    for (def word in [
        "und",
        "die",
        "das",
        "der",
        "ist",
        "einem",
        "oder",
        "dein",
        "sie",
        "nicht",
        "eine",
        "ein"
    ]) {
        testing.assertTrue(lists.contains($de, $word));
    }
}

# Technical writing is bilingual wherever it quotes an identifier, and the
# literals score three points each for sitting in a code span.
func testEnglishAndTheLiteralsReachEveryBook() {
    for (def lang in names()) {
        def words as list of string init forLanguage($lang);
        testing.assertTrue(lists.contains($words, "the"));
        testing.assertTrue(lists.contains($words, "false"));
    }
}

func testEachLanguageAddsItsOwnWordsOnTopOfEnglish() {
    def base as int init len(forLanguage("xx"));
    for (def lang in names()) {
        if ($lang == "en") {
            continue;
        }
        testing.assertTrue(len(forLanguage($lang)) > $base);
    }
}

# `de-AT` is German. The book this came from is Austrian.
func testARegionTagResolvesToItsLanguage() {
    testing.assertEqual(len(forLanguage("de-AT")), len(forLanguage("de")));
    testing.assertTrue(lists.contains(forLanguage("de-AT"), "und"));
    testing.assertTrue(lists.contains(forLanguage("pt-BR"), "para"));
    testing.assertTrue(has("de-AT"));
    testing.assertTrue(has("pt-BR"));
}

func testTheTagIsReadCaseInsensitively() {
    testing.assertEqual(len(forLanguage("DE")), len(forLanguage("de")));
    testing.assertTrue(has("DE-at"));
}

# An unknown language is not an error. The book keeps the English list, and
# `keywordStopwords` is where its author fills the gap.
func testAnUnknownLanguageKeepsEnglish() {
    testing.assertFalse(has("xx"));
    testing.assertFalse(has(""));
    def words as list of string init forLanguage("xx");
    testing.assertEqual(len($words), len(EN) + len(LITERALS));
    testing.assertTrue(lists.contains($words, "the"));
}

# English asks for no second copy of itself.
func testEnglishIsNotAddedTwice() {
    testing.assertEqual(len(forLanguage("en")), len(forLanguage("xx")));
    testing.assertEqual(len(forLanguage("en-GB")), len(forLanguage("xx")));
}
