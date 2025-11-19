#!/bin/bash
#
# BulkChangeIP.sh
#
# Updates IP addresses for LXC containers within a Proxmox VE cluster.
# Assigns incrementing IPs starting from a base IP address.
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkChangeIP.sh <start_ct_id> <end_ct_id> <start_ip/cidr> <bridge> [gateway]
#
# Arguments:
#   start_ct_id   - Starting container ID
#   end_ct_id     - Ending container ID
#   start_ip/cidr - Starting IP with CIDR (e.g., 192.168.1.50/24)
#   bridge        - Network bridge (e.g., vmbr0)
#   gateway       - Optional gateway IP address
#
# Examples:
#   BulkChangeIP.sh 400 404 192.168.1.50/24 vmbr0
#   BulkChangeIP.sh 400 404 192.168.1.50/24 vmbr0 192.168.1.1
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
# shellcheck source=Utilities/Conversion.sh
source "${UTILITYPATH}/Conversion.sh"
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:int end_vmid:int start_ip_cidr:string bridge:string gateway:string:?" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Parse IP and CIDR
    IFS='/' read -r START_IP SUBNET_MASK <<<"$START_IP_CIDR"

    __info__ "Bulk change IP: Containers ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "Starting IP: ${START_IP}/${SUBNET_MASK}, Bridge: ${BRIDGE}"
    [[ -n "${GATEWAY:-}" ]] && __info__ "Gateway: ${GATEWAY}"

    local start_ip_int
    start_ip_int=$(__ip_to_int__ "$START_IP")

    change_ip_callback() {
        local vmid="$1"

        local current_ip_int=$((start_ip_int + vmid - START_VMID))
        local new_ip
        new_ip=$(__int_to_ip__ "$current_ip_int")

        local net_config="name=eth0,bridge=${BRIDGE},ip=${new_ip}/${SUBNET_MASK}"
        [[ -n "${GATEWAY:-}" ]] && net_config="${net_config},gw=${GATEWAY}"

        __ct_set_network__ "$vmid" "$net_config"
    }

    __bulk_ct_operation__ --name "Change IP" --report "$START_VMID" "$END_VMID" change_ip_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "IP addresses updated successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and BulkOperations framework
#   - Pending validation
