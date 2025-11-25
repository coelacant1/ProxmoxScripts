#!/bin/bash
#
# OnlineMemoryTest.sh
#
# Performs in-memory RAM test on a running Proxmox server using memtester.
#
# Usage:
#   OnlineMemoryTest.sh <size_in_gb>
#
# Arguments:
#   size_in_gb - Amount of RAM to test in gigabytes
#
# Examples:
#   OnlineMemoryTest.sh 1
#   OnlineMemoryTest.sh 2
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

__parse_args__ "test_size_gb:number" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    local test_size_mb=$((TEST_SIZE_GB * 1024))

    __install_or_prompt__ "memtester"

    __warn__ "Testing ${TEST_SIZE_GB}GB (${test_size_mb}MB) of RAM"
    __warn__ "This may temporarily reduce available memory for other processes"

    __info__ "Starting memory test"
    if memtester "${test_size_mb}M" 1 2>&1; then
        __ok__ "Memory test completed"
        __info__ "Check output above for any errors or failures"
    else
        __err__ "Memory test encountered errors"
        exit 1
    fi

    __prompt_keep_installed_packages__
}

main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: Pending validation
# - 2025-11-20: Updated to use ArgumentParser.sh
# - 2025-11-20: Validated - uses standard memtester (not Proxmox-specific)
#
# Fixes:
# -
#
# Known issues:
# - Pending validation
# -
#

