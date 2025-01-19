#!/bin/bash
#
# OptimizeNestedVirtualization.sh
#
# A script to enable nested virtualization on a Proxmox node.
# This script detects whether you have an Intel or AMD CPU and adjusts
# kernel module parameters to enable nested virtualization. It then reloads
# the necessary modules and verifies that nested virtualization is enabled.
#
# Usage:
#   ./OptimizeNestedVirtualization.sh
#
# Examples:
#   ./OptimizeNestedVirtualization.sh
#     - Enables nested virtualization for the CPU vendor detected on this Proxmox node.
#
# Note:
#   After running this script, you may need to set the CPU type to "host" for any
#   VM that you want to run nested hypervisors inside of. For example:
#       qm set <VMID> --cpu host
#   A reboot of the Proxmox host might be required in some cases.
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Preliminary Checks
###############################################################################
__check_root__
__check_proxmox__
__install_or_prompt__ "lscpu"

CPU_VENDOR="$(lscpu | awk -F: '/Vendor ID:/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')"
if [[ -z "${CPU_VENDOR}" ]]; then
  echo "Error: Unable to detect CPU vendor."
  exit 3
fi

echo "Detected CPU vendor: \"${CPU_VENDOR}\""

###############################################################################
# Main Script Logic
###############################################################################
if [[ "${CPU_VENDOR}" =~ [Ii]ntel ]]; then
  echo "Enabling nested virtualization for Intel CPU..."
  echo "options kvm-intel nested=Y" > /etc/modprobe.d/kvm-intel.conf
  if lsmod | grep -q kvm_intel; then
    echo "Reloading kvm_intel module..."
    rmmod kvm_intel
  fi
  modprobe kvm_intel

  NESTED_STATUS="$(cat /sys/module/kvm_intel/parameters/nested 2>/dev/null)"
  if [[ "${NESTED_STATUS}" == "Y" || "${NESTED_STATUS}" == "1" ]]; then
    echo "Nested virtualization enabled successfully for Intel CPU."
  else
    echo "Warning: Unable to confirm nested virtualization is enabled (check manually)."
  fi

elif [[ "${CPU_VENDOR}" =~ [Aa][Mm][Dd] ]]; then
  echo "Enabling nested virtualization for AMD CPU..."
  echo "options kvm-amd nested=1" > /etc/modprobe.d/kvm-amd.conf
  if lsmod | grep -q kvm_amd; then
    echo "Reloading kvm_amd module..."
    rmmod kvm_amd
  fi
  modprobe kvm_amd

  NESTED_STATUS="$(cat /sys/module/kvm_amd/parameters/nested 2>/dev/null)"
  if [[ "${NESTED_STATUS}" == "1" || "${NESTED_STATUS}" == "Y" ]]; then
    echo "Nested virtualization enabled successfully for AMD CPU."
  else
    echo "Warning: Unable to confirm nested virtualization is enabled (check manually)."
  fi

else
  echo "Warning: Unknown CPU vendor detected. Attempting Intel approach by default..."
  echo "options kvm-intel nested=Y" > /etc/modprobe.d/kvm-intel.conf
  if lsmod | grep -q kvm_intel; then
    rmmod kvm_intel
  fi
  modprobe kvm_intel
fi

###############################################################################
# Post-Script Instructions
###############################################################################
echo "Done. If nested virtualization is still not working, please reboot the node."
echo "Also, ensure your VMs' CPU type is set to 'host' for nested guests."

__prompt_keep_installed_packages__
