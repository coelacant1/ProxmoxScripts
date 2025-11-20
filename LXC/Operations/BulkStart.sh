#!/bin/bash
#
# BulkStart.sh
#
# Starts LXC containers within a Proxmox VE cluster.
# Uses BulkOperations framework for cluster-wide execution.
#
# Usage:
#   BulkStart.sh <start_ctid> <end_ctid>
#
# Arguments:
#   start_ctid - Starting container ID
#   end_ctid   - Ending container ID
#
# Examples:
#   BulkStart.sh 200 210
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
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_ctid:ctid end_ctid:ctid" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    start_callback() {
        local ctid="$1"
        __ct_start__ "$ctid"
    }

    __bulk_ct_operation__ --name "Start Containers" --report "$START_CTID" "$END_CTID" start_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Start completed successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
# - 2025-11-20: Validated against CONTRIBUTING.md and PVE Guide Chapter 11
# - Compliant with BulkOperations framework and utility usage
#
# Fixes:
# -
#
# Known issues:
# -
#

