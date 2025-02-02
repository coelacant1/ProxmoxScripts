#!/bin/bash
#
# SSH.sh
#
# This script provides repeated-use SSH functions that can be sourced by other
# scripts.
#
# Usage:
#   source SSH.sh
#
# Function Index:
#   - __wait_for_ssh__
#

source "${UTILITYPATH}/Prompts.sh"

__install_or_prompt__ "sshpass"

###############################################################################
# SSH Functions
###############################################################################

# --- __wait_for_ssh__ ------------------------------------------------------------
# @function __wait_for_ssh__
# @description Repeatedly attempts to connect via SSH to a specified host using a given username and password until SSH is reachable or until the maximum number of attempts is exhausted.
# @usage __wait_for_ssh__ <host> <sshUsername> <sshPassword>
# @param 1 The SSH host (IP or domain).
# @param 2 The SSH username.
# @param 3 The SSH password.
# @return Returns 0 if a connection is established within the max attempts, otherwise exits with code 1.
# @example_output For __wait_for_ssh__ "192.168.1.100" "user" "pass", the output might be:
#   SSH is up on "192.168.1.100"
__wait_for_ssh__() {
  local host="$1"
  local sshUsername="$2"
  local sshPassword="$3"
  local maxAttempts=20
  local delay=3

  for attempt in $(seq 1 "$maxAttempts"); do
    if sshpass -p "$sshPassword" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
      "$sshUsername@$host" exit 2>/dev/null; then
      echo "SSH is up on \"$host\""
      return 0
    fi
    echo "Attempt $attempt/$maxAttempts: SSH not ready on \"$host\"; waiting $delay seconds..."
    sleep "$delay"
  done

  echo "Error: Could not connect to SSH on \"$host\" after $maxAttempts attempts."
  exit 1
}
