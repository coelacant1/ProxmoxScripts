#!/bin/bash
#
# Utilities.sh
#
# Provides reusable functions for Proxmox management and automation.
# Typically, it is not run directly. Instead, you source this script from your own.
#
# Usage:
#   source "/path/to/dir/pathUtilities.sh"
#
# Further Explanation:
# - This library is designed for Proxmox version 8 by default.
# - Each function includes its own usage block in the comments.
# - Not all functions require root privileges, but your calling script might.
# - If a package is not available in a default Proxmox 8 install, call install_or_prompt.
# - You can call prompt_keep_installed_packages at the end of your script to offer
#   removal of session-installed packages.
#

set -e

if [[ "$(basename "$PWD")" != "Utilities" ]]; then
    cd Utilities
fi

source "./Communication.sh"
source "./Conversion.sh"
source "./Prompts.sh"
source "./Queries.sh"
source "./SSH.sh"

if [[ "$(basename "$PWD")" == "Utilities" ]]; then
    cd ..
fi
