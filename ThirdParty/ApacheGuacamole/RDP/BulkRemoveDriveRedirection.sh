#!/bin/bash
#
# BulkRemoveDriveRedirection.sh
#
# This script searches for Guacamole connections whose name contains a given substring,
# retrieves the full connection JSON for each match, and then updates its connection
# parameters by removing drive redirection settings. Specifically, it removes the following keys:
#
#   - "enable-drive"
#   - "drive-name"
#   - "drive-path"
#   - "create-drive-path"
#
# All other existing parameters (including connection details such as hostname, port, username, etc.)
# are preserved.
#
# Usage:
#   BulkRemoveDriveRedirection.sh GUAC_SERVER_URL SEARCH_SUBSTRING [DATA_SOURCE]
#
# Example:
#   BulkRemoveDriveRedirection.sh "http://192.168.1.10:8080/guacamole" "Clone" mysql
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
# Filter matching connections (by partial name match) and force an array output
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
# For each matching connection, remove drive redirection parameters
###############################################################################
echo "---------------------------------------------"
echo "Removing drive redirection parameters from matching connections..."
echo "$matchingConnections" | jq -c '.[]' | while read -r conn; do
    connId=$(echo "$conn" | jq -r '.id')
    connName=$(echo "$conn" | jq -r '.name')

    echo "---------------------------------------------"
    echo "Processing Connection ID: $connId"
    echo "Connection Name: $connName"

    # Retrieve the full connection JSON using the identifier.
    connectionInfo=$(curl -s -X GET \
        "${GUAC_URL}/api/session/data/${GUAC_DATA_SOURCE}/connections/${connId}?token=${AUTH_TOKEN}")

    if [[ -z "$connectionInfo" ]]; then
        echo "  Error: Could not retrieve details for connection ID '$connId'. Skipping."
        continue
    fi

    # Retrieve existing parameters from the dedicated endpoint.
    existingParams=$(curl -s -X GET \
        "${GUAC_URL}/api/session/data/${GUAC_DATA_SOURCE}/connections/${connId}/parameters?token=${AUTH_TOKEN}")

    # If no parameters are returned, default to an empty object.
    existingParams=$(echo "$existingParams" | jq 'if . == null then {} else . end')

    # Remove drive redirection keys.
    newParams=$(echo "$existingParams" | jq 'del(.["enable-drive"], .["drive-name"], .["drive-path"], .["create-drive-path"])')

    # Build the updated connection JSON payload.
    # Preserve parentIdentifier, name, protocol, and attributes from connectionInfo.
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
        echo "  Successfully updated connection '$connId'."
    else
        echo "  Failed to update connection '$connId' (HTTP status $updateResponse)."
    fi
done

echo "Completed removal of drive redirection parameters for all matching connections."

# Testing status:
#   - ArgumentParser.sh sourced
#   - Updated to use ArgumentParser.sh
#   - Pending validation
