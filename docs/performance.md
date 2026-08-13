# Performance

The reference book here is the Jennifer language documentation: 155 chapters,
1.7 MiB of Markdown, 31,000 lines, built into 155 pages, a 1332-section search
index, and a 726-page PDF. Everything below was taken with `scripts/bench.sh` on
bare metal - an 8-core, 16-thread Ryzen 7 5800X running Arch Linux - against
Jennifer `0.24.0-dev+13`. Each figure is the fastest of three runs.

The interpreter version belongs next to the machine, because the `markdown` and
`pdf` modules are Jennifer source: between `+11` and `+13` the PDF here got 39%
faster without a line changing in Grimoire. Re-run the benchmark after an
upgrade rather than trusting a number across one.

Two things shape the numbers.

## The site scales to about 4x, not to the core count

| Jobs | Wall clock | Speedup |
| ---- | ---------: | ------: |
| `-j 1` | 31.4 s | 1.00x |
| `-j 2` | 18.5 s | 1.69x |
| `-j 4` | 11.3 s | 2.79x |
| `-j 16` | 7.0 s | 4.48x |

Total CPU barely moves as the jobs rise to the core count - 62 s at `-j 1`, 68 s
at `-j 4` - and climbs only past it, to 86 s at `-j 16`, where half the jobs are
landing on SMT siblings rather than on cores. So the limit is not CPU. It is that
chapter sizes span two orders of magnitude - 135 KiB against a 7 KiB median - and
**a chapter cannot be split**: it is one parse and one render.

The same run on a 6-core, 12-thread Ryzen 5 7600X3D gives **1.69x** at `-j 2` and
**2.78x** at `-j 4` - the same curve to two decimal places on different silicon,
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

Memory is the other axis: the site peaks at 235 MB at `-j 1` and 825 MB at
`-j 16`, because every worker holds its own chapter.

## The PDF dominates, and it is serial

Where a `grimoire pdf` of this book goes:

| Phase | Time | Where |
| ----- | ---: | ----- |
| reading and assembling the chapters | 6.7 s | Grimoire |
| parsing them | 15.7 s | the `markdown` module |
| laying out 726 pages | 16.5 s | the `markdown` module |
| writing the file | 0.2 s | the `pdf` module |

Five sixths of it is inside the modules, and single-threaded. The layout is now
the largest single phase, a shade ahead of the parse; writing the file used to be
3.6 s and is no longer worth naming.

Grimoire starts the PDF at the same time as the chapter render, so `--pdf` costs
roughly `max(site, pdf)` rather than their sum - 42.2 s against a 39.1 s PDF and
a 31.4 s site. But the PDF is the floor, and it is why more jobs do not make
`build --pdf` faster: at `-j 16` it takes 43.9 s, a second and a half *longer*
than at `-j 1`, the extra workers competing with the one task that decides when
the build ends.

The parse is done a chapter at a time and the block trees are concatenated,
rather than the whole book being parsed at once. Both produce the same tree -
they compare equal - but not the same cost: `markdown.parse` hands the whole line
list to a collector once per fenced block, quote, and list, so a document that is
a book rather than a chapter pays for that copy on every block. On a manual, with
fences everywhere, that is quadratic.

The margin narrows as the module improves, so measure before deciding rather than
assuming this is still worth doing. At `+11` the single call cost 2.25x the
chapters; at `+13` it is 1.14x here and 1.10x on the 7600X3D - 2.2 s of a 39 s
build. When the two meet, one call is the honest way to write it and the splice
comes out. Jennifer 0.30 is expected to close it outright, with a read-only
parameter borrow that removes the copy for any helper that only reads what it is
given.

That margin is small because a manual is only moderately dense in fenced code.
The cost is paid per block, so a book of tutorials pays far more: on a synthetic
corpus with a fence every twenty lines, one call over 160 chapters costs 5x what
the chapters cost separately.

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
  since the two overlap, `build --pdf` costs about 8% more and gives you both.
- **Output is deterministic** at any job count, so a build is reproducible and
  diffable regardless of how the work was split.
