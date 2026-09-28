# SPDX-License-Identifier: LGPL-3.0-only
use io;

# The whole of this file is on the first page of the demo, and lines 6 to 8 are
# on it a second time.
func greet(name as string) {
    io.printf("hello, %s\n", $name);
}

greet("world");
