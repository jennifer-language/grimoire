#!/bin/sh
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
#
# Measure Grimoire building a book, on the machine it is run on, and write the
# whole run to one file that can be carried somewhere else and read.
#
#   scripts/bench.sh ~/src/jennifer                  # the full matrix
#   scripts/bench.sh --quick ~/src/jennifer          # a first look
#   scripts/bench.sh -r 5 -j "1 2 4 8 16" ~/src/x    # a scaling study
#
# Nothing is written inside the book: every build goes to a temporary directory,
# which is removed at the end. The result file is the only thing left behind.
#
# What is measured, and why each case is here:
#
#   startup     `grimoire --version`. Grimoire is Jennifer source run by the
#               interpreter, so every other number below carries one parse of
#               it; this is that constant, to be subtracted.
#   site-plain  a site build with the search index off - the renderer alone.
#   site-jN     a site build at each --jobs setting, which is the scaling curve.
#   pdf         `grimoire pdf`: the outline, one parse of the whole book, the
#               layout, and the file. No HTML, no assets, no search index.
#   full-jN     `grimoire build --pdf`, which is what a release does.
#   modules     scripts/bench-md.j: markdown.parse, markdown.renderPdfDoc and
#               pdf.render over the same corpus with no Grimoire around them, so
#               that a change in the libraries can be told from one in the tool.
#
# Every case is repeated, and every repetition is recorded rather than averaged
# here - the analysis wants the spread, and the minimum of several runs is a
# better estimate of the machine than the mean of runs that shared it with a
# browser.
#
# Requires: a Jennifer interpreter and the book's grimoire.toml. GNU time is
# used when present, for peak memory and CPU utilisation; without it the run
# still produces wall clock.

set -eu

BENCH_VERSION=1

# How much of each profile table to keep. It is sorted by cumulative time, so
# this is the top of the call chain plus the expensive leaves under it.
PROFILE_ROWS=40

root=$(cd "$(dirname "$0")/.." && pwd)

JENNIFER=${JENNIFER:-jennifer}
GRIMOIRE=${GRIMOIRE:-$root/bin/grimoire}
SYSMODDIR=${SYSMODDIR:-}

reps=3
jobs=""
out=""
with_pdf=1
with_md=1
with_profile=1
md_skip=""
quick=0

usage() {
    cat <<'EOF'
usage: bench.sh [options] <book-directory>

  -o FILE        where to write the result (default: ./grimoire-bench-HOST-STAMP.txt)
  -r N           repetitions per case (default 3)
  -j "1 2 4"     the --jobs settings to sweep (default: 1, 2, 4 and one per CPU)
  --md-skip a,b  paths the module benchmark leaves out, as pdf.exclude does
  --no-pdf       skip the PDF cases
  --no-md        skip the module benchmark
  --no-profile   skip the profiler pass
  --quick        one repetition, two job settings, no module benchmark, no profile
  -h             this

environment:
  JENNIFER   the interpreter (default: jennifer)
  GRIMOIRE   the launcher (default: the one beside this script)
  SYSMODDIR  run everything through "$JENNIFER run --sysmoddir=DIR", for a
             Jennifer checkout whose modules are not the installed ones
EOF
}

while [ $# -gt 0 ]; do
    case $1 in
        -o) out=$2; shift 2 ;;
        -r) reps=$2; shift 2 ;;
        -j) jobs=$2; shift 2 ;;
        --md-skip) md_skip=$2; shift 2 ;;
        --no-pdf) with_pdf=0; shift ;;
        --no-md) with_md=0; shift ;;
        --no-profile) with_profile=0; shift ;;
        --quick) quick=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "bench.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
        *) break ;;
    esac
done

if [ $# -lt 1 ]; then
    usage >&2
    exit 2
fi

book=$(cd "$1" && pwd)
if [ ! -f "$book/grimoire.toml" ]; then
    echo "bench.sh: no grimoire.toml in $book" >&2
    exit 1
fi

ncpu=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

if [ "$quick" = 1 ]; then
    reps=1
    with_md=0
    with_profile=0
    [ -n "$jobs" ] || jobs="1 $ncpu"
fi
if [ -z "$jobs" ]; then
    # 1 for the serial baseline, one per CPU for the best case, and the powers
    # of two in between for the shape of the curve.
    jobs=$(printf '1\n2\n4\n%s\n' "$ncpu" | sort -n -u |
        awk -v n="$ncpu" '$1 <= n' | tr '\n' ' ')
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
host=$(hostname 2>/dev/null || echo unknown)
[ -n "$out" ] || out="$PWD/grimoire-bench-$host-$stamp.txt"

work=$(mktemp -d "${TMPDIR:-/tmp}/grimoire-bench.XXXXXX")
cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM

# Grimoire and the module benchmark are invoked through two generated wrappers
# rather than through shell functions, because the timer below is a program and
# cannot run a function. This is also the one place that knows about SYSMODDIR:
# a Jennifer checkout runs the modules built from itself, which is the whole
# point of measuring a development build.
if [ -n "$SYSMODDIR" ]; then
    cat >"$work/grim" <<EOF
#!/bin/sh
exec "$JENNIFER" run "--sysmoddir=$SYSMODDIR" "$GRIMOIRE" "\$@"
EOF
    cat >"$work/jenn" <<EOF
#!/bin/sh
exec "$JENNIFER" run "--sysmoddir=$SYSMODDIR" "\$@"
EOF
    cat >"$work/prof" <<EOF
#!/bin/sh
exec "$JENNIFER" profile "--sysmoddir=$SYSMODDIR" "$GRIMOIRE" "\$@"
EOF
else
    # Through the interpreter rather than through the launcher's own shebang,
    # which would pick whichever `jennifer` is on PATH and quietly measure a
    # different build from the one recorded in the file.
    cat >"$work/grim" <<EOF
#!/bin/sh
exec "$JENNIFER" run "$GRIMOIRE" "\$@"
EOF
    cat >"$work/jenn" <<EOF
#!/bin/sh
exec "$JENNIFER" run "\$@"
EOF
    cat >"$work/prof" <<EOF
#!/bin/sh
exec "$JENNIFER" profile "$GRIMOIRE" "\$@"
EOF
fi
chmod +x "$work/grim" "$work/jenn" "$work/prof"

# GNU time gives peak RSS and CPU utilisation, which is what turns a --jobs
# sweep into a parallel-efficiency figure. Its absence is not fatal.
gnutime=""
if [ -x /usr/bin/time ] && /usr/bin/time -f %e true >/dev/null 2>&1; then
    gnutime=/usr/bin/time
fi

# Nanosecond date is the fallback clock, and is not everywhere (macOS prints a
# literal N). Checked once rather than per run.
nanos=0
case $(date +%s%N 2>/dev/null) in
    *[!0-9]*|"") nanos=0 ;;
    *) nanos=1 ;;
esac

emit() { printf '%s\n' "$*" >>"$out"; }
meta() { printf 'meta\t%s\t%s\n' "$1" "$2" >>"$out"; }
say() { printf '%s\n' "$*" >&2; }

# --- what this machine is -------------------------------------------

: >"$out"
emit "# grimoire benchmark v$BENCH_VERSION"
emit "# Tab-separated records. scripts/bench.sh says what each case measures."
emit "# meta      key value"
emit "# run       case jobs rep wall_ms user_ms sys_ms cpu_pct maxrss_kb reported_ms exit"
emit "# size      case files kib pdf_bytes"
emit "# log/err   case line (the command's own output, first repetition only)"
emit "# prof      case rank hits self_us cum_us position"
emit "# mdcorpus  key value"
emit "# md        rep phase value (times in us, over the whole corpus)"
emit "# mdslow    rank parse_us bytes path"

meta generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
meta bench.version "$BENCH_VERSION"
meta host "$host"
meta kernel "$(uname -sr 2>/dev/null || echo unknown)"
meta arch "$(uname -m 2>/dev/null || echo unknown)"
if [ -r /etc/os-release ]; then
    meta os "$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
fi
meta cpu.count "$ncpu"
if [ -r /proc/cpuinfo ]; then
    meta cpu.model "$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)"
    meta cpu.mhz "$(awk -F': ' '/cpu MHz/ {printf "%.0f", $2; exit}' /proc/cpuinfo)"
fi
if [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    meta cpu.governor "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
fi
if [ -r /proc/meminfo ]; then
    meta mem.total_kb "$(awk '/MemTotal/ {print $2; exit}' /proc/meminfo)"
fi
meta load.before "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo unknown)"
meta fs.work "$(stat -f -c %T "$work" 2>/dev/null || echo unknown)"
meta fs.book "$(stat -f -c %T "$book" 2>/dev/null || echo unknown)"
meta timer "${gnutime:-date}"

meta jennifer.path "$(command -v "$JENNIFER" 2>/dev/null || echo "$JENNIFER")"
meta jennifer.version "$("$JENNIFER" --version 2>&1 | head -1)"
meta jennifer.sysmoddir "${SYSMODDIR:-installed}"
meta grimoire.dir "$root"
meta grimoire.commit "$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git -C "$root" status --porcelain 2>/dev/null || true)" ]; then
    meta grimoire.tree dirty
else
    meta grimoire.tree clean
fi
meta book.dir "$book"
meta book.commit "$(git -C "$book" rev-parse --short HEAD 2>/dev/null || echo unknown)"

src=$(awk -F'"' '/^[[:space:]]*src[[:space:]]*=/ {print $2; exit}' "$book/grimoire.toml")
[ -n "$src" ] || src=docs
meta book.src "$src"
meta book.md.files "$(find "$book/$src" -name '*.md' -type f | wc -l | tr -d ' ')"
meta book.md.bytes "$(find "$book/$src" -name '*.md' -type f -exec cat {} + | wc -c | tr -d ' ')"
meta bench.reps "$reps"
meta bench.jobs "$jobs"

# A copy of the book's configuration with the PDF switched off, for the site
# cases. Grimoire has a `--pdf` flag but no `--no-pdf`, so a book whose
# grimoire.toml turns the PDF on would otherwise render one in every case and
# there would be no site-only measurement at all. Everything else is untouched,
# and the paths in it stay relative to the book, which is where each build runs.
awk '
    /^[[:space:]]*\[/ { sect = $0; gsub(/[][ \t]/, "", sect) }
    sect == "pdf" && /^[[:space:]]*enabled[[:space:]]*=/ { print "enabled = false"; next }
    { print }
' "$book/grimoire.toml" >"$work/site.toml"
book_pdf=$(awk -F'=' '
    /^[[:space:]]*\[/ { sect = $0; gsub(/[][ \t]/, "", sect) }
    sect == "pdf" && /^[[:space:]]*enabled[[:space:]]*=/ { gsub(/[ \t]/, "", $2); print $2 }
' "$book/grimoire.toml" | tail -1)
meta book.pdf.configured "${book_pdf:-absent}"

# The chapters the book keeps out of its PDF. Handed to the module benchmark so
# that its PDF covers what `grimoire pdf` covers; a one-line array only, which
# is how the key is written in practice.
book_exclude=$(awk -F'"' '
    /^[[:space:]]*\[/ { sect = $0; gsub(/[][ \t]/, "", sect) }
    sect == "pdf" && /^[[:space:]]*exclude[[:space:]]*=/ {
        for (i = 2; i < NF; i += 2) { printf "%s%s", (n++ ? "," : ""), $i }
    }
' "$book/grimoire.toml")
[ -n "$md_skip" ] || md_skip=$book_exclude
meta book.pdf.exclude "${md_skip:-none}"

# --- one measured run -----------------------------------------------

# measure <case> <jobs> <rep> <command...>
#
# Writes one `run` record: wall clock, user and system time, CPU utilisation,
# peak RSS, whatever the command reported about itself, and its exit status. The
# command's own output is kept for the first repetition of each case, because a
# page count that changed between two runs invalidates the comparison and
# nothing else would show it.
measure() {
    case_name=$1
    case_jobs=$2
    case_rep=$3
    shift 3

    wall=""; user=""; sys=""; cpu=""; rss=""; status=0
    if [ -n "$gnutime" ]; then
        set +e
        "$gnutime" -f '%e %U %S %P %M' -o "$work/time" -- "$@" \
            >"$work/stdout" 2>"$work/stderr"
        status=$?
        set -e
        # The last line, not the first: a command that exits non-zero makes GNU
        # time print a note above its format string.
        t_line=$(tail -1 "$work/time")
        wall=$(printf '%s' "$t_line" | awk '{printf "%d", $1 * 1000}')
        user=$(printf '%s' "$t_line" | awk '{printf "%d", $2 * 1000}')
        sys=$(printf '%s' "$t_line" | awk '{printf "%d", $3 * 1000}')
        cpu=$(printf '%s' "$t_line" | awk '{gsub(/%/, "", $4); print $4}')
        rss=$(printf '%s' "$t_line" | awk '{print $5}')
    elif [ "$nanos" = 1 ]; then
        start=$(date +%s%N)
        set +e
        "$@" >"$work/stdout" 2>"$work/stderr"
        status=$?
        set -e
        wall=$((($(date +%s%N) - start) / 1000000))
    else
        start=$(date +%s)
        set +e
        "$@" >"$work/stdout" 2>"$work/stderr"
        status=$?
        set -e
        wall=$((($(date +%s) - start) * 1000))
    fi

    # "built 41 pages into out/ (2.1 MiB, 12 assets) in 8213 ms" - the tool's
    # own figure, which excludes interpreter start-up and argument parsing.
    reported=$(sed -n 's/^.* in \([0-9][0-9]*\) ms$/\1/p' "$work/stdout" | tail -1)

    printf 'run\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$case_name" "$case_jobs" "$case_rep" \
        "$wall" "$user" "$sys" "$cpu" "$rss" "$reported" "$status" >>"$out"

    if [ "$case_rep" = 1 ]; then
        while IFS= read -r line; do
            printf 'log\t%s\t%s\n' "$case_name" "$line" >>"$out"
        done <"$work/stdout"
        while IFS= read -r line; do
            printf 'err\t%s\t%s\n' "$case_name" "$line" >>"$out"
        done <"$work/stderr"
    fi

    if [ "$status" != 0 ]; then
        say "  ! $case_name exited $status (recorded; see the err records)"
    fi
}

# sizes records what a case produced, so that a build that got faster by doing
# less is visible rather than flattering.
sizes() {
    [ -d "$2" ] || return 0
    printf 'size\t%s\t%s\t%s\t%s\n' "$1" \
        "$(find "$2" -type f | wc -l | tr -d ' ')" \
        "$(du -sk "$2" | cut -f1)" \
        "$(find "$2" -name '*.pdf' -type f -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')" \
        >>"$out"
}

# profile_case <case> <command...>
#
# The one measurement that says where the time goes rather than how much there
# is: `jennifer profile` reports wall clock per source position, so a slow build
# is attributed to a line of markdown.j or pdf.j rather than to "the PDF". The
# instrumented run is a little slower than the real one and is deliberately not
# timed - the `run` records above are the timings.
#
# Only the top of the table is kept. It is sorted by cumulative time, so the
# first rows are the call chain down to whatever is actually expensive, and
# everything past that is noise at this scale.
profile_case() {
    case_name=$1
    shift
    say "profiling $case_name"
    set +e
    (cd "$book" && "$work/prof" "$@" >"$work/prof.txt" 2>"$work/prof.err")
    prof_status=$?
    set -e
    if [ "$prof_status" != 0 ]; then
        say "  ! the profiler exited $prof_status"
        printf 'err\tprofile-%s\texit %s\n' "$case_name" "$prof_status" >>"$out"
        return 0
    fi
    awk -v c="$case_name" -v top="$PROFILE_ROWS" '
        # "1.796708062s", "4.784833ms", "7.05?s" - one number and a unit, in
        # microseconds. The unit is read off the original and stripped as
        # "everything at the end that is not part of a number", because the
        # microsecond one is spelled with a character this file may not contain.
        function us(v, n) {
            n = v
            sub(/[^0-9.]+$/, "", n)
            if (v ~ /ms$/) { return n * 1000 }
            if (v ~ /ns$/) { return n / 1000 }
            if (v ~ /^[0-9.]+s$/) { return n * 1000000 }
            return n + 0
        }
        $1 ~ /^[0-9]+$/ && NF >= 4 {
            rank++
            if (rank > top) { exit }
            printf "prof\t%s\t%d\t%d\t%d\t%d\t%s\n", c, rank, $1, us($2), us($3), $4
        }
    ' "$work/prof.txt" >>"$out"
}

# run_case <case> <jobs> <outdir|-> <command...>
#
# Repeats one case, emptying its output directory between repetitions so that
# every run does the same work rather than the second one finding the first
# one's files in place.
run_case() {
    case_name=$1
    case_jobs=$2
    case_dir=$3
    shift 3
    rep=1
    while [ "$rep" -le "$reps" ]; do
        if [ "$case_dir" != "-" ]; then
            rm -rf "$case_dir"
        fi
        say "  $case_name rep $rep/$reps"
        (cd "$book" && measure "$case_name" "$case_jobs" "$rep" "$@")
        rep=$((rep + 1))
    done
    [ "$case_dir" = "-" ] || sizes "$case_name" "$case_dir"
}

# --- the matrix ------------------------------------------------------

say "grimoire benchmark: $book"
say "  jennifer: $("$JENNIFER" --version 2>&1 | head -1)"
say "  cpus: $ncpu   reps: $reps   jobs: $jobs"
say "  writing $out"

say "warming up"
warm_start=$(date +%s)
if ! (cd "$book" && "$work/grim" build --out "$work/warmup" --quiet >/dev/null 2>&1); then
    say "bench.sh: the warm-up build failed - running it again with its output shown"
    (cd "$book" && "$work/grim" build --out "$work/warmup") || true
    say "bench.sh: giving up; fix the build before measuring it"
    exit 1
fi
warm=$(($(date +%s) - warm_start))
rm -rf "$work/warmup"

# What is left to do, in units of the build that has just been timed. Not a
# prediction - the PDF cases and the profiler are slower than a plain build, and
# the parallel ones faster - but enough to tell a five-minute run from an hour.
runs=$((reps * (2 + $(printf '%s\n' $jobs | wc -l))))
[ "$with_pdf" = 0 ] || runs=$((runs + reps * 3))
meta warmup.seconds "$warm"
say "  a full build takes about ${warm}s here; $runs timed runs follow"

say "startup"
run_case startup 0 - "$work/grim" --version

say "site, search index off"
run_case site-plain 1 "$work/out-plain" \
    "$work/grim" build -c "$work/site.toml" --out "$work/out-plain" -j 1 --no-search

for j in $jobs; do
    say "site, $j job(s)"
    run_case "site-j$j" "$j" "$work/out-site" \
        "$work/grim" build -c "$work/site.toml" --out "$work/out-site" -j "$j"
done

if [ "$with_pdf" = 1 ]; then
    say "pdf only"
    run_case pdf 0 "$work/out-pdf" "$work/grim" pdf --out "$work/out-pdf"

    # Serial and one per CPU; the same list on a single-core machine.
    for j in $(printf '1\n%s\n' "$ncpu" | sort -n -u); do
        say "site and pdf, $j job(s)"
        run_case "full-j$j" "$j" "$work/out-full" \
            "$work/grim" build --pdf --out "$work/out-full" -j "$j"
    done
fi

if [ "$with_profile" = 1 ]; then
    profile_case site \
        build -c "$work/site.toml" --out "$work/out-prof" -j 1
    if [ "$with_pdf" = 1 ]; then
        profile_case pdf pdf --out "$work/out-prof"
    fi
    rm -rf "$work/out-prof"
fi

if [ "$with_md" = 1 ] && [ -f "$root/scripts/bench-md.j" ]; then
    say "markdown and pdf modules, no grimoire around them"
    set -- "$book/$src" "$reps"
    [ "$with_pdf" = 1 ] || set -- "$@" nopdf
    [ -z "$md_skip" ] || set -- "$@" "skip=$md_skip"
    set +e
    (cd "$book" && "$work/jenn" "$root/scripts/bench-md.j" "$@") \
        >>"$out" 2>"$work/mderr"
    md_status=$?
    set -e
    if [ "$md_status" != 0 ]; then
        say "  ! the module benchmark exited $md_status"
        while IFS= read -r line; do
            printf 'err\tmodules\t%s\n' "$line" >>"$out"
        done <"$work/mderr"
    fi
fi

meta load.after "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo unknown)"
meta finished "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

say ""
say "done: $out"
