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

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    if [[ $# -lt 1 ]]; then
        __err__ "Missing required argument: size_in_gb"
        echo "Usage: $0 <size_in_gb>"
        exit 64
    fi

    local test_size_gb="$1"

    # Validate input is a positive integer
    if ! [[ "$test_size_gb" =~ ^[0-9]+$ ]]; then
        __err__ "Size must be a positive integer"
        exit 1
    fi

    local test_size_mb=$((test_size_gb * 1024))

    __install_or_prompt__ "memtester"

    __warn__ "Testing ${test_size_gb}GB (${test_size_mb}MB) of RAM"
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

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
