# Performance

Measured on a 155-chapter, 2.3 MiB book (the official Jennifer 0.24.0
documentation), on an 8-core Ryzen 7 5800X. The wall-clock figures are from bare
metal; the phase split below was measured in a VM on the same part, so read that
as proportions rather than absolutes.

| | wall clock |
| - | - |
| site, `-j 1` | ~47 s |
| site, `-j 16` | ~12 s |
| site + PDF | ~118 s |

Two things shape those numbers.

## The site scales to roughly 4x, not 8x

Total CPU stays flat as jobs rise, so the limit is not CPU. It is that chapter
sizes span two orders of magnitude - 135 KiB against a 7 KiB median - and **a
chapter cannot be split**: it is one parse and one render.

Work is handed out heaviest-first, each chapter going to whichever worker is
least loaded at that moment. That is the greedy longest-processing-time rule,
and on this book it does noticeably better than the obvious alternatives:

| Split | Busiest worker, `-j 8` | `-j 16` |
| ----- | ---------------------: | ------: |
| round-robin over the outline | 336 KiB | 195 KiB |
| heaviest-first, least-loaded | 211 KiB | 135 KiB |

At `-j 8` that is an exactly even split - 211 KiB is the total divided by eight,
so no arrangement does better. At `-j 16` it is the size of the single largest
chapter, which is the floor by definition. Past that, more jobs cannot help; the
one 135 KiB chapter decides when the build ends.

Sorting first was tried and is *worse* at high job counts, which is the
counter-intuitive part: it packs the small chapters neatly but leaves nothing
left to balance the big ones against.

## The PDF dominates, and it is serial

Where the ~2 minutes go:

| Phase | Time | Where |
| ----- | ---: | ----- |
| assembling the combined Markdown | 5.5 s | Grimoire |
| parsing it | 38.6 s | the `markdown` module |
| laying out 506 pages | 79.7 s | the `markdown` module |

95% of it is inside the module, and single-threaded. Grimoire starts the PDF at
the same time as the chapter render, so `--pdf` costs roughly
`max(site, pdf)` rather than their sum - but the PDF is the floor. Getting under
it means fixing the module, not Grimoire.

Re-derive the split at any time with the profiler:

```sh
jennifer profile ./grimoire pdf --src <your-book> --out /tmp/pdfout
```

## Practical notes

- **`--jobs 0`** (the default) is one task per CPU and is almost always the right
  answer. Raising it past the point above buys nothing; lowering it to `1` is
  useful for reading `--verbose` output in outline order.
- **`--no-search`** saves very little. Indexing rides along with the render that
  has already parsed the chapter.
- **`grimoire pdf`** skips the site entirely when the PDF is all you want, but
  since the two overlap, `build --pdf` costs about the same and gives you both.
- **Output is deterministic** at any job count, so a build is reproducible and
  diffable regardless of how the work was split.
