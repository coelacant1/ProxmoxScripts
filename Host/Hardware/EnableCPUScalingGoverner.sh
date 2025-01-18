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
#   ./EnableCPUScalingGoverner.sh install [performance|balanced|powersave] [opts]
#   ./EnableCPUScalingGoverner.sh remove
#   ./EnableCPUScalingGoverner.sh configure [performance|balanced|powersave] [opts]
#
# Common options for "install" or "configure":
#   -m, --min <freq>  Minimum CPU frequency (e.g. 800MHz, 1.2GHz, 1200000)
#   -M, --max <freq>  Maximum CPU frequency (e.g. 2.5GHz, 3.0GHz, 3000000)
#
# Examples:
#   ./EnableCPUScalingGoverner.sh install
#   ./EnableCPUScalingGoverner.sh install performance -m 1.2GHz -M 3.0GHz
#   ./EnableCPUScalingGoverner.sh remove
#   ./EnableCPUScalingGoverner.sh configure balanced
#   ./EnableCPUScalingGoverner.sh configure powersave --min 800MHz
#
# Further Explanation:
#   - "balanced" maps to either "ondemand" or "schedutil", whichever is available.
#   - Installing will place this script into /usr/local/bin (so it's globally accessible).
#   - Removing will attempt to restore default scaling governor (assuming 'ondemand' or 'schedutil').
#   - This script will exit on any error (set -e).
#
# Dependencies:
#   - cpupower (recommended) or sysfs-based access to CPU freq scaling.
#
# Function Index:
#   - usage
#   - set_governor
#   - do_install
#   - do_remove
#   - do_configure
#

source "$UTILITIES"

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
# We assume this script is used primarily on Proxmox. If run outside Proxmox, 
# remove or comment out check_proxmox as needed.
check_root
check_proxmox

###############################################################################
# Usage Function
###############################################################################
usage() {
  echo "Usage:"
  echo "  ${SCRIPT_NAME} install [performance|balanced|powersave] [options]"
  echo "  ${SCRIPT_NAME} remove"
  echo "  ${SCRIPT_NAME} configure [performance|balanced|powersave] [options]"
  echo
  echo "Options for \"install\" or \"configure\":"
  echo "  -m, --min <freq>  Minimum CPU frequency (e.g. 800MHz, 1.2GHz, 1200000)"
  echo "  -M, --max <freq>  Maximum CPU frequency (e.g. 2.5GHz, 3.0GHz, 3000000)"
  echo
  echo "Examples:"
  echo "  ${SCRIPT_NAME} install"
  echo "  ${SCRIPT_NAME} install performance -m 1.2GHz -M 3.0GHz"
  echo "  ${SCRIPT_NAME} remove"
  echo "  ${SCRIPT_NAME} configure balanced"
  echo "  ${SCRIPT_NAME} configure powersave --min 800MHz"
  echo
  echo "Description:"
  echo "  install:   Installs dependencies (cpupower), copies this script to /usr/local/bin,"
  echo "             and optionally sets a default governor."
  echo "  remove:    Removes cpupower (if installed by this script) and attempts to restore"
  echo "             system defaults. Also removes this script from /usr/local/bin."
  echo "  configure: Manually sets CPU governor and optional min/max frequencies."
  exit 1
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
  install_or_prompt "linux-cpupower"

  echo "Copying script to '${TARGET_PATH}'..."
  cp -f "$0" "${TARGET_PATH}"
  chmod 755 "${TARGET_PATH}"

  if [[ -n "${gov}" ]]; then
    # If user specified "balanced", map to fallback
    if [[ "${gov}" == "balanced" ]]; then
      gov="${BALANCED_FALLBACK}"
    fi
    set_governor "${gov}" "${minFreq}" "${maxFreq}"
  else
    echo "No governor specified; skipping governor configuration."
  fi

  prompt_keep_installed_packages
  echo "Install complete."
  exit 0
}

do_remove() {
  echo "Attempting to remove 'linux-cpupower' if it was installed by this script..."
  # We rely on prompt_keep_installed_packages having been called in do_install to decide.
  # If the package remains installed, we attempt to remove it here anyway.
  if command -v cpupower &>/dev/null; then
    apt-get -y remove linux-cpupower || echo "Warning: Could not remove linux-cpupower automatically."
  fi

  echo "Restoring system default governor ('${SYSTEM_DEFAULT}')..."
  set_governor "${SYSTEM_DEFAULT}"

  echo "Removing '${TARGET_PATH}'..."
  rm -f "${TARGET_PATH}"

  echo "Removal complete."
  exit 0
}

do_configure() {
  local gov="$1"
  local minFreq="$2"
  local maxFreq="$3"

  if [[ -z "${gov}" ]]; then
    echo "Error: Missing governor. Must be one of 'performance', 'balanced', or 'powersave'."
    exit 1
  fi

  if [[ "${gov}" == "balanced" ]]; then
    gov="${BALANCED_FALLBACK}"
  fi

  set_governor "${gov}" "${minFreq}" "${maxFreq}"
  exit 0
}

###############################################################################
# Main Logic
###############################################################################
if [[ $# -lt 1 ]]; then
  usage
fi

action="$1"
shift

govOpt=""
minFreq=""
maxFreq=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    performance|powersave|balanced)
      govOpt="$1"
      shift
      ;;
    -m|--min)
      minFreq="$2"
      shift 2
      ;;
    -M|--max)
      maxFreq="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: Unknown option or argument '$1'"
      usage
      ;;
  esac
done

case "${action}" in
  install)
    do_install "${govOpt}" "${minFreq}" "${maxFreq}"
    ;;
  remove)
    do_remove
    ;;
  configure)
    do_configure "${govOpt}" "${minFreq}" "${maxFreq}"
    ;;
  *)
    echo "Error: Unknown action '${action}'"
    usage
    ;;
esac
