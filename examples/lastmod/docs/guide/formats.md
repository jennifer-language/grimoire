# Formats

`format` is a strftime layout, handed to git as it is written:

| | |
| - | - |
| `%Y-%m-%d` | 2026-03-01 |
| `%d.%m.%Y` | 01.03.2026 |
| `%d %B %Y` | the month spelled out, in the machine's language |

The last one is worth avoiding in a book that has to build identically
everywhere: a month name is whatever the locale calls it, and two runners can
disagree.
