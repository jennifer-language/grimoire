# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The client-side runtime, held as source here and written to
 * `assets/grimoire.js` at build time: the colour-mode selector, the mobile
 * navigation drawer, code-block copy buttons, the contents scroll-spy, and the
 * search dialog.
 *
 * Two deliberate constraints shape it. It has **no dependencies** - no
 * framework, no search library, no icon font, nothing fetched from a CDN - so a
 * built site is self-contained. And it never uses `fetch`, loading the search
 * index by injecting a script tag instead, so a site opened straight off the
 * filesystem over `file://` searches exactly as well as one behind a server.
 * @module assets
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */

# The runtime. Written as a raw string so the braces of the JavaScript are never
# read as Jennifer interpolation slots; that also rules out the apostrophe, which
# is why every string literal below is double-quoted.
def const RUNTIME_JS as string init '/* grimoire runtime - no dependencies, works over file:// */
(function () {
    "use strict";

    var root = document.documentElement;
    var cfg = window.grimoire || {};

    /* The words Grimoire adds to a page, translated at build time and carried in
       the settings blob. The fallback is the English original, so a page whose
       settings failed to parse still reads as a page rather than as a set of key
       names. No apostrophes in here: this whole script is a raw string, which
       ends at the first one. */
    function t(key, fallback) {
        return (cfg.t && cfg.t[key]) || fallback;
    }

    var MODE_KEY = "grimoire-mode";

    /* ---------- colour mode ---------- */

    function storedMode() {
        try {
            return localStorage.getItem(MODE_KEY) || "auto";
        } catch (e) {
            return "auto";
        }
    }

    function applyMode(mode) {
        if (mode === "auto") {
            root.removeAttribute("data-theme");
        } else {
            root.setAttribute("data-theme", mode);
        }
        var buttons = document.querySelectorAll("[data-mode]");
        for (var i = 0; i < buttons.length; i++) {
            var on = buttons[i].getAttribute("data-mode") === mode;
            buttons[i].setAttribute("aria-checked", on ? "true" : "false");
        }
        /* The highlight.js stylesheets are external, so they cannot follow the
           mode through CSS - the selector has to switch them by hand. */
        syncHighlightTheme();
    }

    function setMode(mode) {
        try {
            if (mode === "auto") {
                localStorage.removeItem(MODE_KEY);
            } else {
                localStorage.setItem(MODE_KEY, mode);
            }
        } catch (e) {
            /* a blocked storage must not break the toggle */
        }
        applyMode(mode);
    }

    function initModes() {
        var buttons = document.querySelectorAll("[data-mode]");
        for (var i = 0; i < buttons.length; i++) {
            buttons[i].addEventListener("click", function (ev) {
                setMode(ev.currentTarget.getAttribute("data-mode"));
            });
        }
        applyMode(storedMode());
    }

    /* ---------- navigation drawer ---------- */

    function initDrawer() {
        var sidebar = document.getElementById("gr-sidebar");
        var backdrop = document.getElementById("gr-backdrop");
        var button = document.getElementById("gr-menu");
        if (!sidebar || !button) {
            return;
        }
        function setOpen(open) {
            sidebar.setAttribute("data-open", open ? "true" : "false");
            button.setAttribute("aria-expanded", open ? "true" : "false");
            if (backdrop) {
                backdrop.setAttribute("data-open", open ? "true" : "false");
            }
        }
        button.addEventListener("click", function () {
            setOpen(sidebar.getAttribute("data-open") !== "true");
        });
        if (backdrop) {
            backdrop.addEventListener("click", function () {
                setOpen(false);
            });
        }
        document.addEventListener("keydown", function (ev) {
            if (ev.key === "Escape") {
                setOpen(false);
            }
        });
        var current = sidebar.querySelector("[aria-current=page]");
        if (current && current.scrollIntoView) {
            current.scrollIntoView({block: "center"});
        }
    }

    /* ---------- copy buttons ---------- */

    function initCopy() {
        var buttons = document.querySelectorAll(".gr-copy");
        for (var i = 0; i < buttons.length; i++) {
            buttons[i].addEventListener("click", function (ev) {
                var button = ev.currentTarget;
                var block = button.closest(".gr-codeblock");
                var code = block ? block.querySelector("code") : null;
                if (!code) {
                    return;
                }
                var done = function () {
                    button.setAttribute("data-copied", "true");
                    button.setAttribute("aria-label", t("copied", "Copied"));
                    setTimeout(function () {
                        button.removeAttribute("data-copied");
                        button.setAttribute("aria-label", t("copyCode", "Copy code"));
                    }, 1400);
                };
                if (navigator.clipboard && navigator.clipboard.writeText) {
                    navigator.clipboard.writeText(code.textContent).then(done, function () {});
                    return;
                }
                var area = document.createElement("textarea");
                area.value = code.textContent;
                area.setAttribute("readonly", "");
                area.style.position = "fixed";
                area.style.opacity = "0";
                document.body.appendChild(area);
                area.select();
                try {
                    document.execCommand("copy");
                    done();
                } catch (e) {
                    /* nothing else to try */
                }
                document.body.removeChild(area);
            });
        }
    }

    /* ---------- contents scroll-spy ---------- */

    function initScrollSpy() {
        var links = document.querySelectorAll(".gr-toc a");
        if (!links.length || !window.IntersectionObserver) {
            return;
        }
        var byId = {};
        var targets = [];
        for (var i = 0; i < links.length; i++) {
            var id = decodeURIComponent(links[i].getAttribute("href").slice(1));
            var heading = document.getElementById(id);
            if (heading) {
                byId[id] = links[i];
                targets.push(heading);
            }
        }
        var visible = [];
        var observer = new IntersectionObserver(function (entries) {
            for (var i = 0; i < entries.length; i++) {
                var id = entries[i].target.id;
                var at = visible.indexOf(id);
                if (entries[i].isIntersecting && at < 0) {
                    visible.push(id);
                } else if (!entries[i].isIntersecting && at >= 0) {
                    visible.splice(at, 1);
                }
            }
            var active = null;
            for (var j = 0; j < targets.length; j++) {
                if (visible.indexOf(targets[j].id) >= 0) {
                    active = targets[j].id;
                    break;
                }
            }
            for (var id2 in byId) {
                if (Object.prototype.hasOwnProperty.call(byId, id2)) {
                    if (id2 === active) {
                        byId[id2].setAttribute("aria-current", "true");
                    } else {
                        byId[id2].removeAttribute("aria-current");
                    }
                }
            }
        }, {rootMargin: "-70px 0px -70% 0px", threshold: 0});
        for (var k = 0; k < targets.length; k++) {
            observer.observe(targets[k]);
        }
    }

    /* ---------- search ---------- */

    var searchState = {loading: false, ready: false, docs: [], active: 0, results: []};

    function normalize(text) {
        return text.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    }

    function tokenize(text) {
        var parts = normalize(text).split(/[^a-z0-9_]+/);
        var out = [];
        for (var i = 0; i < parts.length; i++) {
            if (parts[i].length > 0) {
                out.push(parts[i]);
            }
        }
        return out;
    }

    function escapeHtml(text) {
        return String(text)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
    }

    /* score returns 0 when any query token is missing, so results are an AND of
       the terms rather than a bag of loosely related pages. */
    function score(entry, tokens) {
        var total = 0;
        for (var i = 0; i < tokens.length; i++) {
            var token = tokens[i];
            var hit = 0;
            if (entry.nt.indexOf(token) >= 0) {
                hit += entry.nt.indexOf(token) === 0 ? 14 : 9;
            }
            if (entry.nh.indexOf(token) >= 0) {
                hit += entry.nh.indexOf(token) === 0 ? 9 : 6;
            }
            var at = entry.nb.indexOf(token);
            if (at >= 0) {
                var count = entry.nb.split(token).length - 1;
                hit += Math.min(count, 6);
            }
            if (hit === 0) {
                return 0;
            }
            total += hit;
        }
        return total;
    }

    function snippet(body, tokens) {
        var lower = normalize(body);
        var at = -1;
        for (var i = 0; i < tokens.length; i++) {
            var found = lower.indexOf(tokens[i]);
            if (found >= 0 && (at < 0 || found < at)) {
                at = found;
            }
        }
        if (at < 0) {
            at = 0;
        }
        var start = Math.max(0, at - 70);
        var text = body.slice(start, start + 200);
        if (start > 0) {
            text = "..." + text;
        }
        if (start + 200 < body.length) {
            text = text + "...";
        }
        return highlight(text, tokens);
    }

    function highlight(text, tokens) {
        var out = escapeHtml(text);
        for (var i = 0; i < tokens.length; i++) {
            var safe = tokens[i].replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            out = out.replace(new RegExp("(" + safe + ")", "gi"), "<mark>$1</mark>");
        }
        return out;
    }

    function renderResults(query) {
        var list = document.getElementById("gr-results");
        var empty = document.getElementById("gr-empty");
        if (!list) {
            return;
        }
        var tokens = tokenize(query);
        searchState.results = [];
        if (tokens.length && searchState.ready) {
            var scored = [];
            for (var i = 0; i < searchState.docs.length; i++) {
                var value = score(searchState.docs[i], tokens);
                if (value > 0) {
                    scored.push({entry: searchState.docs[i], value: value});
                }
            }
            scored.sort(function (a, b) {
                return b.value - a.value;
            });
            searchState.results = scored.slice(0, 20);
        }
        searchState.active = 0;
        var html = "";
        for (var j = 0; j < searchState.results.length; j++) {
            var entry = searchState.results[j].entry;
            var target = cfg.root + entry.p + (entry.a ? "#" + entry.a : "");
            html += "<li data-active=\"" + (j === 0 ? "true" : "false") + "\">";
            html += "<a href=\"" + escapeHtml(target) + "\">";
            html += "<span class=\"gr-r-crumb\">" + escapeHtml(entry.t) + "</span>";
            html += "<span class=\"gr-r-title\">" +
                highlight(entry.h || entry.t, tokens) + "</span>";
            html += "<span class=\"gr-r-body\">" + snippet(entry.b, tokens) + "</span>";
            html += "</a></li>";
        }
        list.innerHTML = html;
        if (empty) {
            if (!tokens.length) {
                empty.textContent = searchState.ready
                    ? t("typeToSearch", "Type to search the book.")
                    : t("loadingIndex", "Loading the index...");
                empty.hidden = false;
            } else if (!searchState.results.length) {
                empty.textContent = t("noResults", "No results for %query%")
                    .replace("%query%", query);
                empty.hidden = false;
            } else {
                empty.hidden = true;
            }
        }
    }

    /* The index is a script tag rather than a fetch so the site keeps working
       when it is opened from disk, where fetch is blocked by the origin rules. */
    function loadIndex(then) {
        if (searchState.ready || searchState.loading) {
            if (searchState.ready && then) {
                then();
            }
            return;
        }
        searchState.loading = true;
        var tag = document.createElement("script");
        tag.src = cfg.root + "assets/search-index.js";
        tag.onload = function () {
            var raw = (window.grimoireIndex || {}).docs || [];
            for (var i = 0; i < raw.length; i++) {
                searchState.docs.push({
                    p: raw[i][0],
                    t: raw[i][1],
                    h: raw[i][2],
                    a: raw[i][3],
                    b: raw[i][4],
                    nt: normalize(raw[i][1]),
                    nh: normalize(raw[i][2]),
                    nb: normalize(raw[i][4])
                });
            }
            searchState.ready = true;
            searchState.loading = false;
            if (then) {
                then();
            }
        };
        tag.onerror = function () {
            searchState.loading = false;
        };
        document.head.appendChild(tag);
    }

    function moveActive(step) {
        var items = document.querySelectorAll("#gr-results li");
        if (!items.length) {
            return;
        }
        items[searchState.active].setAttribute("data-active", "false");
        searchState.active = (searchState.active + step + items.length) % items.length;
        var item = items[searchState.active];
        item.setAttribute("data-active", "true");
        if (item.scrollIntoView) {
            item.scrollIntoView({block: "nearest"});
        }
    }

    function initSearch() {
        var dialog = document.getElementById("gr-search");
        var input = document.getElementById("gr-search-input");
        var opener = document.getElementById("gr-search-open");
        if (!dialog || !input) {
            return;
        }
        function open() {
            dialog.hidden = false;
            input.focus();
            input.select();
            loadIndex(function () {
                renderResults(input.value);
            });
            renderResults(input.value);
        }
        function close() {
            dialog.hidden = true;
        }
        if (opener) {
            opener.addEventListener("click", open);
        }
        dialog.addEventListener("click", function (ev) {
            if (ev.target === dialog) {
                close();
            }
        });
        input.addEventListener("input", function () {
            renderResults(input.value);
        });
        input.addEventListener("keydown", function (ev) {
            if (ev.key === "ArrowDown") {
                ev.preventDefault();
                moveActive(1);
            } else if (ev.key === "ArrowUp") {
                ev.preventDefault();
                moveActive(-1);
            } else if (ev.key === "Enter") {
                var link = document.querySelector("#gr-results li[data-active=true] a");
                if (link) {
                    ev.preventDefault();
                    window.location.href = link.getAttribute("href");
                }
            }
        });
        document.addEventListener("keydown", function (ev) {
            if (ev.key === "Escape" && !dialog.hidden) {
                close();
                return;
            }
            var typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName) ||
                document.activeElement.isContentEditable;
            if (typing) {
                return;
            }
            if (ev.key === "/" || ((ev.metaKey || ev.ctrlKey) && ev.key.toLowerCase() === "k")) {
                ev.preventDefault();
                open();
            }
        });
        /* Warm the index once the page is idle, so the first search is instant. */
        if (window.requestIdleCallback) {
            window.requestIdleCallback(function () {
                loadIndex(null);
            });
        }
    }

    /* ---------- syntax highlighting ---------- */

    /* highlight.js comes from the CDN named in grimoire.toml, and the Jennifer
       grammar - which no CDN ships - is served from the site itself. The two
       stylesheets are both linked and toggled by `disabled`, because an external
       stylesheet cannot be scoped to a data-theme attribute from the outside. */

    var hlLinks = {light: null, dark: null};

    function loadScript(src, then) {
        var tag = document.createElement("script");
        tag.src = src;
        tag.onload = then;
        tag.onerror = then;
        document.head.appendChild(tag);
    }

    function loadStyle(href, id) {
        var link = document.createElement("link");
        link.rel = "stylesheet";
        link.id = id;
        link.href = href;
        document.head.appendChild(link);
        return link;
    }

    function darkActive() {
        var attr = root.getAttribute("data-theme");
        if (attr) {
            return attr === "dark";
        }
        return !!(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches);
    }

    function syncHighlightTheme() {
        if (!hlLinks.light || !hlLinks.dark) {
            return;
        }
        var dark = darkActive();
        hlLinks.light.disabled = dark;
        hlLinks.dark.disabled = !dark;
    }

    function initHighlight() {
        if (!cfg.hlCdn) {
            return;
        }
        var base = cfg.hlCdn.replace(/\/+$/, "");
        hlLinks.light = loadStyle(base + "/styles/" + cfg.hlStyle + ".min.css", "gr-hl-light");
        hlLinks.dark = loadStyle(base + "/styles/" + cfg.hlStyleDark + ".min.css", "gr-hl-dark");
        syncHighlightTheme();
        if (window.matchMedia) {
            var query = window.matchMedia("(prefers-color-scheme: dark)");
            if (query.addEventListener) {
                query.addEventListener("change", syncHighlightTheme);
            }
        }
        loadScript(base + "/highlight.min.js", function () {
            if (typeof hljs === "undefined") {
                return;
            }
            /* The extra language packs are independent of one another, so a pack
               that 404s must not stop the rest - each one settles on its own and
               the last to finish starts the highlight pass. */
            var langs = cfg.hlLangs || [];
            var pending = langs.length + 1;
            var done = function () {
                pending -= 1;
                if (pending > 0) {
                    return;
                }
                /* `:not(.hljs)` skips what the build already highlighted -
                   Jennifer blocks are painted server-side, so repainting them
                   here would be work the reader waits for and never sees. */
                var blocks = document.querySelectorAll(".gr-codeblock pre code:not(.hljs)");
                for (var i = 0; i < blocks.length; i++) {
                    hljs.highlightElement(blocks[i]);
                }
            };
            for (var j = 0; j < langs.length; j++) {
                loadScript(base + "/languages/" + langs[j] + ".min.js", done);
            }
            loadScript(cfg.root + "assets/hljs-jennifer.js", done);
        });
    }

    function start() {
        initModes();
        initDrawer();
        initCopy();
        initScrollSpy();
        initHighlight();
        if (cfg.search) {
            initSearch();
        }
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", start);
    } else {
        start();
    }
})();
';

/**
 * The client-side runtime, for `assets/grimoire.js`.
 * @return {string} the JavaScript source
 */
export func runtime() {
    return RUNTIME_JS;
}

/**
 * The tiny script that goes inline in the document head, before any content is
 * painted: it reads the stored colour mode and stamps it on the root element, so
 * a reader who chose dark never sees a white flash on navigation. It falls back
 * to `deflt`, the book default from `grimoire.toml`.
 * @param deflt {string} the configured default mode: "auto", "light", or "dark"
 * @return {string} the JavaScript source
 */
export func boot(deflt as string) {
    def fallback as string init $deflt;
    if ($fallback != "light" and $fallback != "dark") {
        $fallback = "auto";
    }
    return '(function(){try{var m=localStorage.getItem("grimoire-mode")||"' + $fallback +
        '";if(m==="light"||m==="dark"){document.documentElement.setAttribute("data-theme",m);}}' +
        'catch(e){}})();';
}
