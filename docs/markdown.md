# Markdown

Grimoire renders CommonMark plus GitHub tables, through the `markdown` module
that ships with the interpreter, so a chapter written for another generator
needs no changes. This chapter covers what Grimoire reads on top of that.

Two related settings live elsewhere: [`html.rawHtml`](configuration.md#html)
decides whether a hand-written HTML block is emitted or escaped, and every
heading gets an [anchor](internals.md#anchors) matching mdBook and GitHub.

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
