#!/bin/bash
#
# BulkChangeUserPass.sh
#
# Updates Cloud-Init username and password for virtual machines within a Proxmox VE cluster.
# Uses BulkOperations framework for cluster-wide execution.
#
# Usage:
#   BulkChangeUserPass.sh <start_vmid> <end_vmid> <password> [username]
#
# Arguments:
#   start_vmid - Starting VM ID
#   end_vmid   - Ending VM ID
#   password   - Password to set
#   username   - Optional username to set
#
# Examples:
#   BulkChangeUserPass.sh 400 430 myNewPassword
#   BulkChangeUserPass.sh 400 430 myNewPassword newuser
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
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid password:string username?:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    change_userpass_callback() {
        local vmid="$1"

        local args="--cipassword ${PASSWORD}"
        [[ -n "${USERNAME:-}" ]] && args="${args} --ciuser ${USERNAME}"

        __vm_set_config__ "$vmid" $args
        __vm_node_exec__ "$vmid" "qm cloudinit dump {vmid}" >/dev/null 2>&1 || true
    }

    __bulk_vm_operation__ --report "$START_VMID" "$END_VMID" change_userpass_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "User/password updated successfully!"
}

main

# Testing status:
#   - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
