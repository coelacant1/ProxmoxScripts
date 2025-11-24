#!/bin/bash
#
# RemoveGuacamoleAuthenticationToken.sh
#
# Deletes the locally saved Guacamole authentication token.
#
# Usage:
#   RemoveGuacamoleAuthenticationToken.sh
#
# Examples:
#   RemoveGuacamoleAuthenticationToken.sh
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

TOKEN_PATH="/tmp/cc_pve/guac_token"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    if [[ ! -f "$TOKEN_PATH" ]]; then
        __warn__ "No Guacamole auth token found"
        __info__ "Expected location: $TOKEN_PATH"
        exit 0
    fi

    rm -f "$TOKEN_PATH"
    __ok__ "Guacamole auth token deleted"
    __info__ "Location: $TOKEN_PATH"

    __prompt_keep_installed_packages__
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Validated against CONTRIBUTING.md and Apache Guacamole API best practices
# - 2025-11-20: Updated to use utility functions
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

