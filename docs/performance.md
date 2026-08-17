# Performance

The reference book here is the Jennifer language documentation: 155 chapters,
1.7 MiB of Markdown, built into 155 pages, a 1335-section search index, and a
727-page PDF. Everything below was taken with `scripts/bench.sh` on bare metal -
an 8-core, 16-thread Ryzen 7 5800X running Arch Linux - against Jennifer
`0.24.0-dev+15`. Each figure is the fastest of three runs.

The interpreter version belongs next to the machine, because the `markdown` and
`pdf` modules are Jennifer source and the language underneath them is moving
fast. Two upgrades in a day took the site build here from 31.4 s to 21.5 s
without a line changing in Grimoire. Re-run the benchmark after an upgrade
rather than trusting a number across one.

The larger of the two is worth naming, because it changes the advice as well as
the numbers. `0.24.0-dev+15` added a **read-only parameter borrow**: a parameter
a function never writes is now passed rather than copied, in any module and in a
script that declares no mutable top-level `def`. Jennifer's parameters are
values, so before this a helper that only read a large list or map still paid a
deep copy of it on every call, and the standard way to make a Jennifer program
fast was to arrange not to hand large values to helpers. That is now a smaller
concern than it was - see `CLAUDE.md` for what survives it.

Two things shape the numbers.

## The site scales to about 4.5x, not to the core count

| Jobs | Wall clock | Speedup |
| ---- | ---------: | ------: |
| `-j 1` | 21.5 s | 1.00x |
| `-j 2` | 12.2 s | 1.76x |
| `-j 4` | 7.3 s | 2.94x |
| `-j 16` | 4.7 s | 4.56x |

Total CPU barely moves as the jobs rise to the core count - 35 s at `-j 1`, 39 s
at `-j 4` - and climbs only past it, to 54 s at `-j 16`, where half the jobs are
landing on SMT siblings rather than on cores. So the limit is not CPU. It is that
chapter sizes span two orders of magnitude - 135 KiB against a 7 KiB median - and
**a chapter cannot be split**: it is one parse and one render.

The same run on a 6-core, 12-thread Ryzen 5 7600X3D gives 1.82x at `-j 2` and
3.01x at `-j 4` - within a few percent of the curve above, on different silicon,
with a different core count and a different clock. The shape belongs to the book,
not to the machine.

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

Memory is the other axis: the site peaks at 169 MB at `-j 1` and 464 MB at
`-j 16`, because every worker holds its own chapter.

## The PDF dominates, and it is serial

Where a `grimoire pdf` of this book goes:

| Phase | Time | Where |
| ----- | ---: | ----- |
| reading and assembling the chapters | 5.7 s | Grimoire |
| parsing the assembled book | 14.6 s | the `markdown` module |
| laying out 727 pages | 15.2 s | the `markdown` module |
| writing the file | 0.2 s | the `pdf` module |

Six sevenths of it is inside the modules, and single-threaded. The parse and the
layout are now the same size to within a rounding error; writing the file used to
be 3.6 s and is no longer worth naming.

Grimoire starts the PDF at the same time as the chapter render, so `--pdf` costs
roughly `max(site, pdf)` rather than their sum - 37.9 s against a 35.7 s PDF and
a 21.5 s site. But the PDF is the floor, and it is why more jobs do not make
`build --pdf` faster: at `-j 16` it takes 39.2 s, over a second *longer* than at
`-j 1`, the extra workers competing with the one task that decides when the build
ends.

The parse is one call over the whole assembled book. It was one call per chapter
until recently, with the block trees concatenated onto a single root - the same
tree, and for a long time a much cheaper one, because `markdown.parse` handed the
whole line list to a collector once per fenced block, quote, and list, so a
book-sized document paid for that copy on every block. That was worth 2.25x at
its worst and 1.14x as late as `+13`.

The read-only borrow removed the copy, and the workaround came out with it. One
call is what the code always wanted to be, and it lowers the peak as well: the
spliced version held every chapter's blocks while a fresh chapter tree was being
built beside them.

The PDF holds the whole book as one document, and is where a build reaches its
memory high-water mark - 1.6 GB on a book this size, growing with it.

Re-derive the split at any time with the profiler:

```sh
jennifer profile bin/grimoire pdf --src <your-book> --out /tmp/pdfout
```

## What these numbers do not include

Two changes landed after the run they come from, and both make a build faster or
smaller than the tables say.

**The `src/highlight.j` rewrite** removed a per-character helper call - and with
it a per-character copy of the code block - from the build-time syntax
highlighter. On an interpreter old enough to lack the borrow that was worth about
a third of the site build; on `+15` the borrow has already collected most of it,
and how much is left is unmeasured. Any book that uses `[highlight]` is affected.

**Dropping the chapter-at-a-time PDF parse** for a single call, described above.
The PDF times were measured with the old shape, so the split between the first
two rows of the phase table is the new one and the total is the old one; expect
them to disagree slightly until the next run. Peak memory should fall too, and
the 1.6 GB figure is the spliced version's.

That is the general shape of the caveat rather than an exception to it: a
benchmark file is a measurement of one commit against one interpreter, and both
move.

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
  since the two overlap, `build --pdf` costs about 6% more and gives you both.
- **Output is deterministic** at any job count, so a build is reproducible and
  diffable regardless of how the work was split.
