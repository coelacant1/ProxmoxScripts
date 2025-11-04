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

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

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
        ((next_mp_index++))
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

    if [[ $# -lt 3 ]]; then
        __err__ "Missing required arguments"
        echo "Usage: $0 <host_dir> <permission> <ctid> [<ctid2>...]"
        exit 64
    fi

    local host_dir="$1"
    local permission="$2"
    shift 2
    local -a containers=("$@")

    # Validate host directory
    if [[ ! -d "$host_dir" ]]; then
        __err__ "Host directory does not exist: $host_dir"
        exit 1
    fi

    # Validate permission
    if [[ "$permission" != "ro" && "$permission" != "rw" ]]; then
        __err__ "Permission must be 'ro' or 'rw'"
        exit 1
    fi

    local ro_flag=0
    [[ "$permission" == "ro" ]] && ro_flag=1

    __info__ "Passthrough Storage Configuration"
    __info__ "  Host directory: $host_dir"
    __info__ "  Permission: $permission"
    __info__ "  Containers: ${containers[*]}"

    if [[ "$ro_flag" == "0" ]]; then
        __warn__ "Read-write access will be granted"
    fi

    local mounted=0
    local failed=0

    for ctid in "${containers[@]}"; do
        if process_container "$ctid" "$host_dir" "$ro_flag"; then
            ((mounted++))
        else
            ((failed++))
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

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
