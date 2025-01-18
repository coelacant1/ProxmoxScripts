#!/bin/bash
#
# Prompts.sh
#
# Provides functions for user interaction and prompts (e.g., checking root
# permissions, verifying Proxmox environment, installing packages on demand).
#
# Usage:
#   source ./Prompts.sh
#
#   # Then call its functions, for example:
#   check_root
#   check_proxmox
#   install_or_prompt "curl"
#   prompt_keep_installed_packages
#
# Examples:
#   # Example: Check root and Proxmox status, then install curl:
#   source ./Prompts.sh
#   check_root
#   check_proxmox
#   install_or_prompt "curl"
#   prompt_keep_installed_packages
#
# Function Index:
#   - check_root
#   - check_proxmox
#   - install_or_prompt
#   - prompt_keep_installed_packages
#

###############################################################################
# GLOBALS
###############################################################################
# Array to keep track of packages installed by install_or_prompt() in this session.
SESSION_INSTALLED_PACKAGES=()

###############################################################################
# Misc Functions
###############################################################################

# --- Check Root User -------------------------------------------------------
# @function check_root
# @description Checks if the current user is root. Exits if not.
# @usage
#   check_root
# @return
#   Exits 1 if not root.
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root (sudo)."
        exit 1
    fi
}

# --- Check Proxmox ---------------------------------------------------------
# @function check_proxmox
# @description Checks if this is a Proxmox node. Exits if not.
# @usage
#   check_proxmox
# @return
#   Exits 2 if not Proxmox.
check_proxmox() {
    if ! command -v pveversion &>/dev/null; then
        echo "Error: 'pveversion' command not found. Are you sure this is a Proxmox node?"
        exit 2
    fi
}

# --- Install or Prompt Function --------------------------------------------
# @function install_or_prompt
# @description Checks if a specified command is available. If not, prompts
#   the user to install it via apt-get. Exits if the user declines.
#   Also keeps track of installed packages in SESSION_INSTALLED_PACKAGES.
# @usage
#   install_or_prompt <command_name>
# @param command_name The name of the command to check and install if missing.
# @return
#   Exits 1 if user declines the installation.
install_or_prompt() {
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

# --- Prompt to Keep or Remove Installed Packages ----------------------------
# @function prompt_keep_installed_packages
# @description Prompts the user whether to keep or remove all packages that
#   were installed in this session via install_or_prompt(). If the user chooses
#   "No", each package in SESSION_INSTALLED_PACKAGES is removed.
# @usage
#   prompt_keep_installed_packages
# @return
#   Removes packages if user says "No", otherwise does nothing.
prompt_keep_installed_packages() {
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
