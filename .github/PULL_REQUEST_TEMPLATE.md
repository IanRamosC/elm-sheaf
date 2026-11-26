## What and why

<!-- What this changes, and the problem it solves. Link the issue, if there is one. -->

## How it was tested

<!-- The tests you added or changed, and anything you checked by hand, such as a site built with `sheaf dev`. -->

## Checklist

- [ ] `elm-format --validate src tests review/src cli/templates/default/src cli/test/fixtures docs/src`
- [ ] `bun test`, `bunx --bun biome check .` and `bunx --bun tsc --noEmit` in `cli/`
- [ ] `elm-test-rs`, `elm-review` and `elm make --docs=/tmp/sheaf-docs.json` at the root
- [ ] The user guide in `docs/content/guide/` describes the change, if users can see it
