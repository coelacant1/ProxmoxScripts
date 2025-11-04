#!/bin/bash
#
# BulkAddSSHKey.sh
#
# Adds an SSH public key to virtual machines within a Proxmox VE cluster.
# Appends key and regenerates Cloud-Init image to apply changes.
#
# Usage:
#   BulkAddSSHKey.sh <start_vmid> <end_vmid> <ssh_public_key>
#
# Arguments:
#   start_vmid     - Starting VM ID
#   end_vmid       - Ending VM ID
#   ssh_public_key - SSH public key to add
#
# Examples:
#   BulkAddSSHKey.sh 400 430 "ssh-rsa AAAAB3Nza... user@host"
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
# shellcheck source=Utilities/ProxmoxAPI.sh
source "${UTILITYPATH}/ProxmoxAPI.sh"
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid ssh_public_key:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    local temp_file
    temp_file="$(mktemp)"
    trap 'rm -f "$temp_file"' EXIT

    add_ssh_key_callback() {
        local vmid="$1"

        if __vm_node_exec__ "$vmid" "qm cloudinit get {vmid} ssh-authorized-keys" > "$temp_file" 2>/dev/null; then
            echo "$SSH_PUBLIC_KEY" >> "$temp_file"
            __vm_set_config__ "$vmid" --sshkeys "$temp_file"
            __vm_node_exec__ "$vmid" "qm cloudinit dump {vmid}" >/dev/null 2>&1 || true
        else
            return 1
        fi
    }

    __bulk_vm_operation__ --name "Add SSH Key" --report "$START_VMID" "$END_VMID" add_ssh_key_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "SSH key added successfully!"
}

main

# Testing status:
#   - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
