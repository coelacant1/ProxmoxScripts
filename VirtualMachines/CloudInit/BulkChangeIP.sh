#!/bin/bash
#
# BulkChangeIP.sh
#
# Updates IP addresses for virtual machines within a Proxmox VE cluster.
# Assigns incrementing IPs starting from a base IP address.
#
# Usage:
#   BulkChangeIP.sh <start_vmid> <end_vmid> <start_ip/cidr> <bridge> [gateway]
#
# Arguments:
#   start_vmid    - Starting VM ID
#   end_vmid      - Ending VM ID
#   start_ip/cidr - Starting IP with CIDR (e.g., 192.168.1.50/24)
#   bridge        - Network bridge (e.g., vmbr0)
#   gateway       - Optional gateway IP address
#
# Examples:
#   BulkChangeIP.sh 400 430 192.168.1.50/24 vmbr0 192.168.1.1
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
# shellcheck source=Utilities/Conversion.sh
source "${UTILITYPATH}/Conversion.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid start_ip_cidr:string bridge:string gateway:string:?" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Parse IP and CIDR
    IFS='/' read -r START_IP SUBNET_MASK <<<"$START_IP_CIDR"

    __info__ "Starting IP: ${START_IP}/${SUBNET_MASK}, Bridge: ${BRIDGE}"
    [[ -n "${GATEWAY:-}" ]] && __info__ "Gateway: ${GATEWAY}"

    local start_ip_int
    start_ip_int=$(__ip_to_int__ "$START_IP")

    change_ip_callback() {
        local vmid="$1"

        local current_ip_int=$((start_ip_int + vmid - START_VMID))
        local new_ip
        new_ip=$(__int_to_ip__ "$current_ip_int")

        local ipconfig="ip=${new_ip}/${SUBNET_MASK}"
        [[ -n "${GATEWAY:-}" ]] && ipconfig="${ipconfig},gw=${GATEWAY}"

        __vm_set_config__ "$vmid" --ipconfig0 "$ipconfig" --net0 "virtio,bridge=${BRIDGE}"
        __vm_node_exec__ "$vmid" "qm cloudinit update {vmid}" >/dev/null 2>&1 || true
    }

    __bulk_vm_operation__ --name "Change IP" --report "$START_VMID" "$END_VMID" change_ip_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "IP addresses updated successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
#
# Fixes:
# - 2025-11-24: Fixed incorrect command - changed 'qm cloudinit dump' to
#   'qm cloudinit update' to properly regenerate Cloud-Init config per PVE Guide
# - 2025-11-24: Fixed ArgumentParser optional syntax - changed 'gateway?:string'
#   to correct format 'gateway:string:?'
#
# Known issues:
# -
#

