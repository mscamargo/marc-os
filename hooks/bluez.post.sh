#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=SCRIPTDIR/../functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../functions.sh"

enable_service bluetooth.service
