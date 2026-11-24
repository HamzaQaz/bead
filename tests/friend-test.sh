#!/bin/bash
# make friend-test: install bead the way a friend would, on a fresh Arch (a
# throwaway podman container), both ways: ./install.sh and the package.
# The checks are in tests/friend-inside.sh (CI runs that too).
#   tests/friend-test.sh [user|package]   one way only
# Needs podman; pulls archlinux:latest and the packages (~1.5 GB the first time).
set -eu
cd "$(dirname "$0")/.."
command -v podman >/dev/null || { echo "friend-test needs podman" >&2; exit 1; }
src=$(mktemp -d); trap 'rm -rf "$src"' EXIT
# the working copy as git sees it (tracked and new files, not ignored ones),
# so it tests what you're about to commit
git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do
	if [ -e "$f" ]; then cp --parents "$f" "$src"; fi
done
chmod -R a+rX "$src"
for mode in ${1:-user package}; do
	echo "════ friend-test: $mode"
	podman run --rm -v "$src:/src:ro,Z" docker.io/library/archlinux:latest sh /src/tests/friend-inside.sh "$mode"
done
