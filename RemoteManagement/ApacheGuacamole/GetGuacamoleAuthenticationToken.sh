#!/bin/bash
#
# GetGuacamoleAuthenticationToken.sh
#
# Retrieves authentication token from Apache Guacamole REST API.
#
# Usage:
#   GetGuacamoleAuthenticationToken.sh <server_url> <username> <password>
#
# Arguments:
#   server_url - Guacamole server URL (e.g., http://guac.example.com:8080/guacamole)
#   username   - Admin username
#   password   - Admin password
#
# Examples:
#   GetGuacamoleAuthenticationToken.sh "http://guac.example.com:8080/guacamole" "admin" "pass123"
#   GetGuacamoleAuthenticationToken.sh "https://guac.local/guacamole" "guacadmin" "secret"
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

TOKEN_PATH="/tmp/cc_pve/guac_token"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __install_or_prompt__ "jq"

    if [[ $# -lt 3 ]]; then
        __err__ "Missing required arguments"
        echo "Usage: $0 <server_url> <username> <password>"
        exit 64
    fi

    local guac_url="$1"
    local guac_user="$2"
    local guac_pass="$3"

    __info__ "Requesting authentication token from Guacamole"
    __info__ "Server: $guac_url"

    mkdir -p "$(dirname "$TOKEN_PATH")"

    local token_response
    if ! token_response=$(curl -s -X POST \
        -d "username=${guac_user}&password=${guac_pass}" \
        "${guac_url}/api/tokens" 2>&1); then
        __err__ "Failed to connect to Guacamole server"
        exit 1
    fi

    local auth_token
    auth_token="$(echo "$token_response" | jq -r '.authToken' 2>/dev/null || echo "")"

    if [[ -z "$auth_token" || "$auth_token" == "null" ]]; then
        __err__ "Failed to retrieve authentication token"
        __info__ "Check credentials and server URL"
        exit 1
    fi

    echo "$auth_token" > "$TOKEN_PATH"

    __ok__ "Authentication token retrieved successfully!"
    __info__ "Token saved to: $TOKEN_PATH"

    __prompt_keep_installed_packages__
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
