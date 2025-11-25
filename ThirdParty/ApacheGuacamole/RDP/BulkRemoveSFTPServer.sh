#!/bin/bash
#
# BulkRemoveSFTPServer.sh
#
# This script searches for Guacamole connections whose name contains a given substring,
# retrieves the complete connection configuration, and then updates each connection
# by removing SFTP-related parameters.
#
# The following SFTP keys are removed:
#   - "sftp-directory"
#   - "sftp-root-directory"
#   - "sftp-hostname"
#   - "sftp-password"
#   - "sftp-username"
#   - "enable-sftp"
#   - "sftp-port"
#
# Usage:
#   BulkRemoveSFTPServer.sh GUAC_SERVER_URL SEARCH_SUBSTRING [DATA_SOURCE]
#
# Example:
#   BulkRemoveSFTPServer.sh "http://192.168.1.10:8080/guacamole" "Clone" mysql
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

__parse_args__ "guac_url:url search_substring:string guac_data_source:string:mysql" "$@"

__install_or_prompt__ "jq"

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
# Filter matching connections (by partial name match)
###############################################################################
echo "Searching for connections with names containing '$SEARCH_SUBSTRING'..."
matchingConnections=$(echo "$connectionsJson" | jq -r \
    --arg SUBSTR "$SEARCH_SUBSTRING" '
    [ (.childConnections // [])[]
      | select(.name | test($SUBSTR; "i"))
      | { id: .identifier, name: .name } ]
  ')

# Check if any matches were found.
if [[ "$(echo "$matchingConnections" | jq 'length')" -eq 0 ]]; then
    echo "No connections found matching '$SEARCH_SUBSTRING'."
    exit 0
fi

echo "Found matching connections:"
echo "$matchingConnections" | jq .

###############################################################################
# For each matching connection, remove SFTP parameters
###############################################################################
echo "---------------------------------------------"
echo "Removing SFTP parameters for matching connections..."
echo "$matchingConnections" | jq -c '.[]' | while read -r conn; do
    connId=$(echo "$conn" | jq -r '.id')
    connName=$(echo "$conn" | jq -r '.name')

    echo "---------------------------------------------"
    echo "Processing Connection ID: $connId"
    echo "Connection Name: $connName"

    # Retrieve the full connection JSON.
    connectionInfo=$(curl -s -X GET \
        "${GUAC_URL}/api/session/data/${GUAC_DATA_SOURCE}/connections/${connId}?token=${AUTH_TOKEN}")

    if [[ -z "$connectionInfo" ]]; then
        echo "  Error: Could not retrieve details for connection ID '$connId'. Skipping."
        continue
    fi

    # Retrieve existing parameters.
    existingParams=$(curl -s -X GET \
        "${GUAC_URL}/api/session/data/${GUAC_DATA_SOURCE}/connections/${connId}/parameters?token=${AUTH_TOKEN}")

    # Default to an empty object if no parameters are returned.
    existingParams=$(echo "$existingParams" | jq 'if . == null then {} else . end')

    # Remove SFTP-related keys.
    newParams=$(echo "$existingParams" | jq 'del(.["sftp-directory"], .["sftp-root-directory"], .["sftp-hostname"], .["sftp-password"], .["sftp-username"], .["enable-sftp"], .["sftp-port"])')

    # Build the updated connection JSON payload.
    updatedJson=$(echo "$connectionInfo" | jq --argjson params "$newParams" '
        {
          parentIdentifier: .parentIdentifier,
          name: .name,
          protocol: .protocol,
          attributes: .attributes,
          parameters: $params
        }
    ')

    # Send the updated JSON via a PUT request to update the connection.
    updateResponse=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        -H "Content-Type: application/json" \
        -d "$updatedJson" \
        "${GUAC_URL}/api/session/data/${GUAC_DATA_SOURCE}/connections/${connId}?token=${AUTH_TOKEN}")

    if [[ "$updateResponse" -eq 200 || "$updateResponse" -eq 204 ]]; then
        echo "  Successfully removed SFTP parameters for connection '$connId'."
    else
        echo "  Failed to update connection '$connId' (HTTP status $updateResponse)."
    fi
done

echo "Completed removal of SFTP parameters for all matching connections."

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Deep technical validation - confirmed compliant
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

