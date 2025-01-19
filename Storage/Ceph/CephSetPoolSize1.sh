#!/bin/bash
#
# CephSetPoolSize1.sh
#
# This script sets the 'size' parameter of a specified Ceph storage pool to 1, disabling data replication.
#
# Usage:
#   ./CephSetPoolSize1.sh <pool_name>
#
# Example:
#   ./CephSetPoolSize1.sh testpool
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Checks and setup
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Main
###############################################################################
POOL_NAME="$1"

if [ -z "$POOL_NAME" ]; then
  echo "Usage: $0 <pool_name>"
  exit 1
fi

echo "Setting size of pool \"$POOL_NAME\" to 1..."
ceph osd pool set "$POOL_NAME" size 1 --yes-i-really-mean-it
if [ $? -eq 0 ]; then
  echo "size has been set to 1 for pool \"$POOL_NAME\"."
else
  echo "Failed to set size for pool \"$POOL_NAME\". Please check the pool name and your permissions."
  exit 1
fi
