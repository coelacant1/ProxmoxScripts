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
#   - __prompt_log__
#   - __check_root__
#   - __check_proxmox__
#   - __prompt_user_yn__
#   - __install_or_prompt__
#   - __prompt_keep_installed_packages__
#   - __ensure_dependencies__
#   - __require_root_and_proxmox__
#

# Source Logger for structured logging
if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Logger.sh" ]]; then
    # shellcheck source=Utilities/Logger.sh
    source "${UTILITYPATH}/Logger.sh"
fi

# Safe logging wrapper
__prompt_log__() {
    local level="$1"
    local message="$2"
    if declare -f __log__ >/dev/null 2>&1; then
        __log__ "$level" "$message" "PROMPT"
    fi
}

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
    __prompt_log__ "DEBUG" "Checking root privileges (EUID: $EUID)"
    if [[ $EUID -ne 0 ]]; then
        __prompt_log__ "ERROR" "Not running as root"
        echo "Error: This script must be run as root (sudo)."
        exit 1
    fi
    __prompt_log__ "DEBUG" "Root check passed"
}

# --- __check_proxmox__ ------------------------------------------------------------
# @function __check_proxmox__
# @description Checks if this is a Proxmox node. Exits if not.
# @usage __check_proxmox__
# @return Exits 2 if not Proxmox.
# @example_output If 'pveversion' is not found, the output is: "Error: 'pveversion' command not found. Are you sure this is a Proxmox node?"
__check_proxmox__() {
    __prompt_log__ "DEBUG" "Checking for Proxmox environment"
    if ! command -v pveversion &>/dev/null; then
        __prompt_log__ "ERROR" "Not a Proxmox node (pveversion not found)"
        echo "Error: 'pveversion' command not found. Are you sure this is a Proxmox node?"
        exit 2
    fi
    __prompt_log__ "DEBUG" "Proxmox check passed"
}

# --- __prompt_user_yn__ -------------------------------------------------------
# @function __prompt_user_yn__
# @description Prompts the user with a yes/no question and returns 0 for yes, 1 for no.
#              In non-interactive mode, automatically returns 0 (yes).
# @usage __prompt_user_yn__ "Question text?"
# @param question The question to ask the user
# @return Returns 0 if user answers yes (Y/y), 1 if user answers no (N/n) or presses Enter (default: no)
# @example_output
#   __prompt_user_yn__ "Continue with operation?" && echo "Proceeding..." || echo "Cancelled"
__prompt_user_yn__() {
    local question="$1"

    __prompt_log__ "DEBUG" "Prompting user: $question"

    # Auto-answer YES in non-interactive mode
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
        echo "[AUTO] $question: YES (non-interactive mode)"
        __prompt_log__ "INFO" "Auto-answered YES (non-interactive mode)"
        return 0
    fi

    local response
    read -r -p "${question} [y/N]: " response

    __prompt_log__ "DEBUG" "User response: ${response:-<empty>}"

    if [[ "$response" =~ ^[Yy]$ ]]; then
        __prompt_log__ "INFO" "User answered YES"
        return 0
    else
        __prompt_log__ "INFO" "User answered NO"
        return 1
    fi
}

# --- __install_or_prompt__ ------------------------------------------------------------
# @function __install_or_prompt__
# @description Checks if a specified command is available. If not, prompts
#   the user to install it via apt-get. Exits if the user declines.
#   In non-interactive mode, automatically installs missing packages.
#   Also keeps track of installed packages in SESSION_INSTALLED_PACKAGES.
# @usage __install_or_prompt__ <command_name>
# @param command_name The name of the command to check and install if missing.
# @return Exits 1 if user declines the installation.
# @example_output If "curl" is missing and the user declines installation, the output is: "Aborting script because 'curl' is not installed."
__install_or_prompt__() {
    local cmd="$1"

    # Skip install checks if requested (useful for testing)
    if [[ "${SKIP_INSTALL_CHECKS:-}" == "true" ]]; then
        __prompt_log__ "DEBUG" "Skipping install check for: $cmd (SKIP_INSTALL_CHECKS=true)"
        return 0
    fi

    __prompt_log__ "DEBUG" "Checking for command: $cmd"

    if ! command -v "$cmd" &>/dev/null; then
        __prompt_log__ "WARN" "Command not found: $cmd"

        # Auto-install in non-interactive mode
        if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
            echo "[AUTO] Installing '$cmd'..."
            __prompt_log__ "INFO" "Auto-installing $cmd (non-interactive mode)"
            apt-get update -qq >/dev/null 2>&1
            if apt-get install -y "$cmd" >/dev/null 2>&1; then
                SESSION_INSTALLED_PACKAGES+=("$cmd")
                __prompt_log__ "INFO" "Successfully installed: $cmd"
                return 0
            else
                __prompt_log__ "ERROR" "Failed to install: $cmd"
                return 1
            fi
        fi

        # Interactive mode - prompt user
        echo "The '$cmd' utility is required but is not installed."
        read -r -p "Would you like to install '$cmd' now? [y/N]: " response
        __prompt_log__ "DEBUG" "User response for installing $cmd: ${response:-<empty>}"

        if [[ "$response" =~ ^[Yy]$ ]]; then
            __prompt_log__ "INFO" "User chose to install: $cmd"
            apt-get install -y "$cmd"
            SESSION_INSTALLED_PACKAGES+=("$cmd")
            __prompt_log__ "INFO" "Installed: $cmd"
        else
            __prompt_log__ "ERROR" "User declined to install $cmd, aborting"
            echo "Aborting script because '$cmd' is not installed."
            exit 1
        fi
    else
        __prompt_log__ "DEBUG" "Command already available: $cmd"
    fi
}

# --- __prompt_keep_installed_packages__ ------------------------------------------------------------
# @function __prompt_keep_installed_packages__
# @description Prompts the user whether to keep or remove all packages that
#   were installed in this session via __install_or_prompt__(). If the user chooses
#   "No", each package in SESSION_INSTALLED_PACKAGES is removed.
#   In non-interactive mode, automatically keeps all installed packages.
# @usage __prompt_keep_installed_packages__
# @return Removes packages if user says "No", otherwise does nothing.
# @example_output If the user chooses "No", the output is: "Removing the packages installed in this session..." followed by "Packages removed."
__prompt_keep_installed_packages__() {
    if [[ ${#SESSION_INSTALLED_PACKAGES[@]} -eq 0 ]]; then
        __prompt_log__ "DEBUG" "No packages to clean up"
        return
    fi

    __prompt_log__ "INFO" "Cleanup check for ${#SESSION_INSTALLED_PACKAGES[@]} installed packages: ${SESSION_INSTALLED_PACKAGES[*]}"

    # Auto-keep in non-interactive mode
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
        echo "[AUTO] Keeping installed packages: ${SESSION_INSTALLED_PACKAGES[*]}"
        __prompt_log__ "INFO" "Auto-keeping packages (non-interactive mode)"
        return 0
    fi

    echo "The following packages were installed during this session:"
    printf ' - %s\n' "${SESSION_INSTALLED_PACKAGES[@]}"
    read -r -p "Do you want to KEEP these packages? [Y/n]: " response
    __prompt_log__ "DEBUG" "User response for keeping packages: ${response:-<empty>}"

    if [[ "$response" =~ ^[Nn]$ ]]; then
        echo "Removing the packages installed in this session..."
        __prompt_log__ "INFO" "User chose to remove packages: ${SESSION_INSTALLED_PACKAGES[*]}"
        apt-get remove -y "${SESSION_INSTALLED_PACKAGES[@]}"
        # Optional: apt-get purge -y "${SESSION_INSTALLED_PACKAGES[@]}"
        SESSION_INSTALLED_PACKAGES=()
        echo "Packages removed."
        __prompt_log__ "INFO" "Packages removed successfully"
    else
        echo "Keeping all installed packages."
        __prompt_log__ "INFO" "User chose to keep packages"
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

    __prompt_log__ "DEBUG" "Ensuring dependencies: $*"

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
        __prompt_log__ "ERROR" "No dependencies specified"
        echo "Error: __ensure_dependencies__ requires at least one command name." >&2
        return 1
    fi

    __prompt_log__ "INFO" "Checking ${#deps[@]} dependencies (auto-install: $autoInstall, quiet: $quiet)"

    local dep
    local missing_count=0
    for dep in "${deps[@]}"; do
        if command -v "$dep" &>/dev/null; then
            if [[ "$quiet" -eq 0 ]]; then
                echo "Dependency '$dep' is already installed."
            fi
            __prompt_log__ "DEBUG" "Dependency present: $dep"
            continue
        fi

        ((missing_count += 1))
        __prompt_log__ "WARN" "Missing dependency: $dep"

        if [[ "$autoInstall" -eq 1 ]]; then
            echo "Installing missing dependency '$dep'..."
            __prompt_log__ "INFO" "Auto-installing: $dep"
            apt-get install -y "$dep"
            SESSION_INSTALLED_PACKAGES+=("$dep")
            __prompt_log__ "INFO" "Installed: $dep"
        else
            __install_or_prompt__ "$dep"
        fi
    done

    __prompt_log__ "INFO" "Dependency check complete (missing: $missing_count)"
}

# --- __require_root_and_proxmox__ -------------------------------------------
# @function __require_root_and_proxmox__
# @description Convenience helper that ensures the script is run as root on a Proxmox node.
# @usage __require_root_and_proxmox__
__require_root_and_proxmox__() {
    __prompt_log__ "DEBUG" "Checking root and Proxmox requirements"
    __check_root__
    __check_proxmox__
    __prompt_log__ "DEBUG" "All requirements met"
}

###############################################################################
# Script notes:
###############################################################################
# Last checked: YYYY-MM-DD
#
# Changes:
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

