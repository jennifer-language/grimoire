# Markdown

Grimoire renders CommonMark plus GitHub tables, task lists and strikethrough,
definition lists, marked and sub/superscript text, and attribute lists - through
the `markdown` module that ships with the interpreter, so a chapter written for
another generator needs no changes. This chapter covers all of it.

Footnotes are the one common extension that is **not** supported: `[^1]` reaches
the page as written.

Two related settings live elsewhere: [`html.rawHtml`](configuration.md#html)
decides whether a hand-written HTML block is emitted or escaped, and every
heading gets an [anchor](internals.md#anchors) matching mdBook and GitHub.

## Titles in the outline

A title in `SUMMARY.md` is **inline** Markdown: `` `code` `` and emphasis are
rendered in the sidebar and the pager, and a heading, a list or a quote is not -
a title is one line of text, not a block of them.

That matters for the outline a reference manual actually writes:

```markdown
- [7. Peripherals](peripherals.md)
```

`7. ` opens an ordered list in Markdown. Grimoire takes the title literally
instead, so the entry reads `7. Peripherals` in every place a title appears -
the sidebar, the pager, the search index, the PDF bookmarks. The same rule
applies to a title starting with `#`, `>`, `-` or a table pipe.

The one consequence worth knowing: a title taken literally is taken *entirely*
literally, so `7. A **bold** word` shows its asterisks. A title that does not
open a block keeps its Markdown, and that covers everything else, `1)` and `1.A`
included.

## Formatting

Beyond CommonMark's bold, italic and code:

| You write | You get | Element |
| --------- | ------- | ------- |
| `~~withdrawn~~` | withdrawn text, struck through and dimmed | `del` |
| `==marked==` | marked text, on the theme's own highlight | `mark` |
| `H~2~O` | a subscript | `sub` |
| `x^2^` | a superscript | `sup` |

All four reach the site, the EPUB and the printable book, because they are the
renderer's rather than a stylesheet's. `mark` borrows the palette's admonition
fill rather than the browser default, which is a fixed yellow with black text and
unreadable on a dark page.

## Lists

A task list loses its bullets and gains checkboxes:

```markdown
- [x] written
- [ ] reviewed
```

The boxes are `disabled`, because a page is not a form - a reader cannot tick one,
and a screen reader says so. An ordinary list beside a task list keeps its
bullets.

A definition list is a term and what it means, which is how a glossary or an
option reference is written:

```markdown
outline
: the order of the book, as SUMMARY.md gives it

deck
: a directory of Jennifer modules with a deck.toml
```

## Attribute lists

A heading can name its own anchor:

```markdown
## Peripherals and control desk {#tapes}
```

The name is the anchor **everywhere** - the heading, the contents list, the
search index - so a cross-reference to `#tapes` works from any page. It goes
through the same slug rule as a generated anchor (lowercased, punctuation
dropped), and it is registered like one, so a later heading that would have
produced the same slug gets `-1` rather than a duplicate id. Use it when a URL
was published once and the heading has to change.

A link or an image can take a class:

```markdown
[Download the PDF](grimoire.pdf){.gr-button}
![A wide diagram](pipeline.png){.wide}
```

**Only the class comes through.** An attribute list can carry any key, and a
renderer that passed them all on would let a chapter put an event handler on a
link. A class is styling, which is what the syntax is for; anything else a book
needs it writes as an HTML block, where `[html] rawHtml` and the author's own
judgement already apply.

## Code blocks

A fence can name the file its code came from:

````markdown
```py title="setup.py"
x = 1
```
````

The name takes the place of the language chip in the corner of the block - a file
name already says what language it is - and the language still reaches
`class="language-py"`, which is what a highlighter reads. The name is shown on
the site; the printable book draws the code without it.

## Admonitions

A blockquote opening with an alert marker becomes a callout:

```markdown
> [!NOTE]
> Useful to know, and out of the way of the sentence you were reading.
```

> [!NOTE]
> Useful to know, and out of the way of the sentence you were reading.

Five kinds - `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]` -
in any case. Everything else inside the quotation belongs to the callout: lists,
code blocks, further paragraphs. There is no configuration key for any of it.

The syntax is GitHub's and Obsidian's, so a chapter moves between tools
unchanged and a renderer that does not know it shows a plain quotation.
`:::note` and `!!! note` leave visible wreckage where they are not implemented,
the second as an indented code block.

**Labels** come from Grimoire and follow
[`book.language`](configuration.md#the-interface-language), so a German book
says *Hinweis*. A marker can carry a title instead:

```markdown
> [!WARNING] Mind the gap
> Then the body, as usual.
```

A title is the author's text: printed as written rather than in the small
capitals a standing label gets, indexed with the body, and read as plain text -
markup in it is shown rather than rendered.

**Colours** are five hues shared by all ten themes - blue, green, purple, amber,
red - as a low-alpha wash behind the panel, with the same hue on the left rule
and the label. Redefine the ten `--gr-adm-*` custom properties to change them;
[Themes](themes.md#how-a-theme-is-built) says where.

**In print** the label is set bold at the head of the quotation, which wears the
theme's blockquote tint and rule. Labels are transliterated with everything
else: *Ostrzeżenie* prints as `Ostrzezenie`, and an alphabet that is not Latin
prints as question marks. [Internals](internals.md#the-pdf) has the table.

**Not a callout:** `> [!NOTE]:`, `[!NOTES]`, and a marker in bold. The marker
has to open the quotation, spelled exactly, with nothing after it on that line
but a title.

A quotation indented under a list item is a sibling of the list rather than part
of the item, callout or not:

```markdown
- item
  > [!NOTE]
  > renders after the list, not inside it
```

## Page breaks

In print, a chapter under a part heading is demoted one level so the part
heading owns the top of the outline, and a demoted heading does not start a
page. Such a chapter asks for the break itself:

```markdown
<!-- pagebreak -->
```

An HTML comment, so the site shows nothing and only the printable build acts on
it. A chapter that opens a part needs none: the part heading has already broken
the page.
