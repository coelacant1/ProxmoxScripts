#!/bin/bash
#
# CephSparsifyVMDisks.sh
#
# This script is designed to sparsify (compact) *all* RBD disk(s) associated with a specific VM
# in a specified Ceph storage pool. By zeroing out unused space in the VM and using the
# 'rbd sparsify' command, any zeroed blocks are reclaimed in the Ceph pool, making the space
# available for other uses.
#
# Usage:
#   ./CephSparsifyVMDisks.sh <pool_name> <vm_id>
#     pool_name - The name of the Ceph storage pool where the VM disk(s) reside.
#     vm_id     - The numeric ID of the VM whose disk(s) will be sparsified.
#
# Example:
#   ./CephSparsifyVMDisks.sh mypool 101
#
# Notes:
# 1. This script assumes that the RBD image names follow the convention "vm-<vm_id>-disk-<X>".
#    Adjust the grep pattern and/or logic if your naming differs.
# 2. Ensure you have already zeroed out unused space within the VM (e.g., sdelete -z in Windows
#    or fstrim in Linux) before running this script.
# 3. Verify you have the necessary permissions to run 'rbd sparsify' on the target pool/image.
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Check prerequisites
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Validate arguments
###############################################################################
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: Missing arguments."
  echo "Usage: $0 <pool_name> <vm_id>"
  exit 1
fi

POOL_NAME="$1"
VM_ID="$2"

echo "Querying all RBD disks for VM ID '${VM_ID}' in pool '${POOL_NAME}'..."

###############################################################################
# Main Logic
###############################################################################
images=$(rbd ls "${POOL_NAME}" | grep "vm-${VM_ID}-disk-")
if [ -z "${images}" ]; then
  echo "No disks found for VM ID '${VM_ID}' in pool '${POOL_NAME}'."
  exit 0
fi

echo "Found the following disk(s):"
echo "${images}"
echo

for imageName in ${images}; do
  echo "Attempting to sparsify disk '${POOL_NAME}/${imageName}'..."
  rbd sparsify "${POOL_NAME}/${imageName}"
  sparsifyExitCode=$?

  if [ ${sparsifyExitCode} -eq 0 ]; then
    echo "Successfully sparsified '${POOL_NAME}/${imageName}'."
  else
    echo "Failed to sparsify '${POOL_NAME}/${imageName}'."
    echo "Please check if the image name is correct and that you have the necessary permissions."
    # Uncomment the line below if one failure should stop the entire script:
    # exit ${sparsifyExitCode}
  fi
  echo
done

echo "Disk sparsification process is complete for VM ID '${VM_ID}' in pool '${POOL_NAME}'."
