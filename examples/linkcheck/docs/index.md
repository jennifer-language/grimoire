# Every Link Checked

A link to [anchors](anchors.md), and one to [a heading inside
it](anchors.md#a-heading-with-an-id). Both resolve, so this build passes.

An external link is not followed unless `external = true`:
<https://grimoire.jennifer-lang.dev/>.

The interesting case is a page that *writes about* links. This one does:
`<a href="nowhere.html">` and `href="also-missing.md"` are code spans, not
links, and the checker cuts code out before it reads anything. Without that
every page about HTML fails its own build, which is how a check ends up
switched off.
