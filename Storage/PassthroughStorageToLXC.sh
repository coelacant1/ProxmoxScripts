#!/bin/bash
#
# PassthroughStorageToLXC.sh
#
# Mounts host directory into LXC containers as shared storage.
#
# Usage:
#   PassthroughStorageToLXC.sh <host_dir> <permission> <ctid> [<ctid2>...]
#
# Arguments:
#   host_dir - Host directory path
#   permission - ro (read-only) or rw (read-write)
#   ctid - Container ID(s)
#
# Examples:
#   PassthroughStorageToLXC.sh /mnt/data rw 101 102
#   PassthroughStorageToLXC.sh /mnt/logs ro 101 102 103
#
# Function Index:
#   - process_container
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

__parse_args__ "host_dir:path permission:string ctids:vmid..." "$@"

# Validate permission
if [[ "$PERMISSION" != "ro" && "$PERMISSION" != "rw" ]]; then
    __err__ "Permission must be 'ro' or 'rw'"
    exit 64
fi

# Validate host directory
if [[ ! -d "$HOST_DIR" ]]; then
    __err__ "Host directory does not exist: $HOST_DIR"
    exit 1
fi

# --- process_container -------------------------------------------------------
process_container() {
    local ctid="$1"
    local host_dir="$2"
    local ro_flag="$3"

    if ! pct status "$ctid" &>/dev/null; then
        __warn__ "Container $ctid not found - skipping"
        return 1
    fi

    __update__ "Processing container: $ctid"

    # Check if unprivileged
    local unprivileged
    unprivileged=$(pct config "$ctid" | awk '/^unprivileged:/ {print $2}')

    if [[ "$unprivileged" == "1" ]]; then
        __warn__ "Container $ctid is unprivileged - converting to privileged"

        if pct set "$ctid" -unprivileged 0 --force 2>&1; then
            __ok__ "Converted to privileged"

            __update__ "Restarting container $ctid"
            pct stop "$ctid" 2>&1 || true
            sleep 2
            pct start "$ctid" 2>&1 || true
            sleep 3
        else
            __err__ "Failed to convert container $ctid"
            return 1
        fi
    fi

    # Find next available mount point index
    local next_mp_index=0
    while pct config "$ctid" | grep -q "^mp${next_mp_index}:"; do
        next_mp_index=$((next_mp_index + 1))
    done

    local mount_point="/mnt/$(basename "$host_dir")"

    __update__ "Mounting at mp${next_mp_index}: $mount_point (ro=$ro_flag)"

    if pct set "$ctid" -mp${next_mp_index} "${host_dir},mp=${mount_point},ro=${ro_flag},backup=0" 2>&1; then
        __ok__ "Mounted in container $ctid"
        return 0
    else
        __err__ "Failed to mount in container $ctid"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    local ro_flag=0
    [[ "$PERMISSION" == "ro" ]] && ro_flag=1

    __info__ "Passthrough Storage Configuration"
    __info__ "  Host directory: $HOST_DIR"
    __info__ "  Permission: $PERMISSION"
    __info__ "  Containers: ${CTIDS[*]}"

    if [[ "$ro_flag" == "0" ]]; then
        __warn__ "Read-write access will be granted"
    fi

    local mounted=0
    local failed=0

    for ctid in "${CTIDS[@]}"; do
        if process_container "$ctid" "$HOST_DIR" "$ro_flag"; then
            mounted=$((mounted + 1))
        else
            failed=$((failed + 1))
        fi
    done

    echo
    __info__ "Passthrough Summary:"
    __info__ "  Mounted: $mounted"
    [[ $failed -gt 0 ]] && __warn__ "  Failed: $failed" || __info__ "  Failed: $failed"

    [[ $failed -gt 0 ]] && exit 1
    __ok__ "Storage passthrough completed!"
}

main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Fixed arithmetic increment syntax (CONTRIBUTING.md Section 3.7)
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: Updated to use ArgumentParser.sh
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-24: Changed ((var += 1)) to var=$((var + 1)) for set -e compatibility
#
# Known issues:
# -
#

