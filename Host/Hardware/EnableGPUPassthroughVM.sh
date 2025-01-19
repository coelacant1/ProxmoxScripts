#!/bin/bash
#
# EnableGPUPassthroughVM.sh
#
# This script automates the configuration of GPU passthrough on a Proxmox host.
# It adjusts system configuration files to enable GPU passthrough based on the
# GPU type (NVIDIA or AMD) and the specific GPU IDs provided.
# The script modifies GRUB settings for IOMMU, blacklists conflicting drivers,
# and sets module options necessary for VFIO operation.
#
# Usage:
#   ./EnableGPUPassthroughVM.sh <gpu_type> <gpu_ids>
#
#   <gpu_type> : 'nvidia' or 'amd'
#   <gpu_ids>  : PCI IDs of the GPUs, formatted as 'vendor_id:device_id'
#
# Examples:
#   ./EnableGPUPassthroughVM.sh nvidia 10de:1e78
#   ./EnableGPUPassthroughVM.sh amd 1002:67df
#
# Suitable for users setting up virtual machines that require direct access
# to GPU hardware.
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Setup
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Validate Inputs
###############################################################################
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <gpu_type> <gpu_ids>"
  echo "Example: $0 nvidia 10de:1e78"
  echo "Example: $0 amd 1002:67df"
  exit 1
fi

GPU_TYPE="$1"
GPU_IDS="$2"

GRUB_CONFIG="/etc/default/grub"
BLACKLIST_CONFIG="/etc/modprobe.d/pveblacklist.conf"
IOMMU_CONFIG="/etc/modprobe.d/iommu_unsafe_interrupts.conf"
VFIO_CONFIG="/etc/modprobe.d/vfio.conf"

echo "Configuring GPU passthrough for \"$GPU_TYPE\"..."

###############################################################################
# Update GRUB Configuration
###############################################################################
if ! grep -q "iommu=on" "$GRUB_CONFIG"; then
  if [ "$GPU_TYPE" == "nvidia" ]; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on"/' "$GRUB_CONFIG"
  elif [ "$GPU_TYPE" == "amd" ]; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on"/' "$GRUB_CONFIG"
  else
    echo "Error: Invalid GPU type specified (\"$GPU_TYPE\"). Use 'nvidia' or 'amd'."
    exit 2
  fi
  echo "GRUB updated for \"$GPU_TYPE\". Please run 'update-grub' to apply changes."
else
  echo "GRUB is already configured for IOMMU."
fi

###############################################################################
# Blacklist NVIDIA Framebuffer (NVIDIA Only)
###############################################################################
if [ "$GPU_TYPE" == "nvidia" ]; then
  if [ ! -f "$BLACKLIST_CONFIG" ] || ! grep -q "blacklist nvidiafb" "$BLACKLIST_CONFIG"; then
    echo "blacklist nvidiafb" >> "$BLACKLIST_CONFIG"
    echo "NVIDIA framebuffer driver blacklisted."
  else
    echo "NVIDIA framebuffer blacklist entry already exists."
  fi
fi

###############################################################################
# Update IOMMU Unsafe Interrupts Config
###############################################################################
if [ ! -f "$IOMMU_CONFIG" ] || ! grep -q "allow_unsafe_interrupts=1" "$IOMMU_CONFIG"; then
  echo "options vfio_iommu_type1 allow_unsafe_interrupts=1" >> "$IOMMU_CONFIG"
  echo "IOMMU unsafe interrupts config updated."
else
  echo "IOMMU config already set."
fi

###############################################################################
# Update VFIO Configuration with GPU IDs
###############################################################################
if [ ! -f "$VFIO_CONFIG" ] || ! grep -q "options vfio-pci ids=$GPU_IDS disable_vga=1" "$VFIO_CONFIG"; then
  echo "options vfio-pci ids=$GPU_IDS disable_vga=1" >> "$VFIO_CONFIG"
  echo "VFIO config updated for GPU IDs \"$GPU_IDS\"."
else
  echo "VFIO config already set for these IDs."
fi

echo "GPU passthrough configuration complete for \"$GPU_TYPE\"."
