# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `locale.j`, run by `jennifer test src/locale_test.j`.
 *
 * Two jobs here. The first is the module's own behaviour: region tags, the
 * fallback, and `install` being enough to make every worker translate.
 *
 * The second is the catalogs themselves, and it is the reason this file earns
 * its keep. Eleven parallel maps of twenty-two keys are exactly the shape that
 * rots quietly - a key added to English and forgotten in Polish shows up as a
 * raw key name on a Polish reader's page and nowhere else. `testEveryCatalog...`
 * below compares all eleven against English on every run.
 *
 * `src/locale.j` is also the one file the repository's ASCII check excludes, so
 * that a Russian translation can be Cyrillic. Excluded from the grep is not the
 * same as unchecked: the typographic characters the rule is actually about are
 * still banned there, and `testNoCatalogUsesTypographicPunctuation` is what
 * enforces it now that the one-liner cannot.
 * @module locale_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use maps;
use lists;
use strings;
use convert;

# Every catalog, in the order `install` loads them. Kept beside `LANGUAGES` in
# spirit: a language added there and forgotten here shows up as a length
# mismatch in the first test below rather than as an untested translation.
func catalogs() {
    return [EN, DE, ES, FR, IT, JA, NL, PL, PT, RU, ZH];
}

# --- the language list -----------------------------------------------

func testElevenLanguagesEnglishFirst() {
    testing.assertEqual(len(names()), 11);
    testing.assertEqual(names()[0], "en");
}

# `intl` treats the first catalog loaded as the default, so English being first
# in `LANGUAGES` is what makes an untranslated key fall back to English rather
# than to whichever language happens to sort first.
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

# --- base and has ----------------------------------------------------

func testBaseStripsTheRegion() {
    testing.assertEqual(base("de"), "de");
    testing.assertEqual(base("de-AT"), "de");
    testing.assertEqual(base("pt-BR"), "pt");
    testing.assertEqual(base("ZH-hans"), "zh");
}

func testHasAcceptsEveryShippedLanguage() {
    for (def lang in names()) {
        testing.assertTrue(has($lang));
    }
}

func testHasAcceptsARegionalTag() {
    testing.assertTrue(has("de-AT"));
    testing.assertTrue(has("pt-BR"));
    testing.assertTrue(has("en-GB"));
}

func testHasRejectsAnUntranslatedLanguage() {
    testing.assertFalse(has("xx"));
    testing.assertFalse(has(""));
    testing.assertFalse(has("klingon"));
}

# --- the catalogs are parallel ---------------------------------------

# The test this file exists for. A key added to English and forgotten elsewhere
# renders as its own name on that language's pages, which nothing else notices.
func testEveryCatalogHasExactlyTheEnglishKeys() {
    def keys as list of string init maps.keys(EN);
    testing.assertTrue(len($keys) > 0);
    for (def catalog in catalogs()) {
        testing.assertEqual(len(maps.keys($catalog)), len($keys));
        for (def key in $keys) {
            testing.assertTrue(maps.has($catalog, $key));
        }
    }
}

func testNoTranslationIsEmpty() {
    for (def catalog in catalogs()) {
        for (def key in maps.keys($catalog)) {
            testing.assertNotEqual(strings.trim($catalog[$key]), "");
        }
    }
}

# Only one string in any catalog carries a placeholder, and it is `intl`'s
# `%query%` rather than a Jennifer interpolation slot. A translation that drops
# it loses the reader's search term.
func testThePlaceholderSurvivesTranslation() {
    for (def key in maps.keys(EN)) {
        def carries as bool init strings.contains(EN[$key], "%query%");
        for (def catalog in catalogs()) {
            testing.assertEqual(strings.contains($catalog[$key], "%query%"), $carries);
        }
    }
}

# --- the punctuation rule the ASCII grep cannot reach ----------------

# The codepoints `CLAUDE.md` bans everywhere: em and en dash, the curly quotes,
# the typographic ellipsis, and the non-breaking space. Letters are fine here -
# Russian is Cyrillic or it is not a translation - but these are not letters.
def const BANNED as list of int init [8212, 8211, 8216, 8217, 8220, 8221, 8230, 160];

func testNoCatalogUsesTypographicPunctuation() {
    for (def catalog in catalogs()) {
        for (def key in maps.keys($catalog)) {
            for (def ch in strings.chars($catalog[$key])) {
                testing.assertFalse(lists.contains(BANNED, convert.toCodepoint($ch)));
            }
        }
    }
}

# Three periods, here as everywhere else in the repository.
func testEllipsesAreThreePeriods() {
    for (def catalog in catalogs()) {
        for (def key in maps.keys($catalog)) {
            def value as string init $catalog[$key];
            if (strings.contains(EN[$key], "...")) {
                testing.assertTrue(strings.contains($value, "...") or
                    not strings.contains($value, "."));
            }
        }
    }
}

# --- install and tr --------------------------------------------------

func testInstallSelectsTheLanguage() {
    install("de");
    testing.assertEqual(tr("search"), DE["search"]);
    install("fr");
    testing.assertEqual(tr("search"), FR["search"]);
    install("en");
    testing.assertEqual(tr("search"), EN["search"]);
}

func testInstallTranslatesEveryKeyOfEveryLanguage() {
    for (def i in 0..len(names())) {
        install(names()[$i]);
        def catalog as map of string to string init catalogs()[$i];
        for (def key in maps.keys(EN)) {
            testing.assertEqual(tr($key), $catalog[$key]);
        }
    }
    install("en");
}

# A regional tag resolves through its base language, which is what lets a book
# declare `de-AT` and still get German chrome.
func testInstallResolvesARegionalTag() {
    install("de-AT");
    testing.assertEqual(tr("search"), DE["search"]);
    install("en");
}

# Not an error, and deliberately so: a book in a language nobody has translated
# yet gets English chrome rather than a page full of key names.
func testAnUntranslatedLanguageFallsBackToEnglish() {
    install("xx");
    testing.assertEqual(tr("search"), EN["search"]);
    install("en");
}

# `intl` returns the key itself for one it cannot find, which makes a missing
# string visible on the page instead of blank.
func testAnUnknownKeyReturnsItself() {
    install("en");
    testing.assertEqual(tr("noSuchKeyAnywhere"), "noSuchKeyAnywhere");
}
