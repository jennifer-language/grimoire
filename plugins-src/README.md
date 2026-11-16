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
git clone https://github.com/you/grimoire-NAME plugins-src/grimoire-NAME
docker build -t grimoire .
```

`Dockerfile` copies whatever is here to `/opt/grimoire-plugins`, where the
entrypoint links the ones `GRIMOIRE_PLUGINS` names onto `PATH`. A plugin
directory holds its launcher at `grimoire-NAME/grimoire-NAME`, or at
`grimoire-NAME/bin/grimoire-NAME` as a Jennifer app laid out for
`jvc app install` does, so such a repository can be cloned here as it is. It may
carry a `NEEDS` file listing the commands it needs, which the entrypoint checks
and warns about; the image does not install them.

A Jennifer plugin with `[decks]` needs its `vendor/` filled before the build
(`jvc install` inside its directory), because the image runs no jvc.

Nothing here is tracked by git beyond this file.
