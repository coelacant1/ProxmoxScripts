#!/bin/bash
#
# BulkChangeDNS.sh
#
# Updates DNS settings for virtual machines within a Proxmox VE cluster.
# Sets DNS server and search domain, then regenerates Cloud-Init image.
#
# Usage:
#   BulkChangeDNS.sh <start_vmid> <end_vmid> <dns_server> <dns_search_domain>
#
# Arguments:
#   start_vmid        - Starting VM ID
#   end_vmid          - Ending VM ID
#   dns_server        - DNS server address
#   dns_search_domain - DNS search domain
#
# Examples:
#   BulkChangeDNS.sh 400 430 8.8.8.8 example.com
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
__parse_args__ "start_vmid:vmid end_vmid:vmid dns_server:string dns_search_domain:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    change_dns_callback() {
        local vmid="$1"

        __vm_set_config__ "$vmid" --nameserver "$DNS_SERVER" --searchdomain "$DNS_SEARCH_DOMAIN"
        __vm_node_exec__ "$vmid" "qm cloudinit dump {vmid}" >/dev/null 2>&1 || true
    }

    __bulk_vm_operation__ --name "Change DNS" --report "$START_VMID" "$END_VMID" change_dns_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "DNS settings updated successfully!"
}

main

# Testing status:
#   - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
