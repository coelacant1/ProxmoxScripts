#!/bin/bash
#
# _TestPrompts.sh
# 
# Usage:
# ./_TestPrompts.sh
#
# Demonstrates usage of Prompts.sh by sourcing it and calling each function.
#

if [ -z "${UTILITYPATH}" ]; then
  # UTILITYPATH is unset or empty
  export UTILITYPATH="$(pwd)"
fi

# 1) Source the script
source "${UTILITYPATH}/Prompts.sh"

echo "=== TEST: __check_root__ ==="
__check_root__

echo
echo "=== TEST: __check_proxmox__ ==="
__check_proxmox__

echo
echo "=== TEST: __install_or_prompt__ (curl) ==="
__install_or_prompt__ "curl"

echo
echo "=== TEST: __prompt_keep_installed_packages__ ==="
__prompt_keep_installed_packages__

echo
echo "All tests completed successfully."
