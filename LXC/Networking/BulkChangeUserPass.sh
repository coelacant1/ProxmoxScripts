#!/bin/bash
#
# BulkChangeUserPass.sh
#
# Changes a user's password in a range of LXC containers.
# Containers must be running for password change to work.
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkChangeUserPass.sh <start_ct_id> <end_ct_id> <username> <new_password>
#
# Arguments:
#   start_ct_id   - Starting container ID
#   end_ct_id     - Ending container ID
#   username      - Username to change password for
#   new_password  - New password
#
# Examples:
#   BulkChangeUserPass.sh 400 402 root MyNewPass123
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid username:string new_password:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk change user password: Containers ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "Username: ${USERNAME}"
    __warn__ "Containers must be running for this operation"

    change_password_callback() {
        local vmid="$1"
        __ct_change_password__ "$vmid" "$USERNAME" "$NEW_PASSWORD"
    }

    __bulk_ct_operation__ --name "Change Password" --report "$START_VMID" "$END_VMID" change_password_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Passwords changed successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Pending validation
# - 2025-11-20: Updated to use ArgumentParser and BulkOperations framework
# - 2025-11-20: Validated against PVE Guide v9.1-1 (Chapter 11) and CONTRIBUTING.md
#
# Fixes:
# - Fixed: Changed ArgumentParser types from int to vmid for container ID validation
#
# Known issues:
# - Pending validation
# -
#

