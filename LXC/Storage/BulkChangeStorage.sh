#!/bin/bash
#
# BulkChangeStorageLXC.sh
#
# This script automates the process of updating the storage location specified in
# the configuration files of LXC containers on a Proxmox server.
# It is designed to bulk-update the storage paths for a range of LXC IDs
# from one storage identifier to another.
#
# Usage:
#   ./BulkChangeStorageLXC.sh <start_id> <end_id> <hostname> <current_storage> <new_storage>
#
# Arguments:
#   start_id         - The starting LXC ID for the operation.
#   end_id           - The ending LXC ID for the operation.
#   hostname         - The hostname of the Proxmox node where the LXCs are configured.
#   current_storage  - The current identifier of the storage used in the LXC config (e.g., 'local-lvm').
#   new_storage      - The new identifier of the storage to replace the current one (e.g., 'local-zfs').
#
# Example:
#   ./BulkChangeStorageLXC.sh 100 200 pve-node1 local-lvm local-zfs
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Check environment and parse arguments
###############################################################################
__check_root__
__check_proxmox__

if [ $# -lt 5 ]; then
    echo "Error: Missing arguments."
    echo "Usage: ./BulkChangeStorageLXC.sh <start_id> <end_id> <hostname> <current_storage> <new_storage>"
    exit 1
fi

START_ID="$1"
END_ID="$2"
HOST_NAME="$3"
CURRENT_STORAGE="$4"
NEW_STORAGE="$5"

###############################################################################
# Bulk update storage configuration in LXC containers
###############################################################################
for CT_ID in $(seq "$START_ID" "$END_ID"); do
    CONFIG_FILE="/etc/pve/nodes/${HOST_NAME}/lxc/${CT_ID}.conf"
    if [ -f "${CONFIG_FILE}" ]; then
        echo "Processing LXC ID: '${CT_ID}'"
        if grep -q "${CURRENT_STORAGE}" "${CONFIG_FILE}"; then
            sed -i "s/${CURRENT_STORAGE}/${NEW_STORAGE}/g" "${CONFIG_FILE}"
            echo " - Storage location changed from '${CURRENT_STORAGE}' to '${NEW_STORAGE}'."
        else
            echo " - '${CURRENT_STORAGE}' not found in config. No changes made."
        fi
    else
        echo "LXC ID: '${CT_ID}' does not exist (no config file). Skipping..."
    fi
done

echo "Bulk storage identifier update complete."
