#!/bin/bash
#
# BulkAddIPToNote.sh
#
# Updates the description/notes field of LXC containers with their IP addresses.
# Attempts to retrieve IP via pct exec, falls back to arp-scan if needed.
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkAddIPToNote.sh <start_ct_id> <end_ct_id>
#
# Arguments:
#   start_ct_id - Starting container ID
#   end_ct_id   - Ending container ID
#
# Examples:
#   BulkAddIPToNote.sh 100 150
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
__parse_args__ "start_vmid:vmid end_vmid:vmid" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __install_or_prompt__ "arp-scan"

    __info__ "Bulk add IP to notes: Containers ${START_VMID} to ${END_VMID} (cluster-wide)"

    add_ip_to_note_callback() {
        local vmid="$1"
        __ct_add_ip_to_note__ "$vmid"
    }

    __bulk_ct_operation__ --name "Add IP to Note" --report "$START_VMID" "$END_VMID" add_ip_to_note_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "IP addresses added to notes successfully!"
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
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# - Pending validation
# -
#

