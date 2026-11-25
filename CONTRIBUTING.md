# Contributing to Sheaf

Thank you for helping. Bug reports, ideas and pull requests are all welcome.
For anything larger than a small fix, open an issue first so we can agree on
the approach before you spend time on it. Report security problems privately,
as [SECURITY.md](SECURITY.md) describes.

## Setting up

You need:

- Bun 1.4.5 exactly, the version `packageManager` in `cli/package.json` pins.
  The tests' expected output contains image file names, which hash the Bun
  version, so another Bun fails them. Install it with
  `curl -fsSL https://bun.sh/install | bash -s "bun-v1.4.5"`.
- Node.js and npm, for the Elm tools.
- Elm 0.19.3 and the Elm tools, installed with npm:

  ```sh
  npm install -g elm@0.19.3-0 elm-test-rs@3.2.0-0 elm-review@2.13.5 elm-format@0.8.8
  ```

  The Elm package is tested with `elm-test-rs`, because older `elm-test`
  releases don't run on Elm 0.19.3.

Then install the CLI's dependencies:

```sh
cd cli
bun install
```

## Running the checks

Every pull request must pass these, and CI runs the same ones. At the root of
the repository:

```sh
elm-format --validate src tests review/src cli/templates/default/src cli/test/fixtures
```

Run it before the tests: they build the fixture sites in place, which writes
generated, unformatted Elm into their `.sheaf/gen/`.

In `cli/`:

```sh
bun test
bunx --bun biome check .
bunx --bun tsc --noEmit
```

`bun run check` runs the last two. `bunx --bun biome check --write .` fixes
what Biome can fix on its own.

At the root again:

```sh
elm-test-rs
elm-review
elm make --docs=/tmp/sheaf-docs.json
```

The last one fails when an exposed function has no documentation comment, as
`elm publish` would. Write the docs file anywhere outside the repository.

### Generated test files

Some test inputs are generated, and a test fails when they are out of date:

- The protocol fixtures in `tests/fixtures/protocol/` are shared by the
  TypeScript and Elm tests. `elm-test-rs` can't read files, so they are
  embedded in `tests/ProtocolFixtures.elm`. After changing a fixture, run
  `bun run embed-fixtures` in `cli/` and commit both.
- The build tests compare the fixture sites' output with snapshots in
  `cli/test/__snapshots__/`. When a change to the output is intended, run
  `bun test --update-snapshots` in `cli/` and review the snapshot diff like
  code.
- Raising the pinned Bun changes the names of every image variant, so it is a
  commit of its own that updates the pin and the snapshots together.

## How the repository is laid out

```
elm.json, src/Sheaf/     the Elm package, ianramosc/elm-sheaf; it sits at the root for elm publish
tests/                   elm-test-rs tests for the Elm package
review/                  elm-review configuration
cli/                     the npm package elm-sheaf: the CLI and the host that runs the build
  src/cli/               command-line parsing and terminal output, the only code that writes to stdout
  src/config/            reading sheaf.json
  src/content/           collections, frontmatter, reserved keys, slugs and dates
  src/markdown/          parsing Markdown, directives and link checking
  src/highlight/         Shiki and its cache
  src/images/            image processing with Bun.Image, and its cache
  src/elm/               generating Elm code, compiling it, running it, and the protocol between host and Elm
  src/emit/              writing pages, feeds, the sitemap and static files
  src/dev/               the development server, file watching and live reload
  src/diagnostics/       the Diagnostic type and how it is printed
  templates/default/     the starter that sheaf init copies
  test/                  bun tests, and fixture sites in test/fixtures/
docs/guide/              the user guide
```

The host does all the IO: it reads the content, parses the Markdown,
highlights code and processes images, then hands everything to the site's
compiled Elm, which decodes frontmatter, builds the routes and renders every
page. The two sides talk through one versioned JSON request and response,
whose types are in `cli/src/elm/protocol.ts`.

## The code standard

Write code a reviewer can read without the author in the room:

- Idiomatic for its language, with names from the domain (`Post`, `Slug`,
  `Diagnostic`, never `data` or `handler2`).
- Small modules with one job, and no abstraction until a second real use needs
  it.
- Comments say why, never what the code already says. Every exposed Elm
  module and function has a documentation comment, as `elm publish` requires.
- Expected failures are values: `Result` in both languages, collected so that a
  user sees every problem at once. Exceptions are for bugs.
- Nothing fails silently. An unknown component, a broken link or a bad
  frontmatter field is always an error, never quietly left out of the output.
- The output contains no JavaScript.
- TypeScript is strict, with `noUncheckedIndexedAccess` and
  `exactOptionalPropertyTypes`, and never uses `any`. Code is written against
  Node's standard modules where it can be, and keeps Bun-only APIs at the
  edges.
- The Elm package depends only on `elm/core`, `elm/json` and `elm/time`, and
  released Elm code has no `Debug`.
- Error messages follow Elm's: say what is wrong, point at where, and suggest a
  fix. A new diagnostic needs a line in [the CLI reference](docs/guide/cli.md);
  `cli/test/docs.test.ts` fails until it has one.

Pull requests should be small enough to review in one sitting, with tests for
what they change. A change in behaviour updates the user guide in the same
pull request.

## Commits

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/),
with the package as the scope when there is one: `feat(cli): sheaf init`,
`fix(cli): keep cache failures from crashing the build`, `refactor: tidy the
starter theme`. The
subject says what changed; the body, when there is one, says why.
