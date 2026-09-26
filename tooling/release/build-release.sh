#!/usr/bin/env bash
# Build the release artifacts of ONE tag, deterministically.
#
#   tooling/release/build-release.sh v0.7.0 [out-dir]
#
# Produces, in out-dir (default dist/):
#   xema-infra-terraform-<tag>.tar.gz  the whole tree at the tag, under the
#                                      prefix xema-infra-terraform-<tag>/
#   MANIFEST.sha256                    sha256 of every file in that tree, paths
#                                      relative to the prefix, sorted
#   SHA256SUMS                         sha256 of the two files above
#
# WHY THESE THREE. A consumer pins a release by the archive's and the manifest's
# digests (its lock), stores both wherever IT controls — its own registry, its
# own storage, or unpacked into its own repository — and verifies them with
# nothing but `sha256sum` and `tar`. So a deployment that consumes this release
# can plan and apply after this repository, this organisation or GitHub itself
# has gone: the release is the product, the repository is only where it is made.
#
# WHY THE WHOLE TREE. Stacks reference modules by relative path, so a subset is
# a tree Terraform cannot resolve unless someone curates the closure by hand —
# and a hand-curated copy is exactly what this replaces.
#
# WHICH DIGEST IS THE IDENTITY. MANIFEST.sha256 is a function of the tree's
# BYTES only, so its digest is identical wherever the release is rebuilt —
# measured for v0.7.0: CI (Linux) and a macOS rebuild agree. That is the digest
# a lock pins as the release's identity. The ARCHIVE is not: `git archive` is
# byte-stable, but two gzip implementations compress it differently (the same
# v0.7.0 archive digests differently on Linux and macOS), so the archive digest
# verifies a download of THE PUBLISHED FILE and nothing more.
set -euo pipefail

tag="${1:?usage: build-release.sh <tag> [out-dir]}"
out="${2:-dist}"
prefix="xema-infra-terraform-${tag}"

git rev-parse -q --verify "refs/tags/${tag}" >/dev/null \
  || { echo "build-release: no tag ${tag} in this repository" >&2; exit 2; }
commit="$(git rev-parse "${tag}^{commit}")"

if command -v sha256sum >/dev/null; then sha() { sha256sum "$@"; }; else sha() { shasum -a 256 "$@"; }; fi

mkdir -p "${out}"
archive="${out}/${prefix}.tar.gz"
git archive --format=tar --prefix="${prefix}/" "${commit}" | gzip -n -9 > "${archive}"

# The manifest is computed from the ARCHIVE, not from a working tree, so it
# describes exactly the bytes a consumer will unpack.
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
tar -xzf "${archive}" -C "${work}"
( cd "${work}/${prefix}" && find . -type f -print | LC_ALL=C sort | sed 's#^\./##' | while IFS= read -r f; do sha "$f"; done ) \
  | sed 's/ \*/  /' > "${out}/MANIFEST.sha256"

( cd "${out}" && sha "${prefix}.tar.gz" MANIFEST.sha256 | sed 's/ \*/  /' > SHA256SUMS )

files="$(wc -l < "${out}/MANIFEST.sha256" | tr -d ' ')"
echo "release ${tag} (${commit})"
echo "  ${prefix}.tar.gz  $(sha "${archive}" | cut -d' ' -f1)"
echo "  MANIFEST.sha256   $(sha "${out}/MANIFEST.sha256" | cut -d' ' -f1)  (${files} files)"
