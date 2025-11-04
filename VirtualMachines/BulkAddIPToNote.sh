#!/bin/bash
#
# BulkAddIPToNote.sh
#
# Updates VM notes with IP addresses retrieved via guest agent or ARP scan.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   BulkAddIPToNote.sh <start_vm_id> <end_vm_id>
#
# Arguments:
#   start_vm_id - Starting VM ID
#   end_vm_id   - Ending VM ID
#
# Examples:
#   BulkAddIPToNote.sh 400 430
#
# Function Index:
#   - main
#   - add_ip_to_note_callback
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
__parse_args__ "start_vmid:vmid end_vmid:vmid" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __install_or_prompt__ "arp-scan"

    __info__ "Bulk add IP to notes: VMs ${START_VMID} to ${END_VMID} (cluster-wide)"

    add_ip_to_note_callback() {
        local vmid="$1"
        __vm_add_ip_to_note__ "$vmid"
    }

    __bulk_vm_operation__ --name "Add IP to Note" --report "$START_VMID" "$END_VMID" add_ip_to_note_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "IP addresses added to notes successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and BulkOperations framework
#   - Pending validation
