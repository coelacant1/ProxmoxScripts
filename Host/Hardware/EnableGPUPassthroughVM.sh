#!/bin/bash
#
# EnableGPUPassthroughVM.sh
#
# Automates GPU passthrough configuration for Proxmox VMs. Configures IOMMU,
# blacklists conflicting drivers, and sets up VFIO for GPU passthrough.
#
# Usage:
#   EnableGPUPassthroughVM.sh <gpu_type> <gpu_ids>
#
# Arguments:
#   gpu_type - GPU type: 'nvidia' or 'amd'
#   gpu_ids  - PCI IDs formatted as 'vendor_id:device_id'
#
# Examples:
#   EnableGPUPassthroughVM.sh nvidia 10de:1e78
#   EnableGPUPassthroughVM.sh amd 1002:67df
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

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "gpu_type:string gpu_ids:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    local grub_config="/etc/default/grub"
    local blacklist_config="/etc/modprobe.d/pveblacklist.conf"
    local iommu_config="/etc/modprobe.d/iommu_unsafe_interrupts.conf"
    local vfio_config="/etc/modprobe.d/vfio.conf"

    # Validate GPU type
    if [[ "$GPU_TYPE" != "nvidia" ]] && [[ "$GPU_TYPE" != "amd" ]]; then
        __err__ "Invalid GPU type: $GPU_TYPE (must be 'nvidia' or 'amd')"
        exit 64
    fi

    __info__ "Configuring GPU passthrough for $GPU_TYPE ($GPU_IDS)"

    # Update GRUB configuration
    if ! grep -q "iommu=on" "$grub_config"; then
        if [[ "$GPU_TYPE" == "nvidia" ]]; then
            sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on"/' "$grub_config"
        else
            sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on"/' "$grub_config"
        fi
        __ok__ "GRUB updated for $GPU_TYPE"
        __update__ "Run 'update-grub' to apply changes"
    else
        __update__ "GRUB already configured for IOMMU"
    fi

    # Blacklist NVIDIA framebuffer (NVIDIA only)
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        if [[ ! -f "$blacklist_config" ]] || ! grep -q "blacklist nvidiafb" "$blacklist_config"; then
            echo "blacklist nvidiafb" >>"$blacklist_config"
            __ok__ "NVIDIA framebuffer driver blacklisted"
        else
            __update__ "NVIDIA framebuffer already blacklisted"
        fi
    fi

    # Update IOMMU unsafe interrupts config
    if [[ ! -f "$iommu_config" ]] || ! grep -q "allow_unsafe_interrupts=1" "$iommu_config"; then
        echo "options vfio_iommu_type1 allow_unsafe_interrupts=1" >>"$iommu_config"
        __ok__ "IOMMU unsafe interrupts configured"
    else
        __update__ "IOMMU config already set"
    fi

    # Update VFIO configuration with GPU IDs
    if [[ ! -f "$vfio_config" ]] || ! grep -q "options vfio-pci ids=$GPU_IDS disable_vga=1" "$vfio_config"; then
        echo "options vfio-pci ids=$GPU_IDS disable_vga=1" >>"$vfio_config"
        __ok__ "VFIO configured for GPU IDs: $GPU_IDS"
    else
        __update__ "VFIO config already set for these IDs"
    fi

    __ok__ "GPU passthrough configuration complete!"
    __warn__ "Reboot required for changes to take effect"
}

main

# Testing status:
#   - Updated to follow CONTRIBUTING.md guidelines
#   - Pending validation
