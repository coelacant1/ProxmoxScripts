#!/bin/bash
#
# BulkPrintRDPConfiguration.sh
#
# Searches for Guacamole RDP connections by name substring and prints their full configuration.
#
# Usage:
#   BulkPrintRDPConfiguration.sh <guac_url> <search_substring> [data_source]
#
# Arguments:
#   guac_url         - Guacamole server URL (e.g., http://172.20.192.10:8080/guacamole)
#   search_substring - Substring to match in connection names (case-insensitive)
#   data_source      - Optional data source (default: mysql)
#
# Examples:
#   BulkPrintRDPConfiguration.sh "http://172.20.192.10:8080/guacamole" "Clone"
#   BulkPrintRDPConfiguration.sh "http://172.20.192.10:8080/guacamole" "Clone" mysql
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

__parse_args__ "guac_url:url search_substring:string data_source:string=mysql" "$@"

# --- main --------------------------------------------------------------------
main() {
    __install_or_prompt__ "jq"

    # Check for auth token
    if [[ ! -f "/tmp/cc_pve/guac_token" ]]; then
        __err__ "No Guacamole auth token found in /tmp/cc_pve/guac_token. Run GetGuacamoleAuthenticationToken.sh first"
    fi

    local auth_token
    auth_token="$(cat /tmp/cc_pve/guac_token)"

    __info__ "Using data source: '$DATA_SOURCE'"
    __update__ "Retrieving connection tree from Guacamole..."

    local connections_json
    connections_json="$(curl -s -X GET \
      "${GUAC_URL}/api/session/data/${DATA_SOURCE}/connectionGroups/ROOT/tree?token=${auth_token}")"

    if [[ -z "$connections_json" ]]; then
        __err__ "Could not retrieve connection tree from Guacamole"
    fi

    __update__ "Searching for RDP connections with names containing '$SEARCH_SUBSTRING'..."
    local matching_connections
    matching_connections=$(echo "$connections_json" | jq -r \
      --arg SUBSTR "$SEARCH_SUBSTRING" '
        [ (.childConnections // [])[]
          | select(.name | test($SUBSTR; "i"))
          | select(.protocol == "rdp")
          | { id: .identifier, name: .name } ]
      ')

    local match_count
    match_count=$(echo "$matching_connections" | jq 'length')

    if [[ "$match_count" -eq 0 ]]; then
        __info__ "No RDP connections found matching '$SEARCH_SUBSTRING'"
        exit 0
    fi

    __info__ "Found $match_count matching RDP connection(s)"
    echo "$matching_connections" | jq .

    echo "---------------------------------------------"
    __info__ "Printing complete configuration for matching RDP connections..."

    echo "$matching_connections" | jq -c '.[]' | while read -r conn; do
        local conn_id conn_name
        conn_id=$(echo "$conn" | jq -r '.id')
        conn_name=$(echo "$conn" | jq -r '.name')

        echo "---------------------------------------------"
        echo "Configuration for Connection ID: $conn_id"
        echo "Connection Name: $conn_name"

        local connection_info
        connection_info=$(curl -s -X GET \
          "${GUAC_URL}/api/session/data/${DATA_SOURCE}/connections/${conn_id}?token=${auth_token}")

        if [[ -z "$connection_info" ]]; then
            __warn__ "Could not retrieve details for connection ID '$conn_id'. Skipping."
            continue
        fi

        local existing_params
        existing_params=$(curl -s -X GET \
          "${GUAC_URL}/api/session/data/${DATA_SOURCE}/connections/${conn_id}/parameters?token=${auth_token}")

        existing_params=$(echo "$existing_params" | jq 'if . == null then {} else . end')

        local full_config
        full_config=$(echo "$connection_info" | jq --argjson params "$existing_params" '
            . + { parameters: $params }
        ')

        echo "$full_config" | jq .
    done

    __ok__ "Completed printing configurations for all matching RDP connections"
}

main

# Testing status:
#   - Pending validation
