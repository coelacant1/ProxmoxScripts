#!/bin/bash
#
# EnableX3DOptimization.sh
#
# A script to apply basic Linux-level configurations for AMD Ryzen X3D processors,
# specifically multi-CCD setups (e.g., 7900X3D, 7950X3D), where one CCD has extra 3D cache.
#
# Usage:
#   ./EnableX3DOptimization.sh
#
# Examples:
#   ./EnableX3DOptimization.sh
#     This will attempt to add 'amd_pstate=active' to /etc/default/grub (if not present),
#     enable kernel NUMA balancing, and prompt for a reboot.
#
# Description:
#   1. Instructs the user on relevant BIOS/UEFI settings for 3D V-cache processors.
#   2. Checks and enables the AMD P-State driver if the system kernel supports it.
#   3. Enables NUMA balancing via sysctl (optional, can help multi-CCD scheduling).
#   4. Provides basic guidance on CPU core/NUMA pinning for Proxmox VMs.
#
# NOTE: This script cannot directly configure BIOS/UEFI. Please follow the on-screen
#       instructions to make those changes manually.
#

source "${UTILITYPATH}/Prompts.sh"


###############################################################################
# Preliminary Checks
###############################################################################

# Check if script is run as root
__check_root__

# Gentle check for Proxmox environment (do not exit if not found)
if ! command -v pveversion &>/dev/null; then
  echo "Warning: 'pveversion' not found. This script is intended for Proxmox VE (but may still work on Debian-based systems)."
fi

###############################################################################
# BIOS / UEFI Recommendations
###############################################################################
echo "--------------------------------------------------------------------------------"
echo "                          BIOS / UEFI OPTIMIZATIONS                             "
echo "--------------------------------------------------------------------------------"
echo "1) Update BIOS/UEFI to the latest version:"
echo "   - Ensures you have the newest AMD AGESA firmware for improved scheduler and"
echo "     power management on multi-CCD Ryzen X3D CPUs."
echo
echo "2) Enable 'Preferred/Legacy CCD' or equivalent (if available):"
echo "   - Typically, the motherboard sets the 3D cache CCD as the 'preferred' by default."
echo "   - Consult your motherboard manual to confirm or modify CCD priority."
echo
echo "3) Check 'CPPC' or 'Collaborative Power and Performance Control' in BIOS:"
echo "   - Make sure CPPC is enabled for better OS-level scheduling and power states."
echo
echo "4) Precision Boost Overdrive (PBO) (Optional):"
echo "   - If you want more performance and have adequate cooling, enable PBO."
echo "   - Monitor thermals carefully."
echo
echo "These changes must be done manually in BIOS/UEFI. Press Enter to continue."
read -r

###############################################################################
# AMD P-State / Grub Configuration
###############################################################################
echo "--------------------------------------------------------------------------------"
echo "                         AMD P-STATE DRIVER CONFIGURATION                       "
echo "--------------------------------------------------------------------------------"

GRUB_CFG="/etc/default/grub"
AMD_PSTATE_PARAM="amd_pstate=active"

echo "Checking if \"${AMD_PSTATE_PARAM}\" is already in \"${GRUB_CFG}\" ..."
if grep -q "${AMD_PSTATE_PARAM}" "${GRUB_CFG}"; then
  echo "  - \"${AMD_PSTATE_PARAM}\" is already present in \"${GRUB_CFG}\"."
else
  echo "  - \"${AMD_PSTATE_PARAM}\" not found in \"${GRUB_CFG}\"."
  echo "Adding \"${AMD_PSTATE_PARAM}\" to GRUB_CMDLINE_LINUX_DEFAULT..."
  cp -v "${GRUB_CFG}" "${GRUB_CFG}.bak_$(date +%Y%m%d_%H%M%S)"
  sed -i "s/\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)/\1 ${AMD_PSTATE_PARAM}/" "${GRUB_CFG}"
  echo "  - \"${AMD_PSTATE_PARAM}\" added successfully. Updating grub..."
  update-grub
fi

echo
echo "If your kernel supports amd_pstate, this parameter helps the CPU scale frequency more"
echo "efficiently. If the kernel is older, this parameter may have no effect."
echo

###############################################################################
# Enable NUMA Balancing (Optional)
###############################################################################
echo "--------------------------------------------------------------------------------"
echo "                      NUMA BALANCING CONFIGURATION (OPTIONAL)                   "
echo "--------------------------------------------------------------------------------"

SYSCTL_CONF="/etc/sysctl.d/99-numa.conf"
if [[ ! -f "${SYSCTL_CONF}" ]]; then
  echo "Enabling automatic NUMA balancing via \"${SYSCTL_CONF}\""
  {
    echo "# Enable automatic NUMA balancing"
    echo "kernel.numa_balancing=1"
  } > "${SYSCTL_CONF}"
  sysctl --system
  echo "  - NUMA balancing enabled."
else
  echo "  - \"${SYSCTL_CONF}\" already exists. Please check it to ensure kernel.numa_balancing=1."
fi

echo
echo "Enabling NUMA balancing can help the kernel place processes on the CCD/NUMA node"
echo "with better memory locality. However, for some workloads with manual pinning, you"
echo "may prefer to keep this off."

###############################################################################
# Proxmox CPU Pinning / Scheduling Notes
###############################################################################
echo "--------------------------------------------------------------------------------"
echo "                PROXMOX CPU PINNING AND SCHEDULING RECOMMENDATIONS             "
echo "--------------------------------------------------------------------------------"
echo "1) Identify the 3D-cache CCD cores using 'lscpu -e' or 'hwloc/lstopo':"
echo "   - Typically, the lower-numbered cores or first NUMA node might be the 3D-cache CCD."
echo
echo "2) In the Proxmox UI or CLI, pin critical VMs/containers to those cores:"
echo "   Example CLI usage:"
echo "     qm set <VMID> --cpulimit <num> --cpuunits <num> --cores <num>"
echo "     qm set <VMID> --numa 1"
echo "   Or specify the exact cores, e.g.:"
echo "     qm set <VMID> --cpulist '0-7'  (if cores 0-7 are on the 3D-cache CCD)"
echo
echo "   This ensures latency-sensitive or cache-heavy workloads stay on the 3D-cache CCD."
echo
echo "3) Monitor with 'perf top', 'perf stat', or Proxmox graphs to confirm your tasks"
echo "   remain on the intended CCD. Adjust pinning or let NUMA balancing do the job."
echo

###############################################################################
# Final Instructions
###############################################################################
echo "--------------------------------------------------------------------------------"
echo "                               FINAL INSTRUCTIONS                               "
echo "--------------------------------------------------------------------------------"
echo "1) BIOS changes: Reboot into BIOS and apply the recommended settings."
echo "2) After returning to the OS, verify your GRUB and sysctl changes are active."
echo "3) Test your workloads, monitor CPU frequencies, thermals, and performance."
echo
echo "A reboot is required for the new GRUB settings to take effect."
echo
read -rp "Do you want to reboot now? [y/N]: " rebootNow
case "${rebootNow}" in
  [yY]|[yY][eE][sS])
    echo "Rebooting..."
    reboot
    ;;
  *)
    echo "Reboot skipped. Please remember to reboot later for changes to apply."
    ;;
esac
