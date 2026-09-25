# What is available

Three sources, looked up in this order:

| | |
| - | - |
| the book | `\{{ book.title }}` is *{{ book.title }}*, and `\{{ book.language }}` is {{ book.language }} |
| the table | anything under `[preprocessor.macros.vars]`, like `\{{ version }}` for {{ version }} |
| the environment | `\{{ env.NAME }}`, for the names the book allows in `env` |

A name with nothing behind it stops the build and says which chapter asked for
it, because a placeholder that reaches a reader is worse than a build that
stopped. Set `strict = false` if a book writes braces for some other reason.

Every cell in the left column above is written with a backslash in front of it -
`\{{ version }}` - which is how a page shows the syntax instead of using it.
Inside a fence no escape is needed:

```toml
[preprocessor.macros.vars]
version = "{{ version }}"
```
