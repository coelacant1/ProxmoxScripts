#!/bin/bash
#
# DebugConnectionTree.sh
#
# Debug script to view the raw Guacamole connection tree structure
#
# Usage:
#   DebugConnectionTree.sh GUAC_SERVER_URL [DATA_SOURCE]
#
# Example:
#   DebugConnectionTree.sh https://domain.com/guacamole mysql
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "guac_url:url data_source:string:mysql" "$@"

__install_or_prompt__ "jq"

# Ensure a Guacamole auth token exists
if [[ ! -f "/tmp/cc_pve/guac_token" ]]; then
    echo "Error: No Guacamole auth token found in /tmp/cc_pve/guac_token."
    echo "Please run GetGuacamoleAuthenticationToken.sh first."
    exit 1
fi

AUTH_TOKEN="$(cat /tmp/cc_pve/guac_token)"
echo "Using data source: '$DATA_SOURCE'"
echo "Auth token (first 20 chars): ${AUTH_TOKEN:0:20}..."
echo ""

###############################################################################
# First, validate the token and get user info
###############################################################################
echo "=== VALIDATING AUTH TOKEN ==="
userInfo="$(curl -s -X GET "${GUAC_URL}/api/session/data/${DATA_SOURCE}/self?token=${AUTH_TOKEN}")"
echo "$userInfo" | jq '.'
echo ""

###############################################################################
# List available data sources
###############################################################################
echo "=== AVAILABLE DATA SOURCES ==="
dataSources="$(curl -s -X GET "${GUAC_URL}/api/session/data?token=${AUTH_TOKEN}")"
if echo "$dataSources" | jq -e 'type' >/dev/null 2>&1; then
    echo "$dataSources" | jq 'keys' 2>/dev/null || echo "$dataSources"
else
    echo "Response: $dataSources"
fi
echo ""

###############################################################################
# Get user permissions
###############################################################################
echo "=== USER PERMISSIONS ==="
permissions="$(curl -s -X GET "${GUAC_URL}/api/session/data/${DATA_SOURCE}/self/permissions?token=${AUTH_TOKEN}")"
echo "$permissions" | jq '.'
echo ""

###############################################################################
# Try listing connections directly (not tree)
###############################################################################
echo "=== DIRECT CONNECTION LIST ==="
connectionsList="$(curl -s -X GET "${GUAC_URL}/api/session/data/${DATA_SOURCE}/connections?token=${AUTH_TOKEN}")"
echo "$connectionsList" | jq '.'
echo ""

###############################################################################
# Retrieve and display the raw connection tree
###############################################################################
echo "=== CONNECTION TREE (ROOT/tree endpoint) ==="
connectionsJson="$(curl -s -X GET \
    "${GUAC_URL}/api/session/data/${DATA_SOURCE}/connectionGroups/ROOT/tree?token=${AUTH_TOKEN}")"

echo "$connectionsJson" | jq '.'
echo ""

# Check if it's an error response
if echo "$connectionsJson" | jq -e '.type' >/dev/null 2>&1; then
    errorType=$(echo "$connectionsJson" | jq -r '.type')
    if [[ "$errorType" == "PERMISSION_DENIED" ]]; then
        echo "⚠️  Permission denied for ROOT connection group tree"
        echo "This usually means the user lacks READ permission on the ROOT connection group"
    fi
fi

if [[ -z "$connectionsJson" ]]; then
    echo "Error: Empty response from connection tree endpoint"
    exit 1
fi

echo "=== RAW CONNECTION TREE JSON ==="
echo "$connectionsJson" | jq '.'
echo ""

echo "=== CONNECTION TREE SUMMARY ==="
if echo "$connectionsJson" | jq -e '.type' >/dev/null 2>&1; then
    echo "⚠️  Cannot generate summary - API returned an error"
else
    echo "Root-level connections:"
    echo "$connectionsJson" | jq -r '.childConnections // [] | length'
    echo ""

    echo "Connection groups (folders):"
    echo "$connectionsJson" | jq -r '.childConnectionGroups // [] | length'
fi
echo ""

echo "=== ALL CONNECTIONS (using recursive search) ==="
echo "$connectionsJson" | jq -r '
    def getAllConnections:
      (.childConnections // []) +
      ((.childConnectionGroups // []) | map(getAllConnections) | flatten);
    
    getAllConnections[] | 
    "\(.identifier) | \(.protocol) | \(.name)"
'
echo ""

echo "=== ALL CONNECTION GROUPS (folders) ==="
echo "$connectionsJson" | jq -r '
    def getAllGroups:
      (.childConnectionGroups // []) +
      ((.childConnectionGroups // []) | map(.childConnectionGroups // []) | flatten);
    
    getAllGroups[] | 
    "Group: \(.name) (ID: \(.identifier))"
'
echo ""

echo "=== RDP CONNECTIONS CONTAINING 'Bio' (case-insensitive) ==="
echo "$connectionsJson" | jq -r '
    def getAllConnections:
      (.childConnections // []) +
      ((.childConnectionGroups // []) | map(getAllConnections) | flatten);
    
    [ getAllConnections[]
      | select(.name | test("Bio"; "i"))
      | select(.protocol == "rdp")
      | { id: .identifier, name: .name, protocol: .protocol } ]
' | jq '.'

###############################################################################
# Script notes:
###############################################################################
# Last checked: YYYY-MM-DD
#
# Changes:
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

