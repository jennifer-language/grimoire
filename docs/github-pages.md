# Publishing on GitHub Pages

Grimoire ships a reusable GitHub Actions workflow,
`.github/workflows/docs-pages.yml`, that builds a book and publishes it to
GitHub Pages. Any repository whose documentation is a Grimoire book can call it;
Grimoire's own manual - this one - is published by it.

The repository needs no Jennifer and no Grimoire of its own. The book is built
inside the Grimoire container image, so the runner needs only Docker, which
GitHub's `ubuntu-latest` runners have.

## What gets published

The site is built from the **latest release**, not from the tip of the default
branch. A reader who installs your newest release then reads the documentation
of that release, and not of options merged since.

- **A release is a tag in plain semver**: `MAJOR.MINOR.PATCH`, with no leading
  `v` and no pre-release suffix. `1.2.0` is a release; `v1.2.0`, `1.3.0-rc.1`
  and `latest` are ignored.
- **The highest release wins**, compared number by number: `0.10.0` outranks
  `0.9.3`, and a patch pushed to an older line - `1.1.4` after `1.2.0` - does not
  take the site back to 1.1.
- **The book is built as it stood at that tag**: its `grimoire.toml`, its
  chapters, everything. A documentation fix merged to the default branch reaches
  the site with the next release, or under `/dev/` if you
  [publish the default branch too](#unreleased-documentation-under-dev).
- **Until the first release, the default branch is published instead**, so a
  project has a site before it has a version. The first release tag takes the
  root over from then on.
- **A pull request is built and checked but never published**, so a book that
  stops building fails the pull request rather than the next release.

## Step by step

### 1. Have a book that builds

Somewhere in the repository there is a `grimoire.toml` - at the root, or in a
directory of its own - and `grimoire build` succeeds there. Build it once on your
own machine first; a [container](installation.md#in-a-container) is enough if
you have no Jennifer installed. The `out` setting does not matter: the workflow
always builds into a directory of its own.

### 2. Add the workflow

Create `.github/workflows/docs.yml`:

```yaml
name: docs

on:
  push:
    tags: ["[0-9]+.[0-9]+.[0-9]+"]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  pages:
    permissions:
      contents: read
      pages: write
      id-token: write
    uses: jennifer-language/grimoire/.github/workflows/docs-pages.yml@0.4.0
    with:
      image: ghcr.io/jennifer-language/grimoire:0.4.0
```

`0.4.0` is a Grimoire release: use the newest one, in both places. 0.4.0 is the
first release that carries `docs-pages.yml`, so it is the oldest that `uses`
can name. [Pinning](#pinning) says why both lines name a version rather than
`main` and `latest`.

The `permissions` block on the job is required. A called workflow can narrow
the permissions it is given but never widen them, and deploying to Pages needs
`pages: write` and `id-token: write`.

### 3. Change two repository settings

Once per repository, before the first release is published. Both need admin
rights on the repository, and neither can be done by the workflow itself.

1. **Settings, Pages:** set the source to *GitHub Actions*.
2. **Settings, Environments, `github-pages`:** allow deployments from tags.
   GitHub usually creates this environment with the default branch as its only
   deployment branch, so a deployment started by a release tag is refused -
   after the book has built, at the very last step. Under *Deployment branches
   and tags*, add a rule of type *Tag* with the pattern `[0-9]*.[0-9]*.[0-9]*`.

The same two settings with the [GitHub CLI](https://cli.github.com/), with
`OWNER/REPOSITORY` replaced:

```sh
repo=repos/OWNER/REPOSITORY

# Pages, built by GitHub Actions. -X PUT instead, if Pages is on already.
gh api -X POST $repo/pages -f build_type=workflow

# The environment, deploying from the default branch - before the first
# release - and from release tags.
gh api -X PUT $repo/environments/github-pages \
    -F 'deployment_branch_policy[protected_branches]=false' \
    -F 'deployment_branch_policy[custom_branch_policies]=true'
gh api -X POST $repo/environments/github-pages/deployment-branch-policies \
    -f name=main -f type=branch
gh api -X POST $repo/environments/github-pages/deployment-branch-policies \
    -f name='[0-9]*.[0-9]*.[0-9]*' -f type=tag
```

The environment commands are safe to repeat: the `PUT` creates the environment
or leaves it as it is, and a rule that exists already is not added twice. Use
your default branch's name if it is not `main`. To check:

```sh
gh api $repo/environments/github-pages/deployment-branch-policies \
    --jq '.branch_policies[] | .type + " " + .name'
```

which lists `branch main` and `tag [0-9]*.[0-9]*.[0-9]*`.

### 4. Publish

Push a release tag:

```sh
git tag 1.0.0
git push origin 1.0.0
```

The tag push starts the workflow. Its *deploy* job links the published site when
it finishes, and the Pages settings show the address from then on.

**No release yet?** Click *Run workflow* on the workflow's Actions page instead.
With no plain-semver tag in the repository, the default branch is built and
published at the root, and the run's summary says so. To republish on every
merge until the first release, add `branches: [main]` under `push` for now - and
take it out again afterwards, or each merge republishes the same release.

That is all there is to it. Every release tag you push from now on republishes
the site from the highest release. *Run workflow* on the workflow's Actions page
republishes it without a new tag - after changing a setting, say, or after a
Pages outage.

## The address

A repository's site is published at `https://OWNER.github.io/REPOSITORY/`. A
Grimoire site works from a subdirectory as it is, so there is nothing to
configure for that.

For a **custom domain**, put a file called `CNAME` into the book's source
directory, holding the domain and nothing else:

```
docs.example.org
```

and set the same domain under Settings, Pages. Grimoire copies the file into the
site like any other non-Markdown file. It has to be in the site, not only in the
settings: a deployment from a workflow publishes exactly what the build
produced, so a site without the file loses the domain on its next deployment.

A [`sitemap`](plugins.md) renderer needs the address as its `baseUrl`. Set it to
the published address, custom or not.

## Inputs

| Input | Default | |
| ----- | ------- | - |
| `image` | `grimoire:latest` | the container the book is built in; pin it |
| `directory` | `.` | the directory holding `grimoire.toml`, relative to the repository root |
| `args` | `""` | extra flags for `grimoire build`, such as `--pdf` |
| `plugins` | `""` | `GRIMOIRE_PLUGINS`: third-party plugins the image carries, to switch on |
| `dev` | `false` | also build the default branch, published under `/dev/` |
| `check` | `""` | a shell script that fails the run before anything is published |
| `launcher` | `""` | a Grimoire launcher in the repository, run with a plain Jennifer `image` instead |

## Recipes

### A book in a subdirectory

```yaml
    with:
      image: ghcr.io/jennifer-language/grimoire:0.4.0
      directory: manual
```

The book is built from `manual/grimoire.toml`. The whole repository is still
mounted, so a chapter can include a file from outside `manual/` with
[`grimoire-include`](plugins.md).

### A printable PDF

```yaml
      args: --pdf
```

The PDF is published beside the pages, under the name `[pdf] output` gives it.

### Plugins

The [plugins that ship with Grimoire](plugins.md) are in the image. A book uses
one by naming it in `grimoire.toml`, exactly as it does on your machine, and the
workflow needs no input for it.

A plugin that needs a program the image does not have - `grimoire-feed` and
`grimoire-lastmod` need `git`, `grimoire-mermaid` needs `mmdc` - needs an image
that has it. Build one from Grimoire's, as
[Installation](installation.md#plugins-in-the-image) shows, push it to a
registry, and name it:

```yaml
      image: ghcr.io/you/grimoire-with-git:0.4.0
```

**The image has to be public.** The workflow pulls it without logging in.

`git` in the image is enough for the git-based plugins: the workflow checks out
the full history, so `git log` sees every commit.

### Checks before publishing

`check` is a shell script, run with `bash -euxo pipefail` after the build and
before the upload. Any command that fails stops the run, and nothing is
published:

```yaml
      check: |
        test -s "$SITE/book.pdf"
        test "$(cat "$SITE/CNAME")" = "docs.example.org"
        grep -q 'href="install.html"' "$SITE/index.html"
```

It runs in the checkout the book was built from - the release, or the pull
request - with these set:

| Variable | |
| -------- | - |
| `SITE` | the output directory, as it will be published |
| `RELEASE` | the release being published; empty on a pull request, and before the first release |
| `IMAGE` | the container the book was built in |

The workflow already fails a build that wrote no `index.html`, so a check is for
what your book in particular must contain.

### Unreleased documentation under /dev/

```yaml
on:
  push:
    tags: ["[0-9]+.[0-9]+.[0-9]+"]
    branches: [main]
  pull_request:
  workflow_dispatch:

jobs:
  pages:
    # permissions as above
    uses: jennifer-language/grimoire/.github/workflows/docs-pages.yml@0.4.0
    with:
      image: ghcr.io/jennifer-language/grimoire:0.4.0
      dev: true
```

The site root is still the latest release; the tip of the default branch is
built as well and published under `/dev/`. Before the first release the default
branch is at the root already, so there is no `/dev/` until then.
`branches: [main]` is what makes a merge publish the new `/dev/`. Leave it out
without `dev: true`, once there is a release: a push to the default branch would
only republish the same release.

Nothing marks the `/dev/` pages as unreleased to a search engine. Expect them to
be indexed beside the release, and the sitemap a `sitemap` renderer writes into
`/dev/` to list the release's addresses rather than its own.

### A repository that carries Grimoire itself

A repository with its own Grimoire launcher names it and passes a plain Jennifer
image. That is how Grimoire publishes this manual - with the code it describes,
at the revision being published:

```yaml
      image: ghcr.io/jennifer-language/jennifer:0.25.0
      launcher: bin/grimoire
      args: --pdf
```

Grimoire's own `.github/workflows/pages.yml` is the complete example, `check`
included.

## Pinning

Pin `uses` to a Grimoire release rather than `@main`, for the reason the
workflow exists: `main` is unreleased code, and a change to it would change how
your next release is published.

Pin `image` to the same release. `grimoire:latest` is the newest Grimoire
release, never unreleased code, but it moves: a book republished after a new
Grimoire release is built by that release, and may come out different from the
build its own release got. With both pinned, upgrading Grimoire is a two-line
change you choose to make.

## When it fails

**"Tag "1.0.0" is not allowed to deploy to github-pages due to environment
protection rules".** The `github-pages` environment has no tag rule yet. The
build succeeded; only the deployment was refused. Add the rule as in
[step 3](#3-change-two-repository-settings), then re-run only the failed job, so
the finished build is reused: *Re-run failed jobs* on the run's page, or
`gh run rerun RUN-ID --failed`.

**The site shows the default branch, not the release.** The workflow found no
plain-semver tag, so it published the default branch instead; the run's summary
says so. A `v1.0.0` tag is not a release here - tag `1.0.0`.

**The deploy job asks for permissions it was not given.** The calling job has no
`permissions` block, or one without `pages: write` and `id-token: write`.

**The run succeeds, but the site does not change.** The Pages source is still
*Deploy from a branch*, which publishes something else; set it to *GitHub
Actions*.

**The site lost its custom domain.** The book has no `CNAME` file in its source
directory; see [the address](#the-address).

**A pull request fails at "Check the output".** The book built, but a line of
`check` failed. The log shows each command as it runs, and the last one shown is
the one that failed.
