#!/bin/bash
#
# CephSingleDrive.sh
#
# This script helps set up Ceph on a single-drive system, such as a home lab
# server, by removing the local-lvm partition and creating a Ceph OSD in the
# freed space.
#
# Usage:
#   CephSingleDrive.sh <create_osd|clear_local_lvm>
#
# Steps:
#   create_osd      - Bootstrap Ceph auth, create LVs, and prepare an OSD
#   clear_local_lvm - Delete the local-lvm (pve/data) volume (Destructive!)
#
# Examples:
#   CephSingleDrive.sh create_osd
#   CephSingleDrive.sh clear_local_lvm
#
# Function Index:
#   - clear_local_lvm
#   - create_osd
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "step:string" "$@"

# Validate step argument
if [[ "$STEP" != "create_osd" && "$STEP" != "clear_local_lvm" ]]; then
    __err__ "Invalid step: $STEP (must be: create_osd or clear_local_lvm)"
    exit 64
fi

__check_root__
__check_proxmox__

###############################################################################
# Functions
###############################################################################
function clear_local_lvm() {
    echo "WARNING: This will remove the local-lvm 'pve/data' and all data within it!"
    read -p "Are you sure you want to proceed? [yes/NO]: " confirmation
    case "$confirmation" in
        yes|YES)
            echo "Removing LVM volume 'pve/data'..."
            lvremove -y pve/data
            echo "Local-lvm 'pve/data' removed successfully."
            ;;
        *)
            echo "Aborting operation."
            ;;
    esac
}

function create_osd() {
    echo "Creating OSD on this node..."
    echo "Bootstrapping Ceph auth..."
    ceph auth get client.bootstrap-osd > /var/lib/ceph/bootstrap-osd/ceph.keyring
    echo "Bootstrap auth completed."

    echo "Creating new logical volume with all remaining free space..."
    lvcreate -l 100%FREE -n vz pve
    echo "Logical volume 'pve/vz' created."

    echo "Preparing and activating the logical volume for OSD..."
    ceph-volume lvm create --data pve/vz
    echo "OSD prepared and activated."
}

###############################################################################
# Main
###############################################################################
case "$STEP" in
    create_osd)
        create_osd
        ;;
    clear_local_lvm)
        clear_local_lvm
        ;;
esac
