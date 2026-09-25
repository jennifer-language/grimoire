# plugins-src

Third-party plugins to bake into the container image.

It is empty in a checkout, and an image built from a bare one carries no
third-party collection at all - which `GRIMOIRE_PLUGINS` then reports rather than
failing later.

The twelve plugins that ship with Grimoire are **not** here. They live in
`plugins/`, are installed with the rest of Grimoire, and are found by name with
nothing enabled at the container level.

To carry somebody else's plugin, put its directory here before building:

```sh
git clone https://github.com/jennifer-language/grimoire-mermaid plugins-src/grimoire-mermaid
docker build -t grimoire .
```

`Dockerfile` copies whatever is here to `/opt/grimoire-plugins`, where the
entrypoint links the ones `GRIMOIRE_PLUGINS` names onto `PATH`. A plugin
directory is expected to hold its launcher at `grimoire-NAME/grimoire-NAME`, and
may carry a `NEEDS` file listing the commands it needs, which the entrypoint
checks and warns about.

Nothing here is tracked by git beyond this file.
