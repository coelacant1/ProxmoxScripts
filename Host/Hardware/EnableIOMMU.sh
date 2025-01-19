#!/bin/bash
#
# EnableIOMMU.sh
#
# Ensures VT-d/AMD-Vi (IOMMU) is enabled on a Proxmox host, preparing it for
# PCI passthrough. Specifically:
#   1. Detects if CPU is Intel or AMD.
#   2. Updates /etc/default/grub to include the appropriate IOMMU parameter
#      ("intel_iommu=on" or "amd_iommu=on").
#   3. Optionally blacklists the nouveau driver if desired.
#   4. Updates initramfs and Grub configuration.
#
# Usage:
#   ./EnableIOMMU.sh
#
# Example:
#   ./EnableIOMMU.sh
#
# Note:
#   - You must reboot after running this script for changes to take effect.
#   - For GPU passthrough, consider loading VFIO modules at boot and mapping
#     specific PCI device IDs as needed.
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Preliminary Checks
###############################################################################
__check_root__
__check_proxmox__
__install_or_prompt__ "update-grub"  # Provided by grub-common
__install_or_prompt__ "update-initramfs"  # Provided by initramfs-tools

###############################################################################
# Detect CPU Vendor
###############################################################################
CPU_VENDOR="$(awk -F: '/vendor_id/ {print $2; exit}' /proc/cpuinfo | tr -d '[:space:]')"
if [[ "${CPU_VENDOR}" =~ "GenuineIntel" ]]; then
  IOMMU_PARAM="intel_iommu=on"
elif [[ "${CPU_VENDOR}" =~ "AuthenticAMD" ]]; then
  IOMMU_PARAM="amd_iommu=on"
else
  echo "Warning: Could not detect Intel or AMD CPU. Defaulting to intel_iommu=on."
  IOMMU_PARAM="intel_iommu=on"
fi

echo "Detected CPU vendor: \"${CPU_VENDOR}\""
echo "Will enable IOMMU parameter: \"${IOMMU_PARAM}\""

###############################################################################
# Update /etc/default/grub
###############################################################################
GRUB_FILE="/etc/default/grub"
if [[ ! -f "${GRUB_FILE}" ]]; then
  echo "Error: \"${GRUB_FILE}\" not found. Cannot update grub configuration."
  exit 1
fi

if grep -q "${IOMMU_PARAM}" "${GRUB_FILE}"; then
  echo "IOMMU parameter (\"${IOMMU_PARAM}\") already present in \"${GRUB_FILE}\"."
else
  echo "Adding \"${IOMMU_PARAM}\" to GRUB_CMDLINE_LINUX_DEFAULT..."
  sed -i "s/\(^GRUB_CMDLINE_LINUX_DEFAULT=\".*\)\"/\1 ${IOMMU_PARAM}\"/" "${GRUB_FILE}"
fi

###############################################################################
# Optional: Blacklist nouveau Driver
###############################################################################
read -r -p "Do you want to blacklist the 'nouveau' driver for NVIDIA GPU passthrough? [y/N] " USER_CHOICE
if [[ "${USER_CHOICE}" =~ ^[Yy]$ ]]; then
  MODPROBE_BLACKLIST="/etc/modprobe.d/blacklist.conf"
  if ! grep -q "blacklist nouveau" "${MODPROBE_BLACKLIST}" 2>/dev/null; then
    {
      echo "blacklist nouveau"
      echo "options nouveau modeset=0"
    } >> "${MODPROBE_BLACKLIST}"
    echo "NVIDIA 'nouveau' driver has been blacklisted in \"${MODPROBE_BLACKLIST}\"."
  else
    echo "'nouveau' driver is already blacklisted."
  fi
fi

###############################################################################
# Update initramfs and Grub
###############################################################################
echo "Updating initramfs..."
update-initramfs -u -k all

echo "Updating Grub configuration..."
update-grub

echo "-----------------------------------------------------------------------"
echo "IOMMU has been enabled with parameter: \"${IOMMU_PARAM}\""
echo "If you chose to blacklist nouveau, that change has been applied."
echo "Please reboot the system for changes to take effect."
echo "-----------------------------------------------------------------------"

__prompt_keep_installed_packages__
