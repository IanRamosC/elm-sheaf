#!/usr/bin/env bash
#
# Builds a site from this clone and checks what it writes: the HTML with the
# Nu Html Checker, the links with lychee, and accessibility with axe in both
# colour schemes.
#
#     cli/scripts/check-site.sh [starter | docs]
#
# "starter" builds the starter, with a second post that has an old URL, twice:
# at the root of its domain, and under /blog/, the way GitHub Pages serves a
# project site, so that a link which forgets the base path is caught. "docs"
# builds the documentation website in docs/, which lives under /elm-sheaf/,
# and audits it at a desktop width and at a phone's. With no argument, both
# are checked. Needs Bun, Elm 0.19.3, Docker and Google Chrome (set CHROME to
# its executable when it isn't in its usual place), and `bun install` run in
# cli/ and tools/a11y/.

set -euo pipefail

# Pinned by digest: the validator's dated tags stopped in 2024, and "latest"
# moves with every release. This is vnu 26.11.20.
VNU_IMAGE=ghcr.io/validator/validator@sha256:f10441aee7dcea043d2153b0a8bbce13dafeafc8a3680b69b88b83ba5b9880f5
LYCHEE_IMAGE=lycheeverse/lychee:0.24.2

case ${1:-all} in
  starter | docs | all) which=${1:-all} ;;
  *)
    echo "Usage: $0 [starter | docs]" >&2
    exit 2
    ;;
esac

repo=$(cd "$(dirname "$0")/../.." && pwd -P)
sheaf=("bun" "$repo/cli/src/index.ts")
audit=("bun" "$repo/tools/a11y/audit.ts")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Resolved, because Docker mounts it at the same path and a symlinked temporary
# folder (macOS's /var) would not match the links lychee reads.
work=$(cd "$work" && pwd -P)

step() {
  printf '\n== %s\n' "$1" >&2
}

docker_run() {
  docker run --rm --volume "$work:$work:ro" "$@"
}

# Both checkers pass quietly when they are given a folder they can't see, so
# make sure Docker shares each one before trusting them.
check_docker_sees() {
  local out
  for out in "$@"; do
    if ! docker_run --entrypoint test "$VNU_IMAGE" -f "$out/index.html"; then
      echo "Docker can't see $work; share it with Docker and try again" >&2
      exit 1
    fi
  done
}

validate_html() {
  docker_run "$VNU_IMAGE" java -jar /vnu.jar --skip-non-html --errors-only "$@"
}

# The build's own address is mapped onto its folder, so every absolute URL in
# the pages and the feeds is checked against a file. A link that leaves out
# the base path lands outside the build's folder and fails. Any other URL on
# the domain is mapped onto the root folder too: offline, lychee skips a URL
# it can't map, so a full URL without the base path would otherwise pass
# unchecked.
check_links() {
  local dir=$1 root=$2 url=$3 domain=$4
  docker_run "$LYCHEE_IMAGE" --offline --no-progress \
    --index-files index.html \
    --root-dir "$root" \
    --remap "$url file://$dir/" \
    --remap "$domain file://$root/" \
    "$dir/**/*.html" "$dir/**/*.xml"
}

check_starter() {
  local site=$work/starter
  local root_out=$work/starter-root
  local blog_root=$work/starter-blog
  local blog_out=$blog_root/blog

  step "Building the starter"
  "${sheaf[@]}" init "$site" --local "$repo" >/dev/null
  # A second, older post, so each post links to the other, and an old URL of
  # it, so a redirect page is checked too.
  cat >"$site/content/posts/older.md" <<'POST'
---
title: An older post
date: 2020-01-01
aliases: [/old-welcome/]
---

Hi.
POST
  (cd "$site" && "${sheaf[@]}" build)
  mv "$site/dist" "$root_out"
  (cd "$site" && "${sheaf[@]}" build --site-url https://example.com/blog/)
  mkdir -p "$blog_root"
  mv "$site/dist" "$blog_out"

  # The checks below only mean something if the pages they are meant to cover
  # were written.
  local out
  for out in "$root_out" "$blog_out"; do
    if ! grep -q 'aria-label="More posts"' "$out/posts/older/index.html"; then
      echo "$out/posts/older/index.html has no links to other posts" >&2
      exit 1
    fi
    if ! grep -q 'http-equiv="refresh"' "$out/old-welcome/index.html"; then
      echo "$out/old-welcome/index.html is not a redirect page" >&2
      exit 1
    fi
  done
  check_docker_sees "$root_out" "$blog_out"

  step "Validating the starter's HTML"
  validate_html "$root_out" "$blog_out"

  step "Checking the starter's links at the root"
  check_links "$root_out" "$root_out" https://example.com/ https://example.com/

  step "Checking the starter's links under /blog/"
  check_links "$blog_out" "$blog_root" https://example.com/blog/ https://example.com/

  step "Auditing the starter's accessibility"
  "${audit[@]}" "$root_out"
  "${audit[@]}" --width 375 "$root_out"
}

# Built in docs/ itself, whose elm.json reaches the package through ../src.
check_docs() {
  local url=https://ianramosc.github.io/elm-sheaf/
  local root=$work/docs
  local out=$root/elm-sheaf

  step "Building the documentation website"
  (cd "$repo/docs" && "${sheaf[@]}" build)
  mkdir -p "$root"
  mv "$repo/docs/dist" "$out"
  if ! grep -q 'aria-current="page"' "$out/guide/getting-started/index.html"; then
    echo "$out/guide/getting-started/index.html has no sidebar" >&2
    exit 1
  fi
  check_docker_sees "$out"

  step "Validating the documentation website's HTML"
  validate_html "$out"

  step "Checking the documentation website's links"
  check_links "$out" "$root" "$url" https://ianramosc.github.io/

  step "Auditing the documentation website's accessibility"
  "${audit[@]}" --base /elm-sheaf/ "$out"
  "${audit[@]}" --base /elm-sheaf/ --width 375 "$out"
}

if [ "$which" != docs ]; then
  check_starter
fi
if [ "$which" != starter ]; then
  check_docs
fi
