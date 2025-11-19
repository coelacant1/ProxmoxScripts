#!/bin/bash
#
# EnableX3DOptimization.sh
#
# Applies Linux-level optimizations for AMD Ryzen X3D processors (multi-CCD setups
# like 7900X3D, 7950X3D). Enables AMD P-State driver and NUMA balancing.
#
# Usage:
#   EnableX3DOptimization.sh
#
# Examples:
#   EnableX3DOptimization.sh
#
# Notes:
#   - Adds 'amd_pstate=active' to GRUB configuration
#   - Enables kernel NUMA balancing for better multi-CCD scheduling
#   - Provides guidance on BIOS settings and CPU pinning
#   - Cannot configure BIOS/UEFI directly
#   - Reboot required for changes to take effect
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

    # Gentle check for Proxmox environment
    if ! command -v pveversion &>/dev/null; then
        __warn__ "'pveversion' not found - script intended for Proxmox VE"
    fi

    # BIOS/UEFI recommendations
    __info__ "BIOS/UEFI Optimizations for AMD Ryzen X3D"
    echo
    echo "1) Update BIOS/UEFI to latest version"
    echo "   - Ensures newest AMD AGESA firmware for improved scheduler"
    echo
    echo "2) Enable 'Preferred/Legacy CCD' or equivalent (if available)"
    echo "   - Sets 3D cache CCD as preferred"
    echo
    echo "3) Check 'CPPC' (Collaborative Power and Performance Control)"
    echo "   - Enable for better OS-level scheduling and power states"
    echo
    echo "4) Precision Boost Overdrive (PBO) - Optional"
    echo "   - Enable for more performance with adequate cooling"
    echo
    __warn__ "These changes must be done manually in BIOS/UEFI"
    echo
    read -rp "Press Enter to continue..."

    # AMD P-State / GRUB configuration
    echo
    __info__ "Configuring AMD P-State Driver"

    local grub_cfg="/etc/default/grub"
    local amd_pstate_param="amd_pstate=active"

    if grep -q "${amd_pstate_param}" "${grub_cfg}"; then
        __update__ "AMD P-State already configured in GRUB"
    else
        __update__ "Adding AMD P-State parameter to GRUB"
        cp -v "${grub_cfg}" "${grub_cfg}.bak_$(date +%Y%m%d_%H%M%S)"
        sed -i "s/\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)/\1 ${amd_pstate_param}/" "${grub_cfg}"
        __ok__ "AMD P-State parameter added"
        __update__ "Updating GRUB..."
        update-grub
    fi

    echo
    __info__ "AMD P-State helps CPU scale frequency more efficiently"

    # Enable NUMA balancing
    echo
    __info__ "Configuring NUMA Balancing (Optional)"

    local sysctl_conf="/etc/sysctl.d/99-numa.conf"
    if [[ ! -f "${sysctl_conf}" ]]; then
        {
            echo "# Enable automatic NUMA balancing"
            echo "kernel.numa_balancing=1"
        } >"${sysctl_conf}"
        sysctl --system >/dev/null 2>&1
        __ok__ "NUMA balancing enabled"
    else
        __update__ "NUMA balancing config already exists"
    fi

    echo
    __info__ "NUMA balancing helps kernel place processes on correct CCD"

    # Proxmox CPU pinning recommendations
    echo
    __info__ "Proxmox CPU Pinning Recommendations"
    echo
    echo "1) Identify 3D-cache CCD cores using 'lscpu -e' or 'hwloc/lstopo'"
    echo
    echo "2) Pin critical VMs/containers to those cores:"
    echo "   qm set <VMID> --cpulimit <num> --cpuunits <num> --cores <num>"
    echo "   qm set <VMID> --numa 1"
    echo "   qm set <VMID> --cpulist '0-7'  (if cores 0-7 are 3D-cache CCD)"
    echo
    echo "3) Monitor with 'perf top', 'perf stat', or Proxmox graphs"
    echo

    # Final instructions
    echo
    __warn__ "Reboot required for GRUB changes to take effect"
    echo

    if __prompt_user_yn__ "Reboot now?"; then
        __info__ "Rebooting..."
        reboot
    else
        __info__ "Reboot skipped - remember to reboot later"
    fi
}

main

# Testing status:
#   - Updated to follow CONTRIBUTING.md guidelines
#   - Pending validation
