#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
nvim_bin="${NVIM_BIN:-nvim}"
test_state_dir="$(mktemp -d "${TMPDIR:-/tmp}/nvim-headless-tests.XXXXXX")"
trap 'rm -R -- "$test_state_dir"' EXIT INT TERM

nvim_version="$("$nvim_bin" --version)"
printf '%s\n' "${nvim_version%%$'\n'*}"

for test_file in "$repo_root"/tests/*.lua; do
  printf 'Running %s\n' "${test_file#"$repo_root"/}"
  env \
    PUBBLE_TOKEN= \
    PUBBLE_DATADB= \
    XDG_STATE_HOME="$test_state_dir/state" \
    XDG_CACHE_HOME="$test_state_dir/cache" \
    "$nvim_bin" \
      --clean \
      --headless \
      -i NONE \
      --cmd "set runtimepath^=$repo_root" \
      -l "$test_file"
done
