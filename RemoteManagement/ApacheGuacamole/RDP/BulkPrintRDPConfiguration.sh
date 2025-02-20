#!/bin/bash
#
# BulkPrintRDPConfiguration.sh
#
# This script searches for Guacamole connections whose name contains a given substring
# and whose protocol is RDP, retrieves the complete configuration for each (connection
# details and parameters), and then prints the full JSON configuration.
#
# Usage:
#   ./BulkPrintRDPConfiguration.sh GUAC_SERVER_URL SEARCH_SUBSTRING [DATA_SOURCE]
#
# Example:
#   ./BulkPrintRDPConfiguration.sh "http://172.20.192.10:8080/guacamole" "Clone" mysql
#

# Optionally load utility functions (if you have them available)
source "${UTILITYPATH}/Prompts.sh"
install_or_prompt "jq"

# Assign input parameters
GUAC_URL="$1"
SEARCH_SUBSTRING="$2"
GUAC_DATA_SOURCE="${3:-mysql}"

if [[ -z "$GUAC_URL" || -z "$SEARCH_SUBSTRING" ]]; then
    echo "Error: Missing required arguments."
    echo "Usage: $0 GUAC_SERVER_URL SEARCH_SUBSTRING [DATA_SOURCE]"
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
# For each matching connection, print the entire configuration
###############################################################################
echo "---------------------------------------------"
echo "Printing complete configuration for matching RDP connections..."
echo "$matchingConnections" | jq -c '.[]' | while read -r conn; do
    connId=$(echo "$conn" | jq -r '.id')
    connName=$(echo "$conn" | jq -r '.name')
    
    echo "---------------------------------------------"
    echo "Configuration for Connection ID: $connId"
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
    
    # Default to an empty object if no parameters are returned.
    existingParams=$(echo "$existingParams" | jq 'if . == null then {} else . end')
    
    # Merge the connection info with its parameters.
    fullConfig=$(echo "$connectionInfo" | jq --argjson params "$existingParams" '
        . + { parameters: $params }
    ')
    
    # Print the full configuration in a pretty format.
    echo "$fullConfig" | jq .
done

echo "Completed printing configurations for all matching RDP connections."