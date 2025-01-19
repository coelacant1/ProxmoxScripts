#!/bin/bash
#
# FixDpkgLock.sh
#
# This script removes stale dpkg lock files and repairs interrupted dpkg operations
# on a Proxmox node. It then updates the apt cache.
#
# Usage:
#   ./FixDpkgLock.sh
#
# Example:
#   # To fix dpkg locks on the local Proxmox node
#   ./FixDpkgLock.sh
#
source "${UTILITYPATH}/Prompts.sh"

__check_root__          # Ensure script is run as root
__check_proxmox__       # Ensure we're on a Proxmox node

###############################################################################
# Remove stale locks
###############################################################################
rm -f "/var/lib/dpkg/lock-frontend"
rm -f "/var/lib/dpkg/lock"
rm -f "/var/lib/apt/lists/lock"
rm -f "/var/cache/apt/archives/lock"
rm -f "/var/lib/dpkg/lock"*

###############################################################################
# Reconfigure dpkg
###############################################################################
if ! dpkg --configure -a; then
  echo "Error: Failed to configure dpkg." >&2
  exit 1
fi

###############################################################################
# Update apt cache
###############################################################################
if ! apt-get update; then
  echo "Error: Failed to update apt cache." >&2
  exit 1
fi

echo "dpkg locks removed and apt cache updated successfully."
