#!/bin/bash
#
# CephSingleDrive.sh
#
# This script helps set up Ceph on a single-drive system, such as a home lab
# server, by removing the local-lvm partition and creating a Ceph OSD in the
# freed space.
#
# Usage:
#   CephSingleDrive.sh <create_osd|clear_local_lvm> [--force]
#
# Steps:
#   create_osd      - Bootstrap Ceph auth, create LVs, and prepare an OSD
#   clear_local_lvm - Delete the local-lvm (pve/data) volume (Destructive! Requires --force)
#
# Examples:
#   CephSingleDrive.sh create_osd
#   CephSingleDrive.sh clear_local_lvm --force
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
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
FORCE=0
positional_args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=1
            shift
            ;;
        -*)
            __err__ "Unknown argument: $1"
            exit 64
            ;;
        *)
            positional_args+=("$1")
            shift
            ;;
    esac
done

# Restore positional arguments for ArgumentParser
set -- "${positional_args[@]}"

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
    __warn__ "DESTRUCTIVE: This will remove the local-lvm 'pve/data' and all data within it!"

    # Safety check: Require --force in non-interactive mode
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]] && [[ $FORCE -eq 0 ]]; then
        __err__ "Destructive operation requires --force flag in non-interactive mode"
        __err__ "Usage: CephSingleDrive.sh clear_local_lvm --force"
        exit 1
    fi

    # Prompt for confirmation (unless force is set)
    if [[ $FORCE -eq 1 ]]; then
        __info__ "Force mode enabled - proceeding without confirmation"
    elif ! __prompt_user_yn__ "Are you sure you want to proceed? This will delete all data"; then
        __info__ "Aborting operation."
        return 0
    fi

    __info__ "Removing LVM volume 'pve/data'..."
    lvremove -y pve/data
    __ok__ "Local-lvm 'pve/data' removed successfully."
}

function create_osd() {
    echo "Creating OSD on this node..."
    echo "Bootstrapping Ceph auth..."
    ceph auth get client.bootstrap-osd >/var/lib/ceph/bootstrap-osd/ceph.keyring
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
