#!/bin/bash
#
# EnablePCIPassthroughLXC.sh
#
# A script to set up direct passthrough of a specific GPU or PCI device to one or more LXC containers in Proxmox,
# based on a user-supplied PCI device ID (e.g., "01:00.0"). This script does *not* enable access to all PCI devices.
#
# Usage:
#   EnablePCIPassthroughLXC.sh <PCI_DEVICE_ID> <CTID_1> [<CTID_2> ... <CTID_n>]
#
# Example:
#   EnablePCIPassthroughLXC.sh 01:00.0 100 101
#
# Notes:
#   1. Ensure VT-d/AMD-Vi (IOMMU) is enabled, and Proxmox is configured for PCI passthrough. This may involve:
#        - Editing /etc/default/grub to include "intel_iommu=on" or "amd_iommu=on"
#        - Updating initramfs or blacklisting certain driver modules
#   2. This script modifies each container’s config file: /etc/pve/lxc/<CTID>.conf
#   3. For GPU passthrough to LXC, you typically need:
#        - lxc.cgroup.devices.allow lines for the specific device (major:minor),
#        - a lxc.mount.entry line for binding the PCI device path inside the container.
#     This script will attempt a minimal approach; you may need additional entries for driver or node-level devices.
#   4. Only "privileged" LXC containers can easily use PCI passthrough. By default, this script will set the container(s) to privileged.
#   5. After making changes, stop and start each container for them to take effect (pct stop <CTID> && pct start <CTID>).
#
# Function Index:
#   - enable_pci_passthrough
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"

# Variable args: pci_device + CTIDs - hybrid parsing
if [[ $# -lt 2 ]]; then
    __err__ "Missing required arguments"
    echo "Usage: $0 <pci_device_id> <ctid_1> [<ctid_2> ...]"
    exit 64
fi

PCI_DEVICE_ID="$1"
shift
CTID_ARRAY=("$@")

# --- enable_pci_passthrough --------------------------------------------------
enable_pci_passthrough() {
    local ctid="$1"
    local pci_device="$2"
    local config_file="/etc/pve/lxc/${ctid}.conf"

    if [[ ! -f "$config_file" ]]; then
        __warn__ "Config file not found for CT $ctid - skipping"
        return 1
    fi

    __info__ "Configuring CT $ctid for PCI device $pci_device"

    # Force privileged container
    __update__ "Setting container to privileged mode"
    if ! pct set "${ctid}" --unprivileged 0 2>&1; then
        __err__ "Failed to set privileged mode"
        return 1
    fi

    # Add device access (NVIDIA GPU typically uses major 195)
    local device_allow="lxc.cgroup.devices.allow: c 195:* rwm"
    if ! grep -Fq "$device_allow" "${config_file}"; then
        echo "$device_allow" >> "${config_file}"
        __ok__ "Added device access permission"
    else
        __update__ "Device access already configured"
    fi

    # Add mount entry
    local mount_entry="lxc.mount.entry: /sys/bus/pci/devices/0000:${pci_device} /sys/bus/pci/devices/0000:${pci_device} none bind,optional,create=dir"
    if ! grep -Fq "$mount_entry" "${config_file}"; then
        echo "$mount_entry" >> "${config_file}"
        __ok__ "Added PCI device mount entry"
    else
        __update__ "Mount entry already exists"
    fi

    __ok__ "PCI passthrough configured for CT $ctid"
    return 0
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "PCI Passthrough Configuration"
    __info__ "  Device: $PCI_DEVICE_ID"
    __info__ "  Containers: ${CTID_ARRAY[*]}"

    echo
    __warn__ "This will set containers to privileged mode"

    if ! __prompt_yes_no__ "Configure PCI passthrough for ${#CTID_ARRAY[@]} container(s)?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    local success=0
    local failed=0

    for ctid in "${CTID_ARRAY[@]}"; do
        echo
        if ! pct config "${ctid}" &>/dev/null; then
            __err__ "Container $ctid does not exist - skipping"
            ((failed++))
            continue
        fi

        if enable_pci_passthrough "$ctid" "$PCI_DEVICE_ID"; then
            ((success++))
        else
            ((failed++))
        fi
    done

    echo
    __info__ "Summary:"
    __info__ "  Configured: $success"
    __info__ "  Failed: $failed"

    if [[ $success -gt 0 ]]; then
        echo
        __warn__ "Stop and start containers for changes to take effect"
        __info__ "Example: pct stop <ctid> && pct start <ctid>"
    fi

    [[ $failed -gt 0 ]] && exit 1
    __ok__ "PCI passthrough configuration completed!"
}

main "$@"

# Testing status:
#   - Updated to follow CONTRIBUTING.md guidelines
#   - ArgumentParser.sh sourced (hybrid for variable args)
#   - Pending validation
