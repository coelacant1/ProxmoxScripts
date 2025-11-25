#!/bin/bash
#
# EnableCPUScalingGoverner.sh
#
# A script to manage CPU frequency scaling governor on a Proxmox (or general Linux) system.
# Supports three major actions:
#   1. install   - Installs dependencies (cpupower) and this script, and sets an optional default governor.
#   2. remove    - Removes cpupower (if installed via install) and restores system defaults.
#   3. configure - Adjust CPU governor ("performance", "balanced", or "powersave") with optional min/max frequencies.
#
# Usage:
#   EnableCPUScalingGoverner.sh install
#   EnableCPUScalingGoverner.sh install performance -m 1.2GHz -M 3.0GHz
#   EnableCPUScalingGoverner.sh remove
#   EnableCPUScalingGoverner.sh configure balanced
#   EnableCPUScalingGoverner.sh configure powersave --min 800MHz
#
# Arguments:
#   action              - Action to perform: install, remove, or configure
#   governor            - Optional governor: performance, balanced, or powersave
#   -m, --min <freq>    - Minimum CPU frequency (e.g. 800MHz, 1.2GHz, 1200000)
#   -M, --max <freq>    - Maximum CPU frequency (e.g. 2.5GHz, 3.0GHz, 3000000)
#
# Notes:
#   - "balanced" maps to either "ondemand" or "schedutil", whichever is available.
#   - Installing will place this script into /usr/local/bin (so it's globally accessible).
#   - Removing will attempt to restore default scaling governor (assuming 'ondemand' or 'schedutil').
#
# Dependencies:
#   - cpupower (recommended) or sysfs-based access to CPU freq scaling.
#
# Function Index:
#   - convert_freq_to_khz
#   - set_governor
#   - do_install
#   - do_remove
#   - do_configure
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

###############################################################################
# Globals / Defaults
###############################################################################

SCRIPT_NAME="EnableCPUScalingGoverner.sh"
TARGET_PATH="/usr/local/bin/${SCRIPT_NAME}"
BALANCED_FALLBACK="ondemand"

if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors ]]; then
    if grep -qw "schedutil" /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors; then
        BALANCED_FALLBACK="schedutil"
    fi
fi

SYSTEM_DEFAULT="${BALANCED_FALLBACK}"

###############################################################################
# Check Requirements
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# convert_freq_to_khz
###############################################################################
# Convert frequency from human-readable format to kHz integer
# Usage: convert_freq_to_khz <freq>
# Examples:
#   "1.2GHz" -> "1200000"
#   "800MHz" -> "800000"
#   "1200000" -> "1200000" (already in kHz)
convert_freq_to_khz() {
    local freq="$1"
    local khz_value

    # If already a plain integer (assumed kHz), return as-is
    if [[ "$freq" =~ ^[0-9]+$ ]]; then
        echo "$freq"
        return
    fi

    # Parse value and unit
    if [[ "$freq" =~ ^([0-9.]+)([GMk]?Hz)$ ]]; then
        local value="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"

        case "$unit" in
            GHz)
                # Convert GHz to kHz: multiply by 1,000,000
                khz_value=$(awk "BEGIN {printf \"%.0f\", $value * 1000000}")
                ;;
            MHz)
                # Convert MHz to kHz: multiply by 1,000
                khz_value=$(awk "BEGIN {printf \"%.0f\", $value * 1000}")
                ;;
            kHz)
                # kHz stays as-is
                khz_value=$(awk "BEGIN {printf \"%.0f\", $value}")
                ;;
            Hz)
                # Hz converted to kHz (divide by 1000)
                khz_value=$(awk "BEGIN {printf \"%.0f\", $value / 1000}")
                ;;
            *)
                echo "Error: Unknown frequency unit in '$freq'" >&2
                return 1
                ;;
        esac
        echo "$khz_value"
    else
        echo "Error: Invalid frequency format '$freq'" >&2
        return 1
    fi
}

###############################################################################
# set_governor
###############################################################################
# Usage: set_governor <governor> [min_freq] [max_freq]
set_governor() {
    local gov="$1"
    local minFreq="$2"
    local maxFreq="$3"

    if command -v cpupower &>/dev/null; then
        cpupower frequency-set -g "${gov}" >/dev/null 2>&1 || {
            echo "Error: Failed to set governor to '${gov}' via cpupower."
            exit 1
        }
        [[ -n "${minFreq}" ]] && cpupower frequency-set -d "${minFreq}" >/dev/null 2>&1
        [[ -n "${maxFreq}" ]] && cpupower frequency-set -u "${maxFreq}" >/dev/null 2>&1
    else
        echo "Warning: cpupower not found, using sysfs fallback..."

        # Convert frequencies to kHz for sysfs
        local minFreqKhz maxFreqKhz
        if [[ -n "${minFreq}" ]]; then
            minFreqKhz=$(convert_freq_to_khz "${minFreq}") || {
                echo "Error: Failed to convert min frequency '${minFreq}'"
                exit 1
            }
        fi
        if [[ -n "${maxFreq}" ]]; then
            maxFreqKhz=$(convert_freq_to_khz "${maxFreq}") || {
                echo "Error: Failed to convert max frequency '${maxFreq}'"
                exit 1
            }
        fi

        for cpuDir in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
            if [[ -w "${cpuDir}/scaling_governor" ]]; then
                echo "${gov}" >"${cpuDir}/scaling_governor" 2>/dev/null || {
                    echo "Error: Failed to set governor via sysfs."
                    exit 1
                }
            fi
            if [[ -n "${minFreqKhz}" && -w "${cpuDir}/scaling_min_freq" ]]; then
                echo "${minFreqKhz}" >"${cpuDir}/scaling_min_freq"
            fi
            if [[ -n "${maxFreqKhz}" && -w "${cpuDir}/scaling_max_freq" ]]; then
                echo "${maxFreqKhz}" >"${cpuDir}/scaling_max_freq"
            fi
        done
    fi

    echo "CPU scaling governor set to '${gov}'."
    [[ -n "${minFreq}" ]] && echo "Min frequency set to: ${minFreq}"
    [[ -n "${maxFreq}" ]] && echo "Max frequency set to: ${maxFreq}"
}

###############################################################################
# Actions
###############################################################################
do_install() {
    local gov="$1"
    local minFreq="$2"
    local maxFreq="$3"

    echo "Installing 'linux-cpupower' if not already installed..."
    __install_or_prompt__ "linux-cpupower"

    echo "Copying '${SCRIPT_NAME}' to ${TARGET_PATH} ..."
    cp "$0" "${TARGET_PATH}"
    chmod +x "${TARGET_PATH}"
    echo "Installed to: ${TARGET_PATH}"

    if [[ -n "${gov}" ]]; then
        set_governor "${gov}" "${minFreq}" "${maxFreq}"
    else
        echo "No default governor specified, leaving system defaults."
    fi
    exit 0
}

do_remove() {
    echo "Uninstalling 'linux-cpupower' (if installed by this script)..."
    apt-get remove -y linux-cpupower 2>/dev/null || echo "Package not found or already removed."

    echo "Attempting to restore system default governor: ${SYSTEM_DEFAULT}"
    set_governor "${SYSTEM_DEFAULT}" "" ""

    if [[ -f "${TARGET_PATH}" ]]; then
        echo "Removing script from ${TARGET_PATH} ..."
        rm -f "${TARGET_PATH}"
    fi

    echo "Remove operation complete."
    exit 0
}

do_configure() {
    local gov="$1"
    local minFreq="$2"
    local maxFreq="$3"

    if [[ -z "${gov}" ]]; then
        echo "Error: No governor specified for 'configure' action."
        echo "Usage: ${SCRIPT_NAME} configure [performance|balanced|powersave] [options]"
        exit 1
    fi

    set_governor "${gov}" "${minFreq}" "${maxFreq}"
    exit 0
}

###############################################################################
# Main
###############################################################################
main() {
    # Parse arguments using ArgumentParser
    __parse_args__ "action:string governor:string:? -m|--min:string:? -M|--max:string:?" "$@"

    # Validate action
    case "${ACTION}" in
        install | remove | configure) ;;
        *)
            echo "Error: Unknown action '${ACTION}'"
            echo "Valid actions: install, remove, configure"
            exit 64
            ;;
    esac

    # Validate governor if provided
    if [[ -n "$GOVERNOR" ]]; then
        case "${GOVERNOR}" in
            performance | powersave | balanced) ;;
            *)
                echo "Error: Unknown governor '${GOVERNOR}'"
                echo "Valid governors: performance, balanced, powersave"
                exit 64
                ;;
        esac

        # Convert "balanced" to actual governor name
        if [[ "${GOVERNOR}" == "balanced" ]]; then
            GOVERNOR="${BALANCED_FALLBACK}"
        fi
    fi

    # Execute action
    case "${ACTION}" in
        install)
            do_install "${GOVERNOR}" "${MIN}" "${MAX}"
            ;;
        remove)
            do_remove
            ;;
        configure)
            do_configure "${GOVERNOR}" "${MIN}" "${MAX}"
            ;;
    esac
}

main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-04: Refactored to use ArgumentParser.sh declarative parsing
# - 2025-11-20: Removed manual usage() function
# - 2025-11-20: Removed manual argument parsing in main
# - 2025-11-20: Now uses __parse_args__ with automatic validation
# - 2025-11-20: Handles subcommand pattern (install/remove/configure)
# - 2025-11-20: Added frequency conversion for sysfs fallback (kHz integer format)
# - 2025-11-20: Added Communication.sh and error trap per CONTRIBUTING.md Section 3.9
#
# Fixes:
# -
#
# Known issues:
# -
#

