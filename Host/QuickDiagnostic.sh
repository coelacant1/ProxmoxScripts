#!/bin/bash
#
# QuickDiagnostic.sh
#
# This script checks for current errors in the Proxmox system, including faults in storage,
# memory, CPU, networking, Ceph, and system logs. It provides a succinct summary to quickly
# diagnose any issues with the system.
#
# Usage:
#   ./QuickDiagnostic.sh
#
# Example:
#   ./QuickDiagnostic.sh
#
# Notes:
#   - Must be run as root on a Proxmox node.
#   - If you're using ZFS, Ceph, or LVM, this script attempts to check for related errors.
#   - It also checks memory, CPU, network, and system logs for critical errors or warnings.
#   - The script uses standard Linux tools (dmesg, free, ps, top, journalctl) to gather info.
#

set -e

# -----------------------------------------------------------------------------
# @function find_utilities_script
# @description
#   Finds the root directory of the scripts folder by traversing upward until
#   it finds a folder containing a Utilities subfolder.
#   Returns the full path to Utilities/Utilities.sh if found, or exits with an
#   error if not found within 15 levels.
# -----------------------------------------------------------------------------
find_utilities_script() {
  # Check current directory first
  if [[ -d "./Utilities" ]]; then
    echo "./Utilities"
    return 0
  fi

  local rel_path=""
  for _ in {1..15}; do
    cd ..
    # If rel_path is empty, set it to '..' else prepend '../'
    if [[ -z "$rel_path" ]]; then
      rel_path=".."
    else
      rel_path="../$rel_path"
    fi

    if [[ -d "./Utilities" ]]; then
      echo "$rel_path/Utilities"
      return 0
    fi
  done

  echo "Error: Could not find 'Utilities' folder within 15 levels." >&2
  exit 1
}

###############################################################################
# LOCATE AND SOURCE UTILITIES
###############################################################################
UTILITIES_DIR="$(find_utilities_script)"
# shellcheck source=/dev/null
source "${UTILITIES_DIR}/Utilities.sh"

###############################################################################
# FUNCTIONS
###############################################################################

# --- Check storage errors and usage -----------------------------------------
check_storage_errors() {
    echo "Checking storage errors..."

    # Use ZFS commands if available
    local zpool_status=""
    if command -v zpool &>/dev/null; then
        zpool_status=$(zpool status 2>/dev/null | grep -i 'FAULTED\|DEGRADED' || true)
    fi

    # Use Ceph commands if available
    local ceph_status=""
    if command -v ceph &>/dev/null; then
        ceph_status=$(ceph health 2>/dev/null | grep -i 'HEALTH_ERR\|HEALTH_WARN' || true)
    fi

    # Basic usage via df
    local storage_usage
    storage_usage=$(df -h | awk '$5+0 > 90 {print "Warning: " $6 " is " $5 " full."}')

    # LVM locks if lvs is installed
    local locked_storage=""
    if command -v lvs &>/dev/null; then
        locked_storage=$(lvs -o+lock_args 2>/dev/null | grep -i 'lock' || true)
    fi

    if [[ -n "$zpool_status" ]]; then
        echo "Storage errors detected in ZFS:"
        echo "$zpool_status"
    elif [[ -n "$ceph_status" ]]; then
        echo "Storage errors detected in Ceph:"
        echo "$ceph_status"
    else
        echo "No ZFS/Ceph errors found."
    fi

    if [[ -n "$storage_usage" ]]; then
        echo "Storage usage warning:"
        echo "$storage_usage"
    else
        echo "No storage usage issues found."
    fi

    if [[ -n "$locked_storage" ]]; then
        echo "Locked storage detected:"
        echo "$locked_storage"
    else
        echo "No locked storage found."
    fi
}

# --- Check memory errors and usage ------------------------------------------
check_memory_errors() {
    echo "Checking memory errors..."
    # Filter relevant lines from dmesg
    local memory_errors
    memory_errors=$(dmesg | grep -iE 'memory error|out of memory|oom-killer' || true)

    # Memory usage check
    local memory_usage
    memory_usage=$(free -m | awk '/Mem:/ {if ($3/$2 * 100 > 90) printf "Warning: Memory usage is at %.1f%%\n", ($3/$2 * 100)}')

    if [[ -n "$memory_errors" ]]; then
        echo "Memory errors detected:"
        echo "$memory_errors"
    else
        echo "No memory errors found."
    fi

    if [[ -n "$memory_usage" ]]; then
        echo "Memory usage warning:"
        echo "$memory_usage"
        echo "Processes consuming the most memory:"
        ps -eo pid,ppid,cmd,%mem --sort=-%mem | head -n 5
    else
        echo "No memory usage issues found."
    fi
}

# --- Check CPU errors and usage ---------------------------------------------
check_cpu_errors() {
    echo "Checking CPU errors..."
    local cpu_errors
    cpu_errors=$(dmesg | grep -iE 'cpu error|thermal throttling|overheating' || true)

    # We parse top in batch mode, then parse the %us (user) usage if it’s > 90
    # Adjust if you prefer to check total usage instead of user usage
    local cpu_usage
    cpu_usage=$(top -bn1 | awk '/^%Cpu/ {if ($2 > 90) print "Warning: CPU usage is at " $2 "%"}')

    if [[ -n "$cpu_errors" ]]; then
        echo "CPU errors detected:"
        echo "$cpu_errors"
    else
        echo "No CPU errors found."
    fi

    if [[ -n "$cpu_usage" ]]; then
        echo "CPU usage warning:"
        echo "$cpu_usage"
        echo "Processes consuming the most CPU:"
        ps -eo pid,ppid,cmd,%cpu --sort=-%cpu | head -n 5
    else
        echo "No CPU usage issues found."
    fi
}

# --- Check network errors ---------------------------------------------------
check_network_errors() {
    echo "Checking network errors..."
    local network_errors
    network_errors=$(dmesg | grep -iE 'network error|link is down|nic error|carrier lost' || true)

    if [[ -n "$network_errors" ]]; then
        echo "Network errors detected:"
        echo "$network_errors"
    else
        echo "No network errors found."
    fi
}

# --- Check system logs for errors ------------------------------------------
check_system_log_errors() {
    echo "Checking system logs for errors..."
    # We check priority=err from current boot, then filter lines containing "error" (case-insensitive)
    if command -v journalctl &>/dev/null; then
        local syslog_errors
        syslog_errors=$(journalctl -p err -b | grep -i 'error' || true)
        if [[ -n "$syslog_errors" ]]; then
            echo "Errors detected in system logs:"
            echo "$syslog_errors"
        else
            echo "No errors found in system logs."
        fi
    else
        echo "journalctl not available. Skipping system log check."
    fi
}

###############################################################################
# MAIN
###############################################################################
main() {
    echo "Starting system error check..."

    # 1. Check Proxmox environment and root
    check_proxmox_and_root

    # 2. Install or prompt for relevant commands if not found
    #    (Some commands like 'dmesg', 'df', 'free', 'ps', and 'top' are typically core utilities
    #     and might not have separate packages. We'll try for zfsutils, ceph-common, lvm2, and systemd.)
    if ! command -v zpool &>/dev/null; then
      echo "ZFS tools not found (zpool). Skipping ZFS checks unless installed."
    fi
    if ! command -v ceph &>/dev/null; then
      echo "Ceph tools not found (ceph). Skipping Ceph checks unless installed."
    fi
    if ! command -v lvs &>/dev/null; then
      echo "LVM tools not found (lvs). Skipping LVM lock checks unless installed."
    fi
    # journalctl is generally part of systemd, which is standard on most PVE systems

    # 3. Run checks
    check_storage_errors
    check_memory_errors
    check_cpu_errors
    check_network_errors
    check_system_log_errors

    echo "System error check completed!"

    # 4. Prompt to remove installed packages if any were installed during this session
    prompt_keep_installed_packages
}

main
