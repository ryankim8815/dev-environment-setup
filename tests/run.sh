#!/bin/bash
set -eu
set -o pipefail
TEST_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TEST_SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/dev-setup-tests.XXXXXXXX")
trap '/bin/rm -rf "$TEST_SANDBOX"' EXIT
mkdir -p "$TEST_SANDBOX/home with spaces"
for file in "$TEST_ROOT/setup.sh" "$TEST_ROOT"/lib/*.sh "$TEST_ROOT"/tests/*.sh; do /bin/bash -n "$file"; done
for file in "$TEST_ROOT"/templates/*.zsh; do /bin/zsh -n "$file"; done
# Only the child test process gets a temporary HOME; the caller's environment is untouched.
env -u CONDA_DEFAULT_ENV -u CONDA_PREFIX -u CONDA_SHLVL -u ZDOTDIR HOME="$TEST_SANDBOX/home with spaces" NVM_DIR= ZSH= MAMBA_ROOT_PREFIX= KREW_ROOT= \
    /bin/bash "$TEST_ROOT/tests/spec.sh" "$TEST_ROOT" "$TEST_SANDBOX"
