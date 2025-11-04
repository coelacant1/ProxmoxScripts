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
#   __prompt_user_yn__ "Continue with operation?"
#   __install_or_prompt__ "curl"
#   __prompt_keep_installed_packages__
#
# Examples:
#   # Example: Check root and Proxmox status, prompt user, then install curl:
#   source ./Prompts.sh
#   __check_root__
#   __check_proxmox__
#   if __prompt_user_yn__ "Continue with installation?"; then
#       __install_or_prompt__ "curl"
#       __prompt_keep_installed_packages__
#   fi
#
# Function Index:
#   - __check_root__
#   - __check_proxmox__
#   - __prompt_user_yn__
#   - __install_or_prompt__
#   - __prompt_keep_installed_packages__
#   - __ensure_dependencies__
#   - __require_root_and_proxmox__
#

set -euo pipefail

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

# --- __prompt_user_yn__ -------------------------------------------------------
# @function __prompt_user_yn__
# @description Prompts the user with a yes/no question and returns 0 for yes, 1 for no.
# @usage __prompt_user_yn__ "Question text?"
# @param question The question to ask the user
# @return Returns 0 if user answers yes (Y/y), 1 if user answers no (N/n) or presses Enter (default: no)
# @example_output
#   __prompt_user_yn__ "Continue with operation?" && echo "Proceeding..." || echo "Cancelled"
__prompt_user_yn__() {
    local question="$1"
    local response

    read -r -p "${question} [y/N]: " response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
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

# --- __ensure_dependencies__ -------------------------------------------------
# @function __ensure_dependencies__
# @description Verifies that the specified commands are available; installs them if missing. Supports automatic installation or interactive prompting.
# @usage __ensure_dependencies__ [--auto-install] [--quiet] <command> [<command> ...]
# @flags
#   --auto-install    Automatically install missing dependencies without prompting.
#   --quiet           Suppress status messages for dependencies that are already present.
# @example __ensure_dependencies__ jq sshpass
# @example __ensure_dependencies__ --auto-install curl rsync
__ensure_dependencies__() {
    local autoInstall=0
    local quiet=0
    local -a deps=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --auto-install)
                autoInstall=1
                shift
                ;;
            --quiet)
                quiet=1
                shift
                ;;
            --)
                shift
                deps+=("$@")
                break
                ;;
            *)
                deps+=("$1")
                shift
                ;;
        esac
    done

    if [[ ${#deps[@]} -eq 0 ]]; then
        echo "Error: __ensure_dependencies__ requires at least one command name." >&2
        return 1
    fi

    local dep
    for dep in "${deps[@]}"; do
        if command -v "$dep" &>/dev/null; then
            if [[ "$quiet" -eq 0 ]]; then
                echo "Dependency '$dep' is already installed."
            fi
            continue
        fi

        if [[ "$autoInstall" -eq 1 ]]; then
            echo "Installing missing dependency '$dep'..."
            apt-get install -y "$dep"
            SESSION_INSTALLED_PACKAGES+=("$dep")
        else
            __install_or_prompt__ "$dep"
        fi
    done
}

# --- __require_root_and_proxmox__ -------------------------------------------
# @function __require_root_and_proxmox__
# @description Convenience helper that ensures the script is run as root on a Proxmox node.
# @usage __require_root_and_proxmox__
__require_root_and_proxmox__() {
    __check_root__
    __check_proxmox__
}
