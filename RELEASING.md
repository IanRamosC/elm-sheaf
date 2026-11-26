# Releasing

Sheaf is two packages, released separately:

- the CLI, the npm package `elm-sheaf` in `cli/`, with a standalone binary for
  each system attached to a GitHub release. Pushing a tag `v<version>` releases
  it through `.github/workflows/release.yml`.
- the Elm package `ianramosc/elm-sheaf` at the root, published by hand with
  `elm publish`.

Their versions are independent. A CLI supports every version of one major of
the Elm package, `SUPPORTED_MAJOR` in `cli/src/elm/package-version.ts`, and
`init` writes the version in `ELM_PACKAGE_VERSION` in
`cli/src/init/project-files.ts` into new sites.

## Already in place

- [x] The repository is public. npm provenance, `elm publish` and the Elm
  package website all need that.
- [x] Private vulnerability reporting is on, which `SECURITY.md` relies on.
  `gh api repos/IanRamosC/elm-sheaf/private-vulnerability-reporting` prints
  `{"enabled":true}`.
- [x] Dependabot alerts are on.

## What the release workflow does

A tag `v*` starts these jobs, each after the ones before it:

1. `ci` runs the whole of `ci.yml`, and `tag-check` fails unless the tag is
   `v` followed by the version in `cli/package.json`, and that version doesn't
   end in `-dev`.
2. `binaries` runs `bun run build-binaries` on macOS, which writes the five
   binaries and `THIRD_PARTY_LICENSES` into `cli/out/`. It signs the two macOS
   binaries ad hoc and verifies the signatures, then writes `SHA256SUMS` over
   every file.
3. `intel-binary` runs `sheaf-darwin-x64 --version` on an Intel Mac. That
   binary is cross-compiled on Apple Silicon, so this is the first time the
   file the release ships is run.
4. `npm` publishes `cli/` with `npm publish --provenance --access public`,
   through npm's trusted publishing: it signs in with the workflow's OIDC
   token, so no npm token is stored anywhere. When npm already has the
   version, it skips the publish and says so in a notice.
5. `release` creates the GitHub release with every file in `cli/out/`, or
   replaces the files of a release an earlier run created.

npm comes before the GitHub release because npm never takes a version twice,
while a release can be made again.

Only `npm` can get an OIDC token (`id-token: write`), and only `release` can
write to the repository (`contents: write`). The other jobs only read, and
`intel-binary` has no permissions at all.

## The first release, 1.0.0

Trusted publishing is set up in the settings of a package that already exists
on npm, so 1.0.0 goes to npm by hand, and the workflow does the rest.

1. In `CHANGELOG.md`, rename `## Unreleased` to `## [1.0.0] - <date>`.
2. Set `"version"` in `cli/package.json` to `1.0.0`.
3. Remove the notes that say Sheaf isn't released and send people to
   `--local`: the Status section of `README.md` and of `cli/README.md`,
   "Before the first release" in `docs/guide/getting-started.md` and the
   links to it, and the sentence about it at the top of `docs/guide/cli.md`
   and under `--local` there. The Install section of `README.md` and "Install
   Sheaf" in the guide already describe the published packages and binaries.
4. Add the version badges to the badge row of `README.md`, with their
   references next to the others:

   ```markdown
   [![npm](https://img.shields.io/npm/v/elm-sheaf)][npm]
   [![Elm package](https://img.shields.io/elm-package/v/ianramosc/elm-sheaf)][elm-package]

   [npm]: https://www.npmjs.com/package/elm-sheaf
   [elm-package]: https://package.elm-lang.org/packages/ianramosc/elm-sheaf/latest/
   ```

5. Merge into `main` and wait for CI to pass.
6. Publish the Elm package `1.0.0`, as [the Elm package](#the-elm-package)
   describes. Sites made by `init` depend on it, so it goes first.
7. Tag the CLI, without pushing the tag yet, and publish it to npm from a
   clean checkout of the tag:

   ```sh
   git switch main
   git pull
   git tag v1.0.0
   git worktree add ../elm-sheaf-v1.0.0 v1.0.0
   cd ../elm-sheaf-v1.0.0/cli
   npm login
   npm publish --dry-run --access public    # check the file list
   npm publish --access public
   ```

   A publish from your machine carries no provenance. Later versions, which
   the workflow publishes, do.
8. On npmjs.com, open `elm-sheaf`'s settings and add a trusted publisher:
   GitHub Actions, organisation or user `IanRamosC`, repository `elm-sheaf`,
   workflow file name `release.yml`, no environment. Then, under publishing
   access, require two-factor authentication and disallow tokens; trusted
   publishing still works.
9. Push the tag: `git push origin v1.0.0`. The workflow finds 1.0.0 on npm,
   skips it, and attaches the binaries to the release. Remove the worktree
   with `git worktree remove ../elm-sheaf-v1.0.0`.
10. Start the next version, as in step 6 of
    [Every later release](#every-later-release).

From then on `bunx elm-sheaf init my-blog` makes a site that depends on the
published packages: `elm-sheaf` from npm and `ianramosc/elm-sheaf` from the
Elm package website. `--local` stays for working on Sheaf itself.

## Every later release

1. In `CHANGELOG.md`, rename `## Unreleased` to `## [<version>] - <date>`.
2. Set `"version"` in `cli/package.json` to the version, dropping `-dev`:
   `1.1.0-dev` becomes `1.1.0`.
3. Merge into `main` and wait for CI to pass.
4. Tag the merged commit and push the tag:

   ```sh
   git switch main
   git pull
   git tag v1.1.0
   git push origin v1.1.0
   ```

5. Watch the run with `gh run watch`, or in the Actions tab, until the release
   appears on the Releases page.
6. On `main`, set the version to the next one with `-dev`, such as
   `1.2.0-dev`, and open a new `## Unreleased` section in the changelog. While
   `main` carries a `-dev` version, `tag-check` refuses any tag pushed from it
   by mistake.

## The Elm package

`elm publish` wants a tag that is exactly the version, `1.0.0` with no `v`,
and checks the documentation itself, so it is run by hand. A tag without the
`v` doesn't start the release workflow.

1. Check that every exposed value has its documentation:

   ```sh
   elm make --docs="${TMPDIR:-/tmp}/docs.json"
   ```

2. From the second version on, let Elm choose the version from the API
   changes, and see what changed:

   ```sh
   elm bump
   elm diff
   ```

   The first version has to be `1.0.0`, which `elm.json` already says.
3. If the major version changed, the CLI needs a release too: raise
   `SUPPORTED_MAJOR` and `ELM_PACKAGE_VERSION`, and say in the changelog that
   sites must move to the new major.
4. Commit `elm.json`, merge into `main`, then tag and publish from that
   commit:

   ```sh
   git tag 1.0.0
   git push origin 1.0.0
   elm publish
   ```

## A release that stopped halfway

Running the whole workflow again is always safe: `ci`, `tag-check`,
`binaries` and `intel-binary` only repeat their work, `npm` skips a version npm already has, and
`release` replaces the files of a release that exists. Use "Re-run all jobs"
in the Actions tab, or:

```sh
gh run rerun <run id>
```

"Re-run failed jobs" (`gh run rerun <run id> --failed`) also works within
seven days, while the `binaries` job's files are kept.

- **It failed before `npm`.** Nothing is published. If the fix needs a change
  to the code, delete the tag (`git push origin --delete v1.1.0` and
  `git tag --delete v1.1.0`), fix `main`, and tag again.
- **`npm` published, and `release` failed.** Re-run the workflow. The tag
  can't move, because npm already has that version from that commit.
- **The published version is broken.** npm never takes a version twice:
  deprecate it with `npm deprecate elm-sheaf@<version> "<reason>"` and release
  the next patch version.
