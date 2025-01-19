#!/bin/bash
#
# _TestSSH.sh
#
# Demonstrates how to source SSH.sh and call the __wait_for_ssh__ function.
#
# Usage:
#   ./_TestSSH.sh [host] [sshUsername]
#
# Example:
#   ./_TestSSH.sh
#   ./_TestSSH.sh 192.168.1.100 root s3cr3t
#

###############################################################################
# Ensure UTILITYPATH is set (or default to current directory)
###############################################################################
if [ -z "${UTILITYPATH}" ]; then
  export UTILITYPATH="$(pwd)"
fi

###############################################################################
# Source the SSH.sh script (adjust path if needed)
###############################################################################
source "${UTILITYPATH}/SSH.sh"

###############################################################################
# Parse input arguments or prompt the user
###############################################################################
host="${1}"
sshUsername="${2}"
sshPassword="${3}"

# If host was not provided, prompt for it:
if [ -z "${host}" ]; then
  read -rp "Enter host (IP or hostname): " host
fi

# If username was not provided, prompt for it:
if [ -z "${sshUsername}" ]; then
  read -rp "Enter SSH username: " sshUsername
fi

# If password was not provided, prompt for it (hidden input):
if [ -z "${sshPassword}" ]; then
  read -rsp "Enter SSH password: " sshPassword
  echo   # Move to a new line after entering the password
fi

###############################################################################
# Test the SSH connection
###############################################################################
echo "Attempting to connect to '${host}' as '${sshUsername}'..."
__wait_for_ssh__ "${host}" "${sshUsername}" "${sshPassword}"

# If the function returns successfully, continue:
echo "Success: SSH is accessible on '${host}'."
exit 0
