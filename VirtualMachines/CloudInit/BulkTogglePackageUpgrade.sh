#!/bin/bash
#
# BulkTogglePackageUpgrade.sh
#
# Enables or disables automatic package upgrades for a range of virtual machines (VMs) within a Proxmox VE environment.
# Updates Cloud-Init configuration to set or unset automatic package upgrades.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   BulkTogglePackageUpgrade.sh <start_vm_id> <end_vm_id> <enable|disable>
#
# Arguments:
#   start_vm_id     - The ID of the first VM to update.
#   end_vm_id       - The ID of the last VM to update.
#   enable|disable  - Set to 'enable' to enable automatic upgrades, or 'disable' to disable them.
#
# Examples:
#   BulkTogglePackageUpgrade.sh 400 430 enable
#   BulkTogglePackageUpgrade.sh 400 430 disable
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
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid action:choice(enable,disable)" "$@"

# Determine auto upgrade setting
if [[ "$ACTION" == "enable" ]]; then
    AUTO_UPGRADE_SETTING="1"
else
    AUTO_UPGRADE_SETTING="0"
fi

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk toggle package upgrade (${ACTION}): VMs ${START_VMID} to ${END_VMID} (cluster-wide)"

    # Local callback for bulk operation
    toggle_upgrade_callback() {
        local vmid="$1"
        local node

        node=$(__get_vm_node__ "$vmid")

        if [[ -z "$node" ]]; then
            __update__ "VM ${vmid} not found in cluster"
            return 1
        fi

        __update__ "Setting automatic package upgrade to '${ACTION}' for VM ${vmid}..."

        if qm set "$vmid" --ciupgrade "$AUTO_UPGRADE_SETTING" --node "$node" 2>/dev/null; then
            qm cloudinit update "$vmid" --node "$node" 2>/dev/null || true
            return 0
        else
            __update__ "Failed to set package upgrade for VM ${vmid}"
            return 1
        fi
    }

    # Use BulkOperations framework
    __bulk_vm_operation__ --name "Package Upgrade Toggle" --report "$START_VMID" "$END_VMID" toggle_upgrade_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Package upgrade settings updated successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-20: Updated to use ArgumentParser and BulkOperations framework
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-24: Fixed incorrect qm command - changed '--set "packages_auto_upgrade="'
#   to '--ciupgrade' per PVE Guide documentation
# - 2025-11-24: Fixed incorrect command - changed 'qm cloudinit dump' to
#   'qm cloudinit update' to properly regenerate Cloud-Init config per PVE Guide
# - 2025-11-24: Removed incorrect '--ciuser root' parameter
#
# Known issues:
# -
#

