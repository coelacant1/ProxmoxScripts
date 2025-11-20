#!/bin/bash
#
# BulkChangeDNS.sh
#
# Updates DNS nameservers for a range of LXC containers within a Proxmox VE cluster.
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkChangeDNS.sh <start_ct_id> <end_ct_id> <dns_servers>
#
# Arguments:
#   start_ct_id - Starting container ID
#   end_ct_id   - Ending container ID
#   dns_servers - Space-separated DNS server addresses (e.g., "8.8.8.8 1.1.1.1")
#
# Examples:
#   BulkChangeDNS.sh 400 402 "8.8.8.8 1.1.1.1"
#   BulkChangeDNS.sh 400 402 "8.8.8.8"
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
__parse_args__ "start_vmid:vmid end_vmid:vmid dns_servers:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk change DNS: Containers ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "DNS servers: ${DNS_SERVERS}"

    change_dns_callback() {
        local vmid="$1"
        __ct_set_dns__ "$vmid" "$DNS_SERVERS"
    }

    __bulk_ct_operation__ --name "Change DNS" --report "$START_VMID" "$END_VMID" change_dns_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "DNS settings updated successfully!"
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

