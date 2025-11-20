#!/bin/bash
#
# BulkRemoveRDPConnection.sh
#
# This script searches for Guacamole RDP connections whose name contains a given
# substring (or matches a VMID range) and removes them from Apache Guacamole.
#
# The script supports two modes:
#   1. Search by substring - removes all connections with names containing the substring
#   2. Search by VMID range - removes connections for VMs in a specific VMID range
#
# Usage:
#   BulkRemoveRDPConnection.sh GUAC_SERVER_URL SEARCH_SUBSTRING [DATA_SOURCE] [--force]
#   BulkRemoveRDPConnection.sh GUAC_SERVER_URL --vmid-range START_VMID END_VMID [DATA_SOURCE] [--force]
#
# Examples:
#   BulkRemoveRDPConnection.sh "http://192.168.1.10:8080/guacamole" "TestVM"
#   BulkRemoveRDPConnection.sh "http://guac.example.com:8080/guacamole" "Clone" mysql --force
#   BulkRemoveRDPConnection.sh "http://guac.example.com:8080/guacamole" --vmid-range 100 110 mysql --force
#
# Notes:
#   - This script expects a valid Guacamole auth token in /tmp/cc_pve/guac_token.
#   - Run GetGuacToken.sh beforehand to store the auth token for the Guacamole server.
#   - Use with caution as deleted connections cannot be recovered.
#   - The script will prompt for confirmation before deleting connections (unless --force is used).
#   - For non-interactive use (GUI, automation), --force flag is required.
#
# Function Index:
#   - delete_connection
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__install_or_prompt__ "jq"

# Parse --force flag if present
FORCE=0
args=()
for arg in "$@"; do
    if [[ "$arg" == "--force" ]]; then
        FORCE=1
    else
        args+=("$arg")
    fi
done
set -- "${args[@]}"

# Complex argument parsing - hybrid approach
if [[ $# -lt 2 ]]; then
    echo "Usage:"
    echo "  $0 GUAC_SERVER_URL SEARCH_SUBSTRING [DATA_SOURCE] [--force]"
    echo "  $0 GUAC_SERVER_URL --vmid-range START_VMID END_VMID [DATA_SOURCE] [--force]"
    exit 64
fi

GUAC_URL="$1"
MODE="substring"

if [[ "$2" == "--vmid-range" ]]; then
    MODE="vmid-range"
    if [[ $# -lt 4 ]]; then
        echo "Error: Missing required arguments for VMID range mode."
        echo "Usage: $0 GUAC_SERVER_URL --vmid-range START_VMID END_VMID [DATA_SOURCE]"
        exit 64
    fi
    START_VMID="$3"
    END_VMID="$4"
    GUAC_DATA_SOURCE="${5:-mysql}"
else
    SEARCH_SUBSTRING="$2"
    GUAC_DATA_SOURCE="${3:-mysql}"
fi

###############################################################################
# delete_connection - Deletes a single connection from Guacamole
###############################################################################
delete_connection() {
    local conn_id="$1"
    local conn_name="$2"
    local guac_url="$3"
    local data_source="$4"
    local auth_token="$5"

    echo "  Deleting connection: '$conn_name' (ID: $conn_id)"

    deleteResponse=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
        "${guac_url}/api/session/data/${data_source}/connections/${conn_id}?token=${auth_token}")

    if [[ "$deleteResponse" -eq 200 || "$deleteResponse" -eq 204 ]]; then
        echo "    Successfully deleted connection '$conn_name' (ID: $conn_id)"
        return 0
    else
        echo "    Failed to delete connection '$conn_name' (ID: $conn_id) - HTTP status: $deleteResponse"
        return 1
    fi
}

###############################################################################
# Main Logic
###############################################################################

# Ensure a Guacamole auth token exists
if [[ ! -f "/tmp/cc_pve/guac_token" ]]; then
    echo "Error: No Guacamole auth token found in /tmp/cc_pve/guac_token."
    echo "Please run GetGuacToken.sh first."
    exit 1
fi

AUTH_TOKEN="$(cat /tmp/cc_pve/guac_token)"
echo "Using data source: '$GUAC_DATA_SOURCE'"

###############################################################################
# Retrieve the connection tree from Guacamole
###############################################################################
echo "Retrieving connection tree from Guacamole..."
connectionsJson="$(curl -s -X GET \
    "${GUAC_URL}/api/session/data/${GUAC_DATA_SOURCE}/connectionGroups/ROOT/tree?token=${AUTH_TOKEN}")"

if [[ -z "$connectionsJson" ]]; then
    echo "Error: Could not retrieve connection tree from Guacamole."
    exit 1
fi

###############################################################################
# Filter matching connections
###############################################################################
if [[ "$MODE" == "vmid-range" ]]; then
    echo "Searching for connections with VMIDs in range $START_VMID to $END_VMID..."

    # Build list of VM names for the VMID range
    vmNames=()
    for ((vmid = START_VMID; vmid <= END_VMID; vmid++)); do
        vmName="$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
            | jq -r --arg VMID "$vmid" '.[] | select(.vmid == ($VMID|tonumber)) | .name')"

        if [[ -n "$vmName" && "$vmName" != "null" ]]; then
            vmNames+=("$vmName")
        else
            vmNames+=("VM-$vmid")
        fi
    done

    # Create a jq array of VM names
    vmNamesJson=$(printf '%s\n' "${vmNames[@]}" | jq -R . | jq -s .)

    matchingConnections=$(echo "$connectionsJson" | jq -r \
        --argjson names "$vmNamesJson" '
        [ (.childConnections // [])[]
          | select(.name as $n | $names | any(. == $n))
          | { id: .identifier, name: .name } ]
        ')
else
    echo "Searching for connections with names containing '$SEARCH_SUBSTRING'..."
    matchingConnections=$(echo "$connectionsJson" | jq -r \
        --arg SUBSTR "$SEARCH_SUBSTRING" '
        [ (.childConnections // [])[]
          | select(.name | test($SUBSTR; "i"))
          | { id: .identifier, name: .name } ]
        ')
fi

# Check if any matches were found
connectionCount=$(echo "$matchingConnections" | jq 'length')
if [[ "$connectionCount" -eq 0 ]]; then
    if [[ "$MODE" == "vmid-range" ]]; then
        echo "No connections found for VMID range $START_VMID to $END_VMID."
    else
        echo "No connections found matching '$SEARCH_SUBSTRING'."
    fi
    exit 0
fi

echo ""
echo "Found $connectionCount matching connection(s):"
echo "$matchingConnections" | jq -r '.[] | "  - \(.name) (ID: \(.id))"'
echo ""

###############################################################################
# Confirm deletion
###############################################################################
__warn__ "DESTRUCTIVE: This will delete $connectionCount connection(s) from Guacamole"

# Safety check: Require --force in non-interactive mode
if [[ "${NON_INTERACTIVE:-0}" == "1" ]] && [[ $FORCE -eq 0 ]]; then
    __err__ "Destructive operation requires --force flag in non-interactive mode"
    __err__ "Add '--force' to parameters in GUI"
    exit 1
fi

# Prompt for confirmation (unless force is set)
if [[ $FORCE -eq 1 ]]; then
    __info__ "Force mode enabled - proceeding without confirmation"
elif ! __prompt_user_yn__ "Are you sure you want to delete these $connectionCount connection(s)?"; then
    __info__ "Deletion cancelled."
    exit 0
fi

###############################################################################
# Delete each matching connection
###############################################################################
echo "---------------------------------------------"
echo "Deleting matching connections..."
echo ""

deleted_count=0
failed_count=0

echo "$matchingConnections" | jq -c '.[]' | while IFS= read -r conn; do
    connId=$(echo "$conn" | jq -r '.id')
    connName=$(echo "$conn" | jq -r '.name')

    if delete_connection "$connId" "$connName" "$GUAC_URL" "$GUAC_DATA_SOURCE" "$AUTH_TOKEN"; then
        ((deleted_count++))
    else
        ((failed_count++))
    fi
done

echo ""
echo "---------------------------------------------"
echo "Deletion complete."
if [[ "$MODE" == "vmid-range" ]]; then
    echo "Processed connections for VMID range $START_VMID to $END_VMID."
else
    echo "Processed connections matching '$SEARCH_SUBSTRING'."
fi

__prompt_keep_installed_packages__

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: ArgumentParser.sh sourced (hybrid for complex dual-mode args)
# - 2025-11-20: Pending validation
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# - Pending validation
# -
#

