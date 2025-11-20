#!/bin/bash
#
# BulkDeleteConnectionGuacamole.sh
#
# Deletes Guacamole connections matching keyword in connection name.
#
# Usage:
#   BulkDeleteConnectionGuacamole.sh <server_url> <keyword> [data_source]
#
# Arguments:
#   server_url  - Guacamole server URL
#   keyword     - Keyword to match (case-insensitive)
#   data_source - Database type (default: mysql)
#
# Examples:
#   BulkDeleteConnectionGuacamole.sh "http://guac.example.com:8080/guacamole" "RDP-"
#   BulkDeleteConnectionGuacamole.sh "http://guac.example.com:8080/guacamole" "RDP-" "postgresql"
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

__parse_args__ "guac_url:url keyword:string data_source:string:mysql" "$@"

TOKEN_PATH="/tmp/cc_pve/guac_token"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __install_or_prompt__ "jq"

    if [[ ! -f "$TOKEN_PATH" ]]; then
        __err__ "No Guacamole auth token found: $TOKEN_PATH"
        echo "Run GetGuacamoleAuthenticationToken.sh first"
        exit 1
    fi

    local auth_token
    auth_token="$(cat "$TOKEN_PATH")"

    __info__ "Retrieving connections from Guacamole"
    __info__ "  Server: $GUAC_URL"
    __info__ "  Data source: $DATA_SOURCE"
    __info__ "  Keyword: $KEYWORD"

    # Retrieve connection tree
    local connections_json
    if ! connections_json=$(curl -s -X GET \
        "${GUAC_URL}/api/session/data/${DATA_SOURCE}/connectionGroups/ROOT/tree?token=${auth_token}" 2>&1); then
        __err__ "Failed to retrieve connection tree"
        exit 1
    fi

    if [[ -z "$connections_json" ]]; then
        __err__ "Empty response from Guacamole"
        exit 1
    fi

    # Parse matching connections
    local -a matching_connections
    mapfile -t matching_connections < <(echo "$connections_json" | jq -r \
        --arg KEYWORD "$KEYWORD" \
        '.childConnections[]
         | select(.name | test($KEYWORD; "i"))
         | .identifier' 2>/dev/null || true)

    if [[ ${#matching_connections[@]} -eq 0 ]]; then
        __warn__ "No connections found matching: $KEYWORD"
        __prompt_keep_installed_packages__
        exit 0
    fi

    # Display matching connections
    __ok__ "Found ${#matching_connections[@]} matching connection(s):"
    echo

    for conn_id in "${matching_connections[@]}"; do
        local conn_name
        conn_name="$(echo "$connections_json" | jq -r \
            --arg ID "$conn_id" \
            '.childConnections[] | select(.identifier == $ID) | .name' 2>/dev/null)"
        echo "  - [$conn_id] $conn_name"
    done

    # Confirmation
    echo
    __warn__ "DESTRUCTIVE OPERATION: This will permanently delete all listed connections"

    if ! __prompt_user_yn__ "Delete all ${#matching_connections[@]} connection(s)?"; then
        __info__ "Operation cancelled"
        __prompt_keep_installed_packages__
        exit 0
    fi

    # Bulk delete
    __info__ "Deleting connections"
    echo

    local deleted=0
    local failed=0

    for conn_id in "${matching_connections[@]}"; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
            "${GUAC_URL}/api/session/data/${DATA_SOURCE}/connections/${conn_id}?token=${auth_token}" 2>/dev/null || echo "000")

        if [[ "$http_code" -eq 204 ]]; then
            __ok__ "Deleted: $conn_id"
            ((deleted++))
        else
            __err__ "Failed to delete: $conn_id (HTTP $http_code)"
            ((failed++))
        fi
    done

    echo
    __info__ "Summary:"
    __info__ "  Total connections: ${#matching_connections[@]}"
    __info__ "  Deleted: $deleted"
    __info__ "  Failed: $failed"

    __prompt_keep_installed_packages__

    [[ $failed -gt 0 ]] && exit 1
    __ok__ "Bulk deletion completed successfully!"
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
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# - Pending validation
# -
#

