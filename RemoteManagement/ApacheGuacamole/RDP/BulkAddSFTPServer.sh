#!/bin/bash
#
# BulkAddSFTPServer.sh
#
# This script searches for Guacamole RDP connections whose name contains a given substring,
# retrieves each connection’s details and current parameters, and then updates the SFTP
# settings as follows:
#
#   - "sftp-directory" and "sftp-root-directory" are set to the provided SFTP_ROOT value
#     (default: /root/Desktop)
#   - "sftp-hostname" is set to the value of the "hostname" parameter from the connection
#   - "sftp-password" is set to the current connection password (from the "password" parameter)
#   - "sftp-username" is set to the current connection username (from the "username" parameter)
#   - "enable-sftp" is set to "true"
#   - "sftp-port" is set to the provided SFTP_PORT value (default: 22)
#
# Usage:
#   ./BulkAddSFTPServer.sh GUAC_SERVER_URL SEARCH_SUBSTRING [SFTP_ROOT_DIRECTORY] [SFTP_PORT] [DATA_SOURCE]
#
# Example:
#   ./BulkAddSFTPServer.sh "http://172.20.192.10:8080/guacamole" "Clone" "/root/Desktop" 22 mysql
#

# Optionally load utility functions (if available)
source "${UTILITYPATH}/Prompts.sh"
__install_or_prompt__ "jq"

# Assign input parameters
GUAC_URL="$1"
SEARCH_SUBSTRING="$2"
SFTP_ROOT="${3:-/root/Desktop}"
SFTP_PORT="${4:-22}"
GUAC_DATA_SOURCE="${5:-mysql}"

if [[ -z "$GUAC_URL"  -z "$SEARCH_SUBSTRING" ]]; then
    echo "Error: Missing required arguments."
    echo "Usage: $0 GUAC_SERVER_URL SEARCH_SUBSTRING [SFTP_ROOT_DIRECTORY] [SFTP_PORT] [DATA_SOURCE]"
    exit 1
fi

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
# Filter matching RDP connections (by partial name match)
###############################################################################
echo "Searching for RDP connections with names containing '$SEARCH_SUBSTRING'..."
matchingConnections=$(echo "$connectionsJson" | jq -r \
  --arg SUBSTR "$SEARCH_SUBSTRING" '
    [ (.childConnections // [])[]
      | select(.name | test($SUBSTR; "i"))
      | select(.protocol == "rdp")
      | { id: .identifier, name: .name } ]
  ')

# Check if any matches were found.
if [[ "$(echo "$matchingConnections" | jq 'length')" -eq 0 ]]; then
  echo "No RDP connections found matching '$SEARCH_SUBSTRING'."
  exit 0
fi

echo "Found matching RDP connections:"
echo "$matchingConnections" | jq .

###############################################################################
# For each matching connection, update SFTP parameters
###############################################################################
echo "---------------------------------------------"
echo "Updating SFTP parameters for matching connections..."
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
    
    # Extract the current password, hostname, and username from the existing parameters.
    current_password=$(echo "$existingParams" | jq -r '.password // ""')
    current_hostname=$(echo "$existingParams" | jq -r '.hostname // ""')
    current_username=$(echo "$existingParams" | jq -r '.username // ""')
    
    # Build new parameters by updating/adding SFTP settings.
    newParams=$(echo "$existingParams" | jq --arg sftpRoot "$SFTP_ROOT" \
                                             --arg sftpPort "$SFTP_PORT" \
                                             --arg currentHostname "$current_hostname" \
                                             --arg sftpPassword "$current_password" \
                                             --arg sftpUsername "$current_username" '
        .["sftp-directory"]     = $sftpRoot |
        .["sftp-root-directory"] = $sftpRoot |
        .["sftp-hostname"]       = $currentHostname |
        .["sftp-password"]       = $sftpPassword |
        .["sftp-username"]       = $sftpUsername |
        .["enable-sftp"]         = "true" |
        .["sftp-port"]           = $sftpPort
    ')
    
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
    
    if [[ "$updateResponse" -eq 200  "$updateResponse" -eq 204 ]]; then
        echo "  Successfully updated SFTP parameters for connection '$connId'."
    else
        echo "  Failed to update connection '$connId' (HTTP status $updateResponse)."
    fi
done

echo "Completed updating SFTP parameters for all matching connections."