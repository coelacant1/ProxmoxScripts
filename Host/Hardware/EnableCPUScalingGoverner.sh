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
    for cpuDir in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
      if [[ -w "${cpuDir}/scaling_governor" ]]; then
        echo "${gov}" > "${cpuDir}/scaling_governor" 2>/dev/null || {
          echo "Error: Failed to set governor via sysfs."
          exit 1
        }
      fi
      if [[ -n "${minFreq}" && -w "${cpuDir}/scaling_min_freq" ]]; then
        echo "${minFreq}" > "${cpuDir}/scaling_min_freq"
      fi
      if [[ -n "${maxFreq}" && -w "${cpuDir}/scaling_max_freq" ]]; then
        echo "${maxFreq}" > "${cpuDir}/scaling_max_freq"
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
    install|remove|configure)
      ;;
    *)
      echo "Error: Unknown action '${ACTION}'"
      echo "Valid actions: install, remove, configure"
      exit 64
      ;;
  esac

  # Validate governor if provided
  if [[ -n "$GOVERNOR" ]]; then
    case "${GOVERNOR}" in
      performance|powersave|balanced)
        ;;
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

# Testing status:
#   - 2025-11-04: Refactored to use ArgumentParser.sh declarative parsing
#   - Removed manual usage() function
#   - Removed manual argument parsing in main
#   - Now uses __parse_args__ with automatic validation
#   - Handles subcommand pattern (install/remove/configure)
