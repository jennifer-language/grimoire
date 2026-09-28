#!/bin/sh
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
#
# Everything the build needs is in the repository.
#
#   scripts/check-tracked.sh
#
# A file that exists here and is not tracked works perfectly until somebody else
# checks the repository out - and the first somebody else is CI, which clones and
# then cannot find it:
#
#   scripts/ci-git-image.sh: No such file or directory
#   Error: Process completed with exit code 127
#
# That is a green working copy and a red pipeline, and the gap between them is one
# forgotten `git add`. This closes it before a push rather than after.
#
# Three rules. Anything a workflow, the `Dockerfile` or the PKGBUILD names by path
# has to be tracked; everything under `plugins/` and `examples/` has to be tracked
# - those are the directories a new plugin arrives in, file by file; and a script
# a workflow runs directly has to be tracked **executable**, because a clone gets
# the mode git recorded and not the one on this disk.

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "not a git checkout; nothing to check" >&2
    exit 0
fi

fail=0

report() {
    echo "FAIL  $1 is not tracked" >&2
    printf '      %s\n' "$2" >&2
    fail=1
}

# What the pipeline and the packaging name by path.
named=$(grep -ohE '(scripts|packaging|plugins-src)/[A-Za-z0-9_./-]+\.(sh|j|md)' \
    .github/workflows/*.yml Dockerfile packaging/arch/PKGBUILD 2>/dev/null | sort -u)
for file in $named; do
    [ -e "$file" ] || continue
    if ! git ls-files --error-unmatch "$file" > /dev/null 2>&1; then
        report "$file" "a workflow or the packaging runs it; run: git add $file"
        continue
    fi
    # A `run:` step invokes a script by path, so the recorded mode is what
    # decides whether the clone can execute it.
    case "$file" in
        *.sh)
            case "$(git ls-files -s "$file" | cut -d' ' -f1)" in
                100755) ;;
                *)
                    echo "FAIL  $file is tracked without its execute bit" >&2
                    printf '      %s\n' "run: chmod +x $file && git add $file" >&2
                    fail=1
                    ;;
            esac
            ;;
    esac
done

# The directories a plugin arrives in.
for file in $(git status --porcelain --untracked-files=all plugins examples 2>/dev/null |
        sed -n 's/^?? //p'); do
    report "$file" "a plugin or its example is incomplete without it; run: git add $file"
done

if [ "$fail" -eq 0 ]; then
    echo "every file the build needs is tracked"
fi
exit "$fail"
