#!/bin/bash
#
# SetPoolSize1.sh
#
# Sets the size parameter of a Ceph pool to 1, disabling data replication.
#
# Usage:
#   SetPoolSize1.sh <pool_name>
#
# Arguments:
#   pool_name - Name of the Ceph storage pool
#
# Examples:
#   SetPoolSize1.sh testpool
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "pool_name:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __update__ "Setting size=1 for pool '$POOL_NAME'"
    if ceph osd pool set "$POOL_NAME" size 1 --yes-i-really-mean-it 2>&1; then
        __ok__ "size set to 1 for pool '$POOL_NAME'"
    else
        __err__ "Failed to set size for pool '$POOL_NAME'"
    fi
}

main

# Testing status:
#   - Pending validation
