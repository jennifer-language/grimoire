# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for `assets.j`, run by `jennifer test src/assets_test.j`.
 *
 * The runtime is JavaScript held in a Jennifer string, so nothing here can
 * execute it. What a test *can* do is hold it to the two constraints the module
 * exists to keep - no dependency of any kind, and no `fetch` for the search
 * index so a site opened over `file://` searches as well as one behind a server -
 * and to the raw-string rule that makes it possible to hold it at all: a single
 * apostrophe anywhere in that literal silently truncates the whole runtime.
 *
 * That last one is the case worth having. The build would still succeed, the
 * file would still be written, and the site would simply stop working.
 * @module assets_test
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use testing;
use strings;

# --- the runtime is intact -------------------------------------------

# A raw string ends at the first apostrophe, with no escape available. One
# slipped into a comment inside the runtime would truncate it at that point and
# the build would carry on quite happily.
func testTheRuntimeIsNotTruncated() {
    def js as string init runtime();
    testing.assertFalse(strings.contains($js, "'"));
    testing.assertTrue(strings.startsWith($js, "/* grimoire runtime"));
    testing.assertTrue(strings.endsWith(strings.trim($js), '})();'));
}

func testTheRuntimeCarriesEveryFeature() {
    def js as string init runtime();
    testing.assertContains($js, "function initModes");
    testing.assertContains($js, "function initDrawer");
    testing.assertContains($js, "function initCopy");
    testing.assertContains($js, "function initScrollSpy");
}

# No framework, no search library, no icon font, nothing from a CDN: a built site
# is self-contained, and `packaging/arch/README.md` claims as much.
func testTheRuntimeHasNoDependencies() {
    def js as string init runtime();
    testing.assertFalse(strings.contains($js, "cdn."));
    testing.assertFalse(strings.contains($js, "https://"));
    testing.assertFalse(strings.contains($js, "import "));
    testing.assertFalse(strings.contains($js, "require("));
}

# The index is loaded by injecting a script tag rather than fetched, which is the
# whole reason search works on a book opened straight off a disk.
func testTheRuntimeNeverFetchesTheIndex() {
    def js as string init runtime();
    testing.assertFalse(strings.contains($js, "fetch("));
    testing.assertFalse(strings.contains($js, "XMLHttpRequest"));
    testing.assertContains($js, "createElement");
}

# The fallback is the English original, so a page whose settings blob failed to
# parse still reads as a page rather than as a list of key names.
func testTheRuntimeFallsBackToEnglish() {
    def js as string init runtime();
    testing.assertContains($js, "function t(key, fallback)");
    testing.assertContains($js, "Copied");
}

func testTheRuntimeIsStrict() {
    testing.assertContains(runtime(), '"use strict"');
}

func testRuntimeIsStable() {
    testing.assertEqual(runtime(), runtime());
}

# --- boot ------------------------------------------------------------

func testBootCarriesTheConfiguredDefault() {
    testing.assertContains(boot("dark"), '||"dark"');
    testing.assertContains(boot("light"), '||"light"');
}

# An unrecognised mode is not an error here - it has already been clamped in the
# configuration - but this is the last line of defence before it reaches a page.
func testBootClampsAnUnknownMode() {
    testing.assertContains(boot("auto"), '||"auto"');
    testing.assertContains(boot("chartreuse"), '||"auto"');
    testing.assertContains(boot(""), '||"auto"');
}

# It runs before the first paint and must never be the thing that stops a page
# rendering, so a blocked localStorage has to be survivable.
func testBootSurvivesBlockedStorage() {
    testing.assertContains(boot("auto"), "try");
    testing.assertContains(boot("auto"), 'catch(e)');
}

func testBootStampsTheRootElement() {
    def js as string init boot("dark");
    testing.assertContains($js, "document.documentElement.setAttribute");
    testing.assertContains($js, "data-theme");
}

# Only an explicit choice is stamped; "auto" leaves the element alone so the
# media query in the stylesheet decides.
func testBootStampsOnlyAnExplicitMode() {
    testing.assertContains(boot("auto"), 'm==="light"||m==="dark"');
}

# --- liveReload ------------------------------------------------------

func testLiveReloadPollsTheGivenEndpoint() {
    def js as string init liveReload("/__grimoire_build", 700);
    testing.assertContains($js, '"/__grimoire_build"');
    testing.assertContains($js, "700");
    testing.assertContains($js, "setInterval");
}

func testLiveReloadDoesNotCache() {
    testing.assertContains(liveReload("/x", 500), 'cache:"no-store"');
}

# The first answer is only recorded, never acted on, so opening a page never
# reloads it - which would otherwise be an infinite loop.
func testLiveReloadIgnoresTheFirstAnswer() {
    def js as string init liveReload("/x", 500);
    testing.assertContains($js, 'if(last===null){last=v;return;}');
}

# A failed request is ignored: the server is being restarted, or the build is
# mid-write. A reload loop on a transient error would be worse than no reload.
func testLiveReloadSwallowsAFailedRequest() {
    testing.assertContains(liveReload("/x", 500), '.catch(function(){});');
}

func testLiveReloadReloadsOnAChangedToken() {
    testing.assertContains(liveReload("/x", 500), 'if(v!==last){location.reload();}');
}

# It is injected into a page rather than written to disk, so it has to be one
# expression with no stray newline that could break the surrounding markup.
func testLiveReloadIsASingleLine() {
    testing.assertEqual(len(strings.split(liveReload("/x", 500), "\n")), 1);
}

# --- every emitted asset is ASCII ------------------------------------

# These land in files that declare no encoding, and the repository rule is ASCII
# punctuation everywhere. The grep in `CLAUDE.md` reads the `.j` source, which
# catches this too - but only while the strings stay literal.
func testEveryEmittedAssetIsAscii() {
    def sources as list of string init [runtime(), boot("auto"), liveReload("/x", 500)];
    for (def js in $sources) {
        for (def ch in strings.chars($js)) {
            testing.assertTrue(convert.toCodepoint($ch) < 128);
        }
    }
}
