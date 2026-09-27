#!/bin/bash
# Compatible with the Bash 3.2 shipped with macOS.
set -u
set -o pipefail
umask 077
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || exit 2
. "$ROOT/lib/core.sh"
. "$ROOT/lib/adapters.sh"
. "$ROOT/lib/settings.sh"
main "$@"
