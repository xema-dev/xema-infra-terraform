#!/usr/bin/env bash
# GENERATED from tooling/ci/ci-steps/gitleaks-scan-tree.sh
# source-sha256: 60828fd65078764f341fee9684aaeb2dee352cd850f032c2a30d6432368c782d
# Builds the tree the gitleaks action scans and prints the config to scan it with (XEMA-9737).
#   gitleaks-scan-tree.sh <empty-dest-dir>      run from inside the repository
# The tree holds EVERY file `git ls-files` lists at HEAD, whatever .gitattributes says: `git archive` honours `export-ignore`, so a
# commit could drop a tracked file from the scan; checkout-index from a temporary index of HEAD does not. Untracked and ignored
# leftovers on a self-hosted runner never enter it. The config (printed, relative to <dest>) is the repository's own .gitleaks.toml
# when tracked, which must extend .github/gitleaks-base.toml or set useDefault = true (else the default rules would be lost);
# otherwise .github/gitleaks-base.toml.
set -euo pipefail
dest="${1:?usage: gitleaks-scan-tree.sh <empty-dest-dir>}"
mkdir -p "${dest}"
[ -z "$(ls -A "${dest}")" ] || { echo "::error::${dest} is not empty" >&2; exit 1; }
dest="$(cd "${dest}" && pwd)"
index="$(mktemp)"
trap 'rm -f "${index}"' EXIT
GIT_INDEX_FILE="${index}" git read-tree HEAD
GIT_INDEX_FILE="${index}" git checkout-index -a --prefix="${dest}/"
if [ -f "${dest}/.gitleaks.toml" ]; then
  if ! grep -Eq 'gitleaks-base\.toml|^[[:space:]]*useDefault[[:space:]]*=[[:space:]]*true' "${dest}/.gitleaks.toml"; then
    echo "::error::.gitleaks.toml neither extends .github/gitleaks-base.toml nor sets useDefault = true: the default token rules would be lost" >&2
    exit 1
  fi
  echo .gitleaks.toml
elif [ -f "${dest}/.github/gitleaks-base.toml" ]; then
  echo .github/gitleaks-base.toml
else
  echo "::error::neither .gitleaks.toml nor .github/gitleaks-base.toml is tracked at HEAD" >&2
  exit 1
fi
