#!/bin/bash
#
# EnablePCIPassthroughLXC.sh
#
# A script to set up direct passthrough of a specific GPU or PCI device to one or more LXC containers in Proxmox,
# based on a user-supplied PCI device ID (e.g., "01:00.0"). This script does *not* enable access to all PCI devices.
#
# Usage:
#   ./EnablePCIPassthroughLXC.sh <PCI_DEVICE_ID> <CTID_1> [<CTID_2> ... <CTID_n>]
#
# Example:
#   ./EnablePCIPassthroughLXC.sh 01:00.0 100 101
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
#   - enablePciPassthroughInContainerConfig
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Preliminary Checks
###############################################################################
__check_root__
__check_proxmox__

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <PCI_DEVICE_ID> <CTID_1> [<CTID_2> ... <CTID_n>]"
  exit 3
fi

PCI_DEVICE_ID="$1"
shift
CTID_ARRAY=("$@")

###############################################################################
# Functions
###############################################################################
function enablePciPassthroughInContainerConfig() {
  local ctid="$1"
  local configFile="/etc/pve/lxc/${ctid}.conf"

  if [[ ! -f "$configFile" ]]; then
    echo "Warning: \"${configFile}\" does not exist for CTID \"${ctid}\". Skipping..."
    return
  fi

  # Force privileged container
  pct set "${ctid}" --unprivileged 0

  # For NVIDIA GPUs, the major device number is typically 195 (c 195:* rwm).
  # Adjust if using another GPU vendor.
  if ! grep -q "lxc.cgroup.devices.allow: c 195:* rwm" "${configFile}"; then
    echo "lxc.cgroup.devices.allow: c 195:* rwm" >> "${configFile}"
  fi

  # Add a mount entry for the specific PCI device path
  local mountEntry="lxc.mount.entry: /sys/bus/pci/devices/0000:${PCI_DEVICE_ID} /sys/bus/pci/devices/0000:${PCI_DEVICE_ID} none bind,optional,create=dir"
  if ! grep -q "${mountEntry}" "${configFile}"; then
    echo "${mountEntry}" >> "${configFile}"
  fi

  echo "Configured PCI passthrough for container \"${ctid}\" using device \"${PCI_DEVICE_ID}\" (container is now privileged)."
}

###############################################################################
# Main Logic
###############################################################################
for ctid in "${CTID_ARRAY[@]}"; do
  if ! pct config "${ctid}" &>/dev/null; then
    echo "Error: Container \"${ctid}\" does not exist. Skipping..."
    continue
  fi

  enablePciPassthroughInContainerConfig "${ctid}"
done

echo "Done. Please stop and start each container for changes to take effect."
