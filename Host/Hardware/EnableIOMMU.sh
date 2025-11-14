#!/bin/bash
#
# EnableIOMMU.sh
#
# Enables VT-d/AMD-Vi (IOMMU) for PCI passthrough on Proxmox.
# Detects CPU vendor and configures GRUB accordingly.
#
# Usage:
#   EnableIOMMU.sh
#
# Examples:
#   EnableIOMMU.sh
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Enabling IOMMU for PCI passthrough"

    # Detect CPU vendor
    local cpu_vendor
    cpu_vendor=$(awk -F: '/vendor_id/ {print $2; exit}' /proc/cpuinfo | tr -d '[:space:]')

    local iommu_param
    if [[ "${cpu_vendor}" =~ GenuineIntel ]]; then
        iommu_param="intel_iommu=on"
        __info__ "Detected Intel CPU"
    elif [[ "${cpu_vendor}" =~ AuthenticAMD ]]; then
        iommu_param="amd_iommu=on"
        __info__ "Detected AMD CPU"
    else
        __warn__ "Could not detect CPU vendor, defaulting to intel_iommu=on"
        iommu_param="intel_iommu=on"
    fi

    # Update GRUB configuration
    local grub_file="/etc/default/grub"
    if [[ ! -f "$grub_file" ]]; then
        __err__ "GRUB configuration file not found: $grub_file"
        exit 1
    fi

    if grep -q "$iommu_param" "$grub_file"; then
        __ok__ "IOMMU parameter already present in GRUB"
    else
        __info__ "Adding $iommu_param to GRUB_CMDLINE_LINUX_DEFAULT"
        sed -i "s/\(^GRUB_CMDLINE_LINUX_DEFAULT=\".*\)\"/\1 ${iommu_param}\"/" "$grub_file"
        __ok__ "GRUB configuration updated"
    fi

    # Optional: Blacklist nouveau driver
    if __prompt_user_yn__ "Blacklist nouveau driver for NVIDIA GPU passthrough?"; then
        local blacklist_file="/etc/modprobe.d/blacklist.conf"
        if ! grep -q "blacklist nouveau" "$blacklist_file" 2>/dev/null; then
            {
                echo "blacklist nouveau"
                echo "options nouveau modeset=0"
            } >> "$blacklist_file"
            __ok__ "Nouveau driver blacklisted"
        else
            __info__ "Nouveau driver already blacklisted"
        fi
    fi

    # Update initramfs and GRUB
    __info__ "Updating initramfs"
    if update-initramfs -u -k all 2>&1; then
        __ok__ "Initramfs updated"
    else
        __err__ "Failed to update initramfs"
        exit 1
    fi

    __info__ "Updating GRUB configuration"
    if update-grub 2>&1; then
        __ok__ "GRUB updated"
    else
        __err__ "Failed to update GRUB"
        exit 1
    fi

    echo
    __ok__ "IOMMU enabled successfully!"
    __warn__ "REBOOT REQUIRED for changes to take effect"
    __info__ "Verify after reboot with: dmesg | grep -i iommu"
}

main

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
