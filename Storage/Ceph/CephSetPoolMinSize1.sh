#!/bin/bash
#
# CephSetPoolMinSize1.sh
#
# This script sets the 'min_size' parameter of a specified Ceph storage pool to 1.
# This allows the pool to operate with a single replica in degraded mode when necessary.
#
# Usage:
#   ./CephSetPoolMinSize1.sh <pool_name>
#
# Example:
#   # Sets the min_size to 1 for the 'mypool' storage pool
#   ./CephSetPoolMinSize1.sh mypool
#
source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Main
###############################################################################
__check_root__
__check_proxmox__

if [ -z "$1" ]; then
  echo "Error: No pool name provided."
  echo "Usage: $0 <pool_name>"
  exit 1
fi

POOL_NAME="$1"

echo "Setting min_size of pool '$POOL_NAME' to 1..."
ceph osd pool set "$POOL_NAME" min_size 1 --yes-i-really-mean-it

if [ $? -eq 0 ]; then
  echo "min_size has been set to 1 for pool '$POOL_NAME'."
else
  echo "Error: Failed to set min_size for pool '$POOL_NAME'."
  exit 1
fi
