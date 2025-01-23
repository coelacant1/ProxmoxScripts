#!/bin/bash
#
# BulkDeleteConnectionGuacamole.sh
#
# Deletes all Guacamole connections containing a given keyword in the connection
# name. Uses Guacamole's REST API to list and delete matching connections.
#
# Usage:
#   ./BulkDeleteConnectionGuacamole.sh GUAC_SERVER_URL KEYWORD [DATA_SOURCE]
#
# Example:
#   # Defaults to 'mysql' data source
#   ./BulkDeleteConnectionGuacamole.sh "http://guac.example.com:8080/guacamole" "RDP-"
#
#   # Specify a different data source (e.g., 'postgresql')
#   ./BulkDeleteConnectionGuacamole.sh "http://guac.example.com:8080/guacamole" "RDP-" "postgresql"
#
# Notes:
#   - This script expects a valid Guacamole auth token in /tmp/cc_pve/guac_token.
#   - Run GetGuacToken.sh beforehand to store the auth token for the Guacamole server.
#   - The script matches the KEYWORD case-insensitively in the connection name.
#   - Data source argument defaults to 'mysql' if not provided.
#

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

__check_root__
__check_proxmox__
__install_or_prompt__ "jq"

GUAC_URL="$1"
KEYWORD="$2"
GUAC_DATA_SOURCE="${3:-mysql}"

if [[ -z "$GUAC_URL" || -z "$KEYWORD" ]]; then
  echo "Error: Missing required arguments."
  echo "Usage: $0 GUAC_SERVER_URL KEYWORD [DATA_SOURCE]"
  echo "Example: $0 \"http://guac.example.com:8080/guacamole\" \"RDP-\" \"mysql\""
  exit 1
fi

if [[ ! -f "/tmp/cc_pve/guac_token" ]]; then
  echo "Error: No Guacamole auth token found in /tmp/cc_pve/guac_token."
  echo "Please run GetGuacToken.sh first."
  exit 1
fi

AUTH_TOKEN="$(cat /tmp/cc_pve/guac_token)"

###############################################################################
# Retrieve All Connections Under "ROOT"
###############################################################################
# The connection tree includes childConnections[] for top-level connections
# and childGroups[] for nested groups. If your Guacamole setup uses nested
# groups, you may need to recurse through each group's .childConnections as well.
connectionsJson="$(curl -s -X GET \
  "${GUAC_URL}/api/session/data/${GUAC_DATA_SOURCE}/connectionGroups/ROOT/tree?token=${AUTH_TOKEN}")"

if [[ -z "$connectionsJson" ]]; then
  echo "Error: Could not retrieve connection tree from Guacamole."
  exit 1
fi

###############################################################################
# Parse All Connection Identifiers Where Name Matches KEYWORD
###############################################################################
# The 'test($KEYWORD; "i")' performs a case-insensitive regex match against KEYWORD.
mapfile -t matchingConnections < <(echo "$connectionsJson" | jq -r \
  --arg KEYWORD "$KEYWORD" \
  '.childConnections[]
   | select(.name | test($KEYWORD; "i"))
   | .identifier')

if [[ "${#matchingConnections[@]}" -eq 0 ]]; then
  echo "No connections found matching '$KEYWORD'."
  __prompt_keep_installed_packages__
  exit 0
fi

echo "Found ${#matchingConnections[@]} matching connection(s) with keyword '$KEYWORD':"
for connId in "${matchingConnections[@]}"; do
  connName="$(echo "$connectionsJson" | jq -r \
    --arg ID "$connId" '.childConnections[]
    | select(.identifier == $ID)
    | .name')"
  echo "- [$connId] '$connName'"
done

###############################################################################
# Confirmation Prompt
###############################################################################
read -r -p "Are you sure you want to DELETE all connections above? [y/N] " confirm
if [[ "$confirm" != [yY]* ]]; then
  echo "Aborting deletion."
  __prompt_keep_installed_packages__
  exit 0
fi

###############################################################################
# Bulk Delete
###############################################################################
for connId in "${matchingConnections[@]}"; do
  delResponse="$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    "${GUAC_URL}/api/session/data/${GUAC_DATA_SOURCE}/connections/${connId}?token=${AUTH_TOKEN}")"

  if [[ "$delResponse" -eq 204 ]]; then
    echo "Deleted connection ID '$connId'."
  else
    echo "Failed to delete connection ID '$connId' (HTTP status $delResponse)."
  fi
done

__prompt_keep_installed_packages__
