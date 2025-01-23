#!/bin/bash
#
# GetGuacamoleAuthenticationToken.sh
#
# Retrieves an authentication token from the Apache Guacamole REST API
# and saves it to /tmp/cc_pve/guac_token for later use.
#
# Usage:
#   ./GetGuacamoleAuthenticationToken.sh GUAC_SERVER_URL GUAC_ADMIN_USER GUAC_ADMIN_PASS
#
# Example:
#   # Using default port 8080 on guac.example.com
#   ./GetGuacamoleAuthenticationToken.sh "http://guac.example.com:8080/guacamole" "admin" "pass123"
#

source "${UTILITYPATH}/Prompts.sh"

__check_root__
__check_proxmox__
__install_or_prompt__ "jq"

GUAC_URL="$1"
GUAC_ADMIN_USER="$2"
GUAC_ADMIN_PASS="$3"

if [[ -z "$GUAC_URL" || -z "$GUAC_ADMIN_USER" || -z "$GUAC_ADMIN_PASS" ]]; then
    echo "Error: Missing required arguments." >&2
    echo "Usage: ./GetGuacToken.sh GUAC_SERVER_URL GUAC_ADMIN_USER GUAC_ADMIN_PASS" >&2
    exit 1
fi

mkdir -p "/tmp/cc_pve"

###############################################################################
# Main Logic
###############################################################################
TOKEN_RESPONSE="$(curl -s -X POST \
  -d "username=${GUAC_ADMIN_USER}&password=${GUAC_ADMIN_PASS}" \
  "${GUAC_URL}/api/tokens")"

AUTH_TOKEN="$(echo "$TOKEN_RESPONSE" | jq -r '.authToken')"

if [[ -z "$AUTH_TOKEN" || "$AUTH_TOKEN" == "null" ]]; then
    echo "Error: Failed to retrieve Guacamole auth token." >&2
    exit 1
fi

echo "$AUTH_TOKEN" > "/tmp/cc_pve/guac_token"
echo "Guacamole auth token saved to /tmp/cc_pve/guac_token"

__prompt_keep_installed_packages__
