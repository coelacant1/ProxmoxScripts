#!/bin/bash
#
# BulkAddSSHKey.sh
#
# Appends an SSH public key to the root user's authorized_keys file
# for a range of LXC containers. Containers must be running.
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkAddSSHKey.sh <start_ct_id> <end_ct_id> <ssh_public_key>
#
# Arguments:
#   start_ct_id    - Starting container ID
#   end_ct_id      - Ending container ID
#   ssh_public_key - SSH public key to add
#
# Examples:
#   BulkAddSSHKey.sh 400 402 "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ..."
#
# Function Index:
#   - main
#   - add_ssh_key_callback
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

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid ssh_key:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk add SSH key: Containers ${START_VMID} to ${END_VMID} (cluster-wide)"
    __warn__ "Containers must be running for this operation"

    add_ssh_key_callback() {
        local vmid="$1"
        __ct_add_ssh_key__ "$vmid" "$SSH_KEY"
    }

    __bulk_ct_operation__ --name "Add SSH Key" --report "$START_VMID" "$END_VMID" add_ssh_key_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "SSH key added successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and BulkOperations framework
#   - Pending validation
