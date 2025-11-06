#!/bin/bash
#
# BulkUpdateDriveRedirection.sh
#
# This script searches for Guacamole connections whose name contains a given substring,
# retrieves the full connection JSON for each match, and then updates its connection
# parameters as follows:
#
#   - Retrieves existing parameters from GET /connections/{id}/parameters.
#   - Creates a new drive path by appending a sanitized subfolder (based on the connection name)
#     to the provided DRIVE_PATH.
#   - Directly sets the following drive redirection keys:
#         "enable-drive": true,
#         "drive-name":   <provided DRIVE_NAME>,
#         "drive-path":   <DRIVE_PATH>/<sanitized connection name>,
#         "create-drive-path": true
#
# All other existing parameters (including RDP parameters such as hostname, port, username, etc.)
# are preserved.
#
# Usage:
#   BulkUpdateDriveRedirection.sh GUAC_SERVER_URL SEARCH_SUBSTRING DRIVE_NAME DRIVE_PATH [DATA_SOURCE]
#
# Example:
#   BulkUpdateDriveRedirection.sh "http://172.20.192.10:8080/guacamole" "Clone" "Storage" "/mnt/storage" mysql
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"

__parse_args__ "guac_url:url search_substring:string drive_name:string drive_path:path guac_data_source:string:mysql" "$@"

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
# For each matching connection, update drive redirection parameters
###############################################################################
echo "---------------------------------------------"
echo "Updating drive redirection parameters for matching connections..."
echo "$matchingConnections" | jq -c '.[]' | while read -r conn; do
    connId=$(echo "$conn" | jq -r '.id')
    connName=$(echo "$conn" | jq -r '.name')

    echo "---------------------------------------------"
    echo "Processing Connection ID: $connId"
    echo "Connection Name: $connName"

    # Sanitize connection name for subfolder usage (replace spaces with underscores)
    sanitizedName=$(echo "$connName" | tr ' ' '_')

    # Build the new drive path by appending the sanitized connection name as a subfolder
    newDrivePath="${DRIVE_PATH}/${sanitizedName}"

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

    # Manually set new drive redirection keys.
    newParams=$(echo "$existingParams" | jq --arg dname "$DRIVE_NAME" --arg ndp "$newDrivePath" '
        .["enable-drive"] = true |
        .["drive-name"]   = $dname |
        .["drive-path"]   = $ndp |
        .["create-drive-path"] = true
    ')

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

    #echo "New merged parameters:"
    #echo "$newParams" | jq .

    #echo "Updated connection payload:"
    #echo "$updatedJson" | jq .

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

echo "Completed updating drive redirection parameters for all matching connections."


# Testing status:
#   - ArgumentParser.sh sourced  
#   - Updated to use ArgumentParser.sh
#   - Pending validation
