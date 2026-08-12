# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * The words Grimoire itself puts on a page, in English and ten other languages.
 *
 * A book's own text is the author's; these are the few strings the engine adds
 * around it - "Search", "On this page", the colour-mode buttons, the keyboard
 * hints in the search dialog, the copy-code button. There are twenty-two of
 * them, and until now they were English wherever the book was not.
 *
 * `intl` holds the catalogs and the current locale as library state, and that
 * state is **per module**: a `use intl` in two files is two catalogs, and the one
 * that never called `intl.load` translates nothing. So every lookup in Grimoire
 * goes through `tr` here rather than through a `use intl` of its own - this
 * module is the only place that touches the library, which is what makes
 * `install` being called once enough.
 *
 * The state *is* shared across `spawn`ed tasks, which matters just as much:
 * chapters render in parallel workers, and every one of them translates its own
 * chrome from the catalogs the main task loaded.
 *
 * **This file is the one place in the repository that is not ASCII**, and has to
 * be - a translation of "Search" into Russian is Cyrillic or it is not a
 * translation.
 * Nothing here reaches the PDF: the printed book has no chrome, only the
 * author's own text and the two configurable strings around it.
 *
 * A missing language is not an error. `intl` falls back to the first catalog
 * loaded - English, below - so a book in a language nobody has translated yet
 * gets English chrome rather than a page full of key names.
 * @module locale
 * @author mplx <jennifer@mplx.dev>
 * @license LGPL-3.0-only
 */
use intl;
use lists;
use strings;

# The languages, in the order they load. English is first because `intl` treats
# the first catalog as the default, which is the last stop before a key is
# printed raw.
def const LANGUAGES as list of string init [
    "en",
    "de",
    "es",
    "fr",
    "it",
    "ja",
    "nl",
    "pl",
    "pt",
    "ru",
    "zh"
];

# `%query%` is the only placeholder in any of these, and it is the search term
# the reader typed. The marker is `intl`'s rather than Jennifer's `{}`, so these
# read the same in a cooked or a raw string.
def const EN as map of string to string init {
    "bookContents": "Book contents",
    "chapterNav": "Chapter navigation",
    "colourMode": "Colour mode",
    "copied": "Copied",
    "copyCode": "Copy code",
    "dark": "Dark",
    "editPage": "Edit this page",
    "light": "Light",
    "loadingIndex": "Loading the index...",
    "matchSystem": "Match the system",
    "next": "Next",
    "noResults": "No results for %query%",
    "onThisPage": "On this page",
    "previous": "Previous",
    "search": "Search",
    "searchBook": "Search the book",
    "skipToContent": "Skip to content",
    "toClose": "to close",
    "toMove": "to move",
    "toOpen": "to open",
    "toggleNav": "Toggle navigation",
    "typeToSearch": "Type to search the book."
};

def const DE as map of string to string init {
    "bookContents": "Inhalt des Buchs",
    "chapterNav": "Kapitelnavigation",
    "colourMode": "Farbmodus",
    "copied": "Kopiert",
    "copyCode": "Code kopieren",
    "dark": "Dunkel",
    "editPage": "Diese Seite bearbeiten",
    "light": "Hell",
    "loadingIndex": "Index wird geladen...",
    "matchSystem": "Systemeinstellung folgen",
    "next": "Weiter",
    "noResults": "Keine Ergebnisse für %query%",
    "onThisPage": "Auf dieser Seite",
    "previous": "Zurück",
    "search": "Suchen",
    "searchBook": "Buch durchsuchen",
    "skipToContent": "Zum Inhalt springen",
    "toClose": "zum Schließen",
    "toMove": "zum Navigieren",
    "toOpen": "zum Öffnen",
    "toggleNav": "Navigation umschalten",
    "typeToSearch": "Zum Suchen tippen."
};

def const ES as map of string to string init {
    "bookContents": "Contenido del libro",
    "chapterNav": "Navegación por capítulos",
    "colourMode": "Modo de color",
    "copied": "Copiado",
    "copyCode": "Copiar código",
    "dark": "Oscuro",
    "editPage": "Editar esta página",
    "light": "Claro",
    "loadingIndex": "Cargando el índice...",
    "matchSystem": "Seguir el sistema",
    "next": "Siguiente",
    "noResults": "Sin resultados para %query%",
    "onThisPage": "En esta página",
    "previous": "Anterior",
    "search": "Buscar",
    "searchBook": "Buscar en el libro",
    "skipToContent": "Saltar al contenido",
    "toClose": "para cerrar",
    "toMove": "para moverse",
    "toOpen": "para abrir",
    "toggleNav": "Mostrar la navegación",
    "typeToSearch": "Escribe para buscar en el libro."
};

def const FR as map of string to string init {
    "bookContents": "Contenu du livre",
    "chapterNav": "Navigation entre chapitres",
    "colourMode": "Mode de couleur",
    "copied": "Copié",
    "copyCode": "Copier le code",
    "dark": "Sombre",
    "editPage": "Modifier cette page",
    "light": "Clair",
    "loadingIndex": "Chargement de l'index...",
    "matchSystem": "Suivre le système",
    "next": "Suivant",
    "noResults": "Aucun résultat pour %query%",
    "onThisPage": "Sur cette page",
    "previous": "Précédent",
    "search": "Rechercher",
    "searchBook": "Rechercher dans le livre",
    "skipToContent": "Aller au contenu",
    "toClose": "pour fermer",
    "toMove": "pour naviguer",
    "toOpen": "pour ouvrir",
    "toggleNav": "Afficher la navigation",
    "typeToSearch": "Saisissez votre recherche."
};

def const IT as map of string to string init {
    "bookContents": "Contenuto del libro",
    "chapterNav": "Navigazione tra capitoli",
    "colourMode": "Modalità colore",
    "copied": "Copiato",
    "copyCode": "Copia il codice",
    "dark": "Scuro",
    "editPage": "Modifica questa pagina",
    "light": "Chiaro",
    "loadingIndex": "Caricamento dell'indice...",
    "matchSystem": "Segui il sistema",
    "next": "Successivo",
    "noResults": "Nessun risultato per %query%",
    "onThisPage": "In questa pagina",
    "previous": "Precedente",
    "search": "Cerca",
    "searchBook": "Cerca nel libro",
    "skipToContent": "Vai al contenuto",
    "toClose": "per chiudere",
    "toMove": "per spostarsi",
    "toOpen": "per aprire",
    "toggleNav": "Mostra la navigazione",
    "typeToSearch": "Digita per cercare nel libro."
};

# The keyboard hints read as one line after their key caps, so the Japanese
# entries carry the particle that joins them: "arrow arrow で移動".
def const JA as map of string to string init {
    "bookContents": "本の目次",
    "chapterNav": "章のナビゲーション",
    "colourMode": "カラーモード",
    "copied": "コピーしました",
    "copyCode": "コードをコピー",
    "dark": "ダーク",
    "editPage": "このページを編集",
    "light": "ライト",
    "loadingIndex": "インデックスを読み込み中...",
    "matchSystem": "システムに合わせる",
    "next": "次へ",
    "noResults": "%query% に一致する結果はありません",
    "onThisPage": "このページの内容",
    "previous": "前へ",
    "search": "検索",
    "searchBook": "本を検索",
    "skipToContent": "本文へスキップ",
    "toClose": "で閉じる",
    "toMove": "で移動",
    "toOpen": "で開く",
    "toggleNav": "ナビゲーションの切り替え",
    "typeToSearch": "入力して本を検索します。"
};

def const NL as map of string to string init {
    "bookContents": "Inhoud van het boek",
    "chapterNav": "Hoofdstuknavigatie",
    "colourMode": "Kleurmodus",
    "copied": "Gekopieerd",
    "copyCode": "Code kopiëren",
    "dark": "Donker",
    "editPage": "Deze pagina bewerken",
    "light": "Licht",
    "loadingIndex": "Index wordt geladen...",
    "matchSystem": "Systeeminstelling volgen",
    "next": "Volgende",
    "noResults": "Geen resultaten voor %query%",
    "onThisPage": "Op deze pagina",
    "previous": "Vorige",
    "search": "Zoeken",
    "searchBook": "Zoeken in het boek",
    "skipToContent": "Naar de inhoud",
    "toClose": "om te sluiten",
    "toMove": "om te navigeren",
    "toOpen": "om te openen",
    "toggleNav": "Navigatie tonen",
    "typeToSearch": "Typ om in het boek te zoeken."
};

def const PL as map of string to string init {
    "bookContents": "Spis treści",
    "chapterNav": "Nawigacja po rozdziałach",
    "colourMode": "Tryb kolorów",
    "copied": "Skopiowano",
    "copyCode": "Kopiuj kod",
    "dark": "Ciemny",
    "editPage": "Edytuj tę stronę",
    "light": "Jasny",
    "loadingIndex": "Wczytywanie indeksu...",
    "matchSystem": "Zgodnie z systemem",
    "next": "Następny",
    "noResults": "Brak wyników dla %query%",
    "onThisPage": "Na tej stronie",
    "previous": "Poprzedni",
    "search": "Szukaj",
    "searchBook": "Szukaj w książce",
    "skipToContent": "Przejdź do treści",
    "toClose": "aby zamknąć",
    "toMove": "aby przejść",
    "toOpen": "aby otworzyć",
    "toggleNav": "Przełącz nawigację",
    "typeToSearch": "Zacznij pisać, aby wyszukać."
};

def const PT as map of string to string init {
    "bookContents": "Conteúdo do livro",
    "chapterNav": "Navegação entre capítulos",
    "colourMode": "Modo de cor",
    "copied": "Copiado",
    "copyCode": "Copiar código",
    "dark": "Escuro",
    "editPage": "Editar esta página",
    "light": "Claro",
    "loadingIndex": "Carregando o índice...",
    "matchSystem": "Seguir o sistema",
    "next": "Próximo",
    "noResults": "Nenhum resultado para %query%",
    "onThisPage": "Nesta página",
    "previous": "Anterior",
    "search": "Pesquisar",
    "searchBook": "Pesquisar no livro",
    "skipToContent": "Ir para o conteúdo",
    "toClose": "para fechar",
    "toMove": "para navegar",
    "toOpen": "para abrir",
    "toggleNav": "Alternar navegação",
    "typeToSearch": "Digite para pesquisar no livro."
};

def const RU as map of string to string init {
    "bookContents": "Содержание книги",
    "chapterNav": "Навигация по главам",
    "colourMode": "Цветовая тема",
    "copied": "Скопировано",
    "copyCode": "Копировать код",
    "dark": "Тёмная",
    "editPage": "Редактировать страницу",
    "light": "Светлая",
    "loadingIndex": "Загрузка индекса...",
    "matchSystem": "Как в системе",
    "next": "Вперёд",
    "noResults": "Ничего не найдено по запросу %query%",
    "onThisPage": "На этой странице",
    "previous": "Назад",
    "search": "Поиск",
    "searchBook": "Поиск по книге",
    "skipToContent": "Перейти к содержимому",
    "toClose": "чтобы закрыть",
    "toMove": "для перехода",
    "toOpen": "чтобы открыть",
    "toggleNav": "Показать навигацию",
    "typeToSearch": "Введите запрос для поиска по книге."
};

def const ZH as map of string to string init {
    "bookContents": "本书目录",
    "chapterNav": "章节导航",
    "colourMode": "颜色模式",
    "copied": "已复制",
    "copyCode": "复制代码",
    "dark": "深色",
    "editPage": "编辑此页",
    "light": "浅色",
    "loadingIndex": "正在加载索引...",
    "matchSystem": "跟随系统",
    "next": "下一页",
    "noResults": "没有找到 %query% 的结果",
    "onThisPage": "本页目录",
    "previous": "上一页",
    "search": "搜索",
    "searchBook": "在本书中搜索",
    "skipToContent": "跳到主要内容",
    "toClose": "关闭",
    "toMove": "移动",
    "toOpen": "打开",
    "toggleNav": "切换导航",
    "typeToSearch": "输入以在本书中搜索。"
};

# base strips the region from a language tag, so `de-AT` is recognised as German.
# `intl` does the same thing when it resolves a key; this is here so that the
# command line can tell a supported language from a typo.
func base(lang as string) {
    def at as int init strings.indexOf($lang, "-");
    if ($at < 0) {
        return strings.lower($lang);
    }
    return strings.lower(strings.substring($lang, 0, $at));
}

/**
 * The languages Grimoire's own strings are translated into, English first.
 * @return {list of string} the language tags
 */
export func names() {
    return LANGUAGES;
}

/**
 * Whether a language tag is one Grimoire has its own strings in. A tag with a
 * region counts if its base language does, so `pt-BR` is Portuguese.
 * @param lang {string} the language tag from the configuration
 * @return {bool} whether a catalog will be found
 */
export func has(lang as string) {
    return lists.contains(LANGUAGES, base($lang));
}

/**
 * Load every catalog and select one. Called once, while the configuration is
 * being resolved, before anything renders.
 *
 * An unknown tag is not rejected here - `intl` falls back to English on a key it
 * cannot find, which is the right outcome for a book in an untranslated
 * language. `has` is what the command line uses to say so out loud.
 * @param lang {string} the language tag to render the interface in
 * @return {null}
 */
export func install(lang as string) {
    intl.load("en", EN);
    intl.load("de", DE);
    intl.load("es", ES);
    intl.load("fr", FR);
    intl.load("it", IT);
    intl.load("ja", JA);
    intl.load("nl", NL);
    intl.load("pl", PL);
    intl.load("pt", PT);
    intl.load("ru", RU);
    intl.load("zh", ZH);
    intl.setLocale($lang);
}

/**
 * One of Grimoire's own strings in the selected language.
 *
 * Callers use this rather than `intl.tr` directly: the catalogs live in this
 * module, and a `use intl` elsewhere would look into an empty one. An unknown
 * key returns itself, which is `intl`'s way of making a missing string visible
 * rather than blank.
 * @param key {string} the catalog key
 * @return {string} the translated string
 */
export func tr(key as string) {
    return intl.tr($key);
}
