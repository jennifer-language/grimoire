# Performance

The reference book here is the Jennifer language documentation: 155 chapters,
1.7 MiB of Markdown, 31,000 lines, built into 155 pages, a 1332-section search
index, and a 726-page PDF. Everything below was taken with `scripts/bench.sh` on
bare metal - an 8-core, 16-thread Ryzen 7 5800X running Arch Linux.

Two things shape the numbers.

## The site scales to roughly 4x, not 8x

Sixteen jobs render this book 4.3x faster than one. Total CPU barely moves as the
jobs rise to the core count - it climbs only past that, where the extra jobs are
landing on SMT siblings rather than on cores - so the limit is not CPU. It is
that chapter sizes span two orders of magnitude - 135 KiB against a 7 KiB median
- and **a chapter cannot be split**: it is one parse and one render.

Work is handed out heaviest-first, each chapter going to whichever worker is
least loaded at that moment. That is the greedy longest-processing-time rule,
and on this book it does noticeably better than the obvious alternatives:

| Split | Busiest worker, `-j 8` | `-j 16` |
| ----- | ---------------------: | ------: |
| round-robin over the outline | 337 KiB | 195 KiB |
| heaviest-first, least-loaded | 213 KiB | 135 KiB |

At `-j 8` that is an exactly even split - 213 KiB is the total divided by eight,
so no arrangement does better. At `-j 16` it is the size of the single largest
chapter, which is the floor by definition. Past that, more jobs cannot help; the
one 135 KiB chapter decides when the build ends.

Sorting first was tried and is *worse* at high job counts, which is the
counter-intuitive part: it packs the small chapters neatly but leaves nothing
left to balance the big ones against.

Memory is the other axis: the site peaks at 226 MB at `-j 1` and 763 MB at
`-j 16`, because every worker holds its own chapter.

## The PDF dominates, and it is serial

Where a `grimoire pdf` of this book goes:

| Phase | Time | Where |
| ----- | ---: | ----- |
| reading and assembling the chapters | 8 s | Grimoire |
| parsing them | 16.7 s | the `markdown` module |
| laying out 726 pages | 16.7 s | the `markdown` module |
| writing the file | 3.6 s | the `pdf` module |

Five sixths of it is inside the modules, and single-threaded. Grimoire starts the
PDF at the same time as the chapter render, so `--pdf` costs roughly
`max(site, pdf)` rather than their sum - but the PDF is the floor, and it is why
more jobs do not make `build --pdf` faster. The extra workers only compete with
the one task that decides when the build ends.

The parse is done a chapter at a time and the block trees are concatenated,
rather than the whole book being parsed at once. Both produce the same tree -
they compare equal - but `markdown.parse` costs time quadratic in the length of
what it is given, and on this book one call over the whole text costs 35.4 s
where the same text in chapters costs 16.7 s. That is a workaround, not a design:
if the module goes linear, one call is the honest way to write it.

The PDF also holds the whole book as one document, and is where a build reaches
its memory high-water mark - gigabytes on a book this size, growing with it.

Re-derive the split at any time with the profiler:

```sh
jennifer profile ./grimoire pdf --src <your-book> --out /tmp/pdfout
```

## Taking these numbers on your own machine

`scripts/bench.sh` runs the whole matrix - startup, the site at each `--jobs`
setting, the PDF alone, both together, a profiler pass, and the `markdown` and
`pdf` modules on their own - and writes one tab-separated file:

```sh
scripts/bench.sh ~/src/your-book          # the full matrix, tens of minutes
scripts/bench.sh --quick ~/src/your-book  # one repetition, two job settings
```

Nothing is written inside the book; every build goes to a temporary directory.
The file records the machine as well as the timings, because a wall-clock figure
without the CPU, the filesystem, and the interpreter version beside it cannot be
compared with anything - and a figure from a virtual machine cannot be compared
with one from the metal under it at all.

## Practical notes

- **`--jobs 0`** (the default) is one task per CPU and is almost always the right
  answer. Raising it past the point above buys nothing; lowering it to `1` is
  useful for reading `--verbose` output in outline order.
- **`--no-search`** saves nothing measurable. Indexing rides along with the
  render that has already parsed the chapter.
- **`grimoire pdf`** skips the site entirely when the PDF is all you want, but
  since the two overlap, `build --pdf` costs little more and gives you both.
- **Output is deterministic** at any job count, so a build is reproducible and
  diffable regardless of how the work was split.
