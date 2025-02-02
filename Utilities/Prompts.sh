#!/bin/bash
#
# Prompts.sh
#
# Provides functions for user interaction and prompts (e.g., checking root permissions, verifying Proxmox environment, installing packages on demand).
#
# Usage:
#   source ./Prompts.sh
#
#   # Then call its functions, for example:
#   __check_root__
#   __check_proxmox__
#   __install_or_prompt__ "curl"
#   __prompt_keep_installed_packages__
#
# Examples:
#   # Example: Check root and Proxmox status, then install curl:
#   source ./Prompts.sh
#   __check_root__
#   __check_proxmox__
#   __install_or_prompt__ "curl"
#   __prompt_keep_installed_packages__
#
# Function Index:
#   - __check_root__
#   - __check_proxmox__
#   - __install_or_prompt__
#   - __prompt_keep_installed_packages__
#

###############################################################################
# GLOBALS
###############################################################################
# Array to keep track of packages installed by __install_or_prompt__() in this session.
SESSION_INSTALLED_PACKAGES=()

###############################################################################
# Misc Functions
###############################################################################

# --- __check_root__ ------------------------------------------------------------
# @function __check_root__
# @description Checks if the current user is root. Exits if not.
# @usage __check_root__
# @return Exits 1 if not root.
# @example_output If not run as root, the output is: "Error: This script must be run as root (sudo)."
__check_root__() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root (sudo)."
        exit 1
    fi
}

# --- __check_proxmox__ ------------------------------------------------------------
# @function __check_proxmox__
# @description Checks if this is a Proxmox node. Exits if not.
# @usage __check_proxmox__
# @return Exits 2 if not Proxmox.
# @example_output If 'pveversion' is not found, the output is: "Error: 'pveversion' command not found. Are you sure this is a Proxmox node?"
__check_proxmox__() {
    if ! command -v pveversion &>/dev/null; then
        echo "Error: 'pveversion' command not found. Are you sure this is a Proxmox node?"
        exit 2
    fi
}

# --- __install_or_prompt__ ------------------------------------------------------------
# @function __install_or_prompt__
# @description Checks if a specified command is available. If not, prompts
#   the user to install it via apt-get. Exits if the user declines.
#   Also keeps track of installed packages in SESSION_INSTALLED_PACKAGES.
# @usage __install_or_prompt__ <command_name>
# @param command_name The name of the command to check and install if missing.
# @return Exits 1 if user declines the installation.
# @example_output If "curl" is missing and the user declines installation, the output is: "Aborting script because 'curl' is not installed."
__install_or_prompt__() {
    local cmd="$1"

    if ! command -v "$cmd" &>/dev/null; then
        echo "The '$cmd' utility is required but is not installed."
        read -r -p "Would you like to install '$cmd' now? [y/N]: " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            apt-get install -y "$cmd"
            SESSION_INSTALLED_PACKAGES+=("$cmd")
        else
            echo "Aborting script because '$cmd' is not installed."
            exit 1
        fi
    fi
}

# --- __prompt_keep_installed_packages__ ------------------------------------------------------------
# @function __prompt_keep_installed_packages__
# @description Prompts the user whether to keep or remove all packages that
#   were installed in this session via __install_or_prompt__(). If the user chooses
#   "No", each package in SESSION_INSTALLED_PACKAGES is removed.
# @usage __prompt_keep_installed_packages__
# @return Removes packages if user says "No", otherwise does nothing.
# @example_output If the user chooses "No", the output is: "Removing the packages installed in this session..." followed by "Packages removed."
__prompt_keep_installed_packages__() {
    if [[ ${#SESSION_INSTALLED_PACKAGES[@]} -eq 0 ]]; then
        return
    fi

    echo "The following packages were installed during this session:"
    printf ' - %s\n' "${SESSION_INSTALLED_PACKAGES[@]}"
    read -r -p "Do you want to KEEP these packages? [Y/n]: " response

    if [[ "$response" =~ ^[Nn]$ ]]; then
        echo "Removing the packages installed in this session..."
        apt-get remove -y "${SESSION_INSTALLED_PACKAGES[@]}"
        # Optional: apt-get purge -y "${SESSION_INSTALLED_PACKAGES[@]}"
        SESSION_INSTALLED_PACKAGES=()
        echo "Packages removed."
    else
        echo "Keeping all installed packages."
    fi
}
