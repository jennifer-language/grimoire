#!/bin/sh
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
#
# The shape every plugin in `plugins/` has to have, checked rather than
# described. Each assertion says what it looked at and what to do about it: a
# bare `test` under `set -e` fails with no output at all, which turns a one-line
# problem into a round trip through the logs.
#
#   scripts/check-plugins.sh
#
# A plugin is a launcher, the module beside it, and an overlay for that module.
# The launcher is what Grimoire executes, the module is where the work is, and
# the overlay is the only way to test it: `jennifer test` splices a `_test.j`
# into the module it names, so a plugin written as one script cannot be tested
# at all.

set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

fail=0

check() {
    if eval "$2"; then
        echo "ok    $1"
    else
        echo "FAIL  $1"
        printf '      %s\n' "$3"
        fail=1
    fi
}

for launcher in plugins/grimoire-*; do
    name=${launcher#plugins/grimoire-}

    check "$name: the launcher is executable" \
        "[ -x $launcher ]" \
        "git tracks the mode; run: chmod +x $launcher && git add $launcher"
    check "$name: the launcher is a Jennifer program" \
        "head -1 $launcher | grep -q '^#!.*jennifer'" \
        "the launcher lost its shebang"

    # `grimoire-include` predates the split and is one file. It is the last
    # exemption, and nothing else is exempt.
    case "$name" in
        include) continue;;
    esac

    check "$name: the launcher imports its module" \
        "grep -q '^import \"\./$name\.j\"' $launcher" \
        "the launcher is a launcher: import ./$name.j and exit its run()"
    check "$name: the launcher only exits" \
        "grep -q '^exit ' $launcher" \
        "the status comes from the module's run(), through exit in the launcher"
    check "$name: $name.j is a module" \
        "[ -f plugins/$name.j ] && ! head -1 plugins/$name.j | grep -q '^#!'" \
        "a module is imported, never executed: the shebang belongs on the launcher"
    check "$name: the module has an entry point" \
        "grep -q '^export func run(' plugins/$name.j" \
        "run(request) returns a status; exit inside a module takes the test runner with it"
    check "$name: the module is tested" \
        "[ -s plugins/${name}_test.j ]" \
        "a white-box overlay beside the module: scripts/test.sh $name"
    check "$name: an example book" \
        "[ -s examples/$name/grimoire.toml ]" \
        "a book small enough to read in one screen, which CI builds"
    check "$name: the example names no command" \
        "! grep -q '^command = ' examples/$name/grimoire.toml" \
        "a shipped plugin is found beside Grimoire; the example should show that"
done

exit "$fail"
