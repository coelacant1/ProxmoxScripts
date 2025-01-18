#!/bin/bash
#
# CephSingleDrive.sh
#
# This script helps set up Ceph on a single-drive system, such as a home lab
# server, by removing the local-lvm partition and creating a Ceph OSD in the
# freed space.
#
# Usage:
#   ./CephSingleDrive.sh <create_osd|clear_local_lvm>
#
# Steps:
#   create_osd      - Bootstrap Ceph auth, create LVs, and prepare an OSD
#   clear_local_lvm - Delete the local-lvm (pve/data) volume (Destructive!)
#
# Examples:
#   ./CephSingleDrive.sh create_osd
#   ./CephSingleDrive.sh clear_local_lvm
#
# Function Index:
#   - clear_local_lvm
#   - create_osd
#

source "$UTILITIES"

check_root
check_proxmox

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
STEP="$1"

if [ -z "$STEP" ]; then
    echo "Usage: $0 <create_osd|clear_local_lvm>"
    exit 1
fi

case "$STEP" in
    create_osd)
        create_osd
        ;;
    clear_local_lvm)
        clear_local_lvm
        ;;
    *)
        echo "Invalid step. Use 'create_osd' or 'clear_local_lvm'."
        exit 2
        ;;
esac
