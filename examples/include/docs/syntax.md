# The syntax

Three forms, and a backslash to show them:

```markdown
\{{#include examples/hello.j}}          the whole file
\{{#include examples/hello.j:3:12}}     lines 3 to 12, inclusive
\{{#include examples/hello.j:5}}        line 5 onwards
```

Lines count from 1, the way an editor counts, and a range includes both ends.

The directive has to stand alone on its line - one inside a sentence, like
\{{#include examples/hello.j}} here, is prose about the syntax and is left
alone. A backslash in front of one prints it instead of following it, which is
how both of the blocks above are written.

Paths are relative to the book's source directory, and one that climbs out of it
with `..` is refused: a book is a directory. Directives are resolved once, so an
included file's own directives are left as they are.
