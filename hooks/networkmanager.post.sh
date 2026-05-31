#!/usr/bin/env bash
set -euo pipefail
__HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../lib/packages.sh
source "$__HOOK_DIR/../lib/packages.sh"

pkg::enable_service NetworkManager.service
