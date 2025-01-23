#!/bin/bash
#
# RemoveGuacamoleAuthenticationToken.sh
#
# This script deletes the locally saved Guacamole authentication token
# stored in /tmp/cc_pve/guac_token.
#
# Usage:
#   ./RemoveGuacamoleAuthenticationToken.sh
#
# Example:
#   ./RemoveGuacamoleAuthenticationToken.sh
#

source "${UTILITYPATH}/Prompts.sh"

__check_root__
__check_proxmox__

###############################################################################
# Main Logic
###############################################################################
TOKEN_PATH="/tmp/cc_pve/guac_token"

if [[ ! -f "$TOKEN_PATH" ]]; then
  echo "No Guacamole auth token found at '$TOKEN_PATH'. Nothing to delete."
else
  rm -f "$TOKEN_PATH"
  echo "Guacamole auth token deleted from '$TOKEN_PATH'."
fi

__prompt_keep_installed_packages__
