#!/bin/bash
#
# CephWipeDisk.sh
#
# Securely erase a disk previously used by Ceph for removal or redeployment.
# This script will:
#   1. Prompt for confirmation to wipe the specified disk.
#   2. Remove any existing partition tables and Ceph signatures.
#   3. Optionally overwrite the disk with zeroes.
#
# Usage:
#   CephWipeDisk.sh /dev/sdX [--force]
#
# Example:
#   CephWipeDisk.sh /dev/sdb
#   CephWipeDisk.sh /dev/sdb --force     # Skip confirmation
#
# Notes:
# - This script must be run as root (sudo).
# - Make sure you specify the correct disk. This operation is destructive!
# - For non-interactive use (GUI, automation), --force flag is required
#

# Function Index:
#   - main
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

__parse_args__ "disk:path" "$@"

# Validate disk path
if [[ ! "$DISK" =~ ^/dev/ ]]; then
    __err__ "Invalid disk specified. Please provide a valid /dev/sdX path."
    exit 64
fi

__check_root__
__check_proxmox__

# Check and/or install required commands
__install_or_prompt__ "parted"
__install_or_prompt__ "util-linux" # Provides wipefs
__install_or_prompt__ "coreutils"

###############################################################################
# Confirmation
###############################################################################
__warn__ "DESTRUCTIVE: This will wipe and remove partitions/signatures on \"$DISK\""
__warn__ "This operation is destructive and cannot be undone"

# Safety check: Require --force in non-interactive mode
if [[ "${NON_INTERACTIVE:-0}" == "1" ]] && [[ $FORCE -eq 0 ]]; then
    __err__ "Destructive operation requires --force flag in non-interactive mode"
    __err__ "Usage: CephWipeDisk.sh $DISK --force"
    __err__ "Or add '--force' to parameters in GUI"
    exit 1
fi

# Prompt for confirmation (unless force is set)
if [[ $FORCE -eq 1 ]]; then
    __info__ "Force mode enabled - proceeding without confirmation"
elif ! __prompt_user_yn__ "Are you sure you want to continue?"; then
    __info__ "Aborting. No changes were made."
    exit 0
fi

###############################################################################
# Remove Partition Tables and Ceph Signatures
###############################################################################
__info__ "Removing partition tables and file system signatures on \"$DISK\"..."
wipefs --all --force "$DISK"

__info__ "Re-initializing partition label on \"$DISK\"..."
parted -s "$DISK" mklabel gpt

###############################################################################
# Optional Zero Fill
###############################################################################
if __prompt_user_yn__ "Would you like to overwrite the disk with zeroes?"; then
    __install_or_prompt__ "coreutils"
    echo "Overwriting \"$DISK\" with zeroes. This may take a while..."
    dd if=/dev/zero of="$DISK" bs=1M status=progress || {
        echo "Error: Failed to overwrite disk with zeroes."
        exit 5
    }
    sync
    echo "Zero-fill complete."
else
    echo "Skipping zero-fill as per user choice."
fi

###############################################################################
# Prompt to keep newly installed packages
###############################################################################
__prompt_keep_installed_packages__

###############################################################################
# Script notes:
###############################################################################
# Last checked: YYYY-MM-DD
#
# Changes:
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

