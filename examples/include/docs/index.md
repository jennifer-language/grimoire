# Quoted, Not Copied

The whole file, fenced as Jennifer so it is highlighted like any other code
block:

```jennifer
{{#include examples/hello.j}}
```

And three lines out of the middle of it, which is what a chapter wants when the
imports are not the point:

```jennifer
{{#include examples/hello.j:6:8}}
```

A snippet pasted into a chapter is wrong the day the code changes and nobody
notices until a reader tries it. A file read at build time is either right or a
failed build.
