#!/usr/bin/env bash
#
# Builds the starter site from this clone and checks what it writes: the HTML
# with the Nu Html Checker, the links with lychee, and accessibility with axe
# in both colour schemes.
#
#     cli/scripts/check-starter.sh
#
# The site is built twice: at the root of its domain, and under /blog/, the
# way GitHub Pages serves a project site, so that a link which forgets the
# base path is caught. Needs Bun, Elm 0.19.3, Docker and Google Chrome (set
# CHROME to its executable when it isn't in its usual place), and
# `bun install` run in cli/ and tools/a11y/.

set -euo pipefail

# Pinned by digest: the validator's dated tags stopped in 2024, and "latest"
# moves with every release. This is vnu 26.11.20.
VNU_IMAGE=ghcr.io/validator/validator@sha256:f10441aee7dcea043d2153b0a8bbce13dafeafc8a3680b69b88b83ba5b9880f5
LYCHEE_IMAGE=lycheeverse/lychee:0.24.2

repo=$(cd "$(dirname "$0")/../.." && pwd -P)
sheaf=("bun" "$repo/cli/src/index.ts")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Resolved, because Docker mounts it at the same path and a symlinked temporary
# folder (macOS's /var) would not match the links lychee reads.
work=$(cd "$work" && pwd -P)

site=$work/site
root_out=$work/dist-root
blog_root=$work/blog-root
blog_out=$blog_root/blog

step() {
  printf '\n== %s\n' "$1" >&2
}

step "Building the starter"
"${sheaf[@]}" init "$site" --local "$repo" >/dev/null
(cd "$site" && "${sheaf[@]}" build)
mv "$site/dist" "$root_out"
(cd "$site" && "${sheaf[@]}" build --site-url https://example.com/blog/)
mkdir -p "$blog_root"
mv "$site/dist" "$blog_out"

docker_run() {
  docker run --rm --volume "$work:$work:ro" "$@"
}

# Both checkers pass quietly when they are given a folder they can't see, so
# make sure Docker shares this one before trusting them.
if ! docker_run --entrypoint test "$VNU_IMAGE" -f "$root_out/index.html" -a -f "$blog_out/index.html"; then
  echo "Docker can't see $work; share it with Docker and try again" >&2
  exit 1
fi

step "Validating the HTML"
docker_run "$VNU_IMAGE" java -jar /vnu.jar --skip-non-html --errors-only \
  "$root_out" "$blog_out"

# Each build's own address is mapped onto its folder, so every absolute URL in
# the pages and the feeds is checked against a file. A link that leaves out
# /blog/ lands outside blog/ and fails. Any other URL on the domain is mapped
# onto the root folder too: offline, lychee skips a URL it can't map, so a
# full URL without /blog/ would otherwise pass unchecked.
check_links() {
  local dir=$1 root=$2 url=$3
  docker_run "$LYCHEE_IMAGE" --offline --no-progress \
    --index-files index.html \
    --root-dir "$root" \
    --remap "$url file://$dir/" \
    --remap "https://example.com/ file://$root/" \
    "$dir/**/*.html" "$dir/**/*.xml"
}

step "Checking links at the root"
check_links "$root_out" "$root_out" https://example.com/

step "Checking links under /blog/"
check_links "$blog_out" "$blog_root" https://example.com/blog/

step "Auditing accessibility"
bun "$repo/tools/a11y/audit.ts" "$root_out"
