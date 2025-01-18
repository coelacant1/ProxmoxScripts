#!/bin/bash
#
# QuickDiagnostic.sh
#
# This script checks for current errors in the Proxmox system, including faults
# in storage, memory, CPU, networking, Ceph, and system logs. It provides a succinct
# summary to quickly diagnose any issues with the system.
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
# Function Index:
#   - check_storage_errors
#   - check_memory_errors
#   - check_cpu_errors
#   - check_network_errors
#   - check_system_log_errors
#

source "$UTILITIES"

###############################################################################
# FUNCTIONS
###############################################################################

###############################################################################
# Check storage errors and usage
###############################################################################
check_storage_errors() {
    echo "Checking storage errors..."

    # Use ZFS commands if available
    local zpoolStatus=""
    if command -v zpool &>/dev/null; then
        zpoolStatus="$(zpool status 2>/dev/null | grep -i 'FAULTED\|DEGRADED' || true)"
    fi

    # Use Ceph commands if available
    local cephStatus=""
    if command -v ceph &>/dev/null; then
        cephStatus="$(ceph health 2>/dev/null | grep -i 'HEALTH_ERR\|HEALTH_WARN' || true)"
    fi

    # Basic usage via df
    local storageUsage
    storageUsage="$(df -h | awk '$5+0 > 90 {print "Warning: " $6 " is " $5 " full."}')"

    # LVM locks if lvs is installed
    local lockedStorage=""
    if command -v lvs &>/dev/null; then
        lockedStorage="$(lvs -o+lock_args 2>/dev/null | grep -i 'lock' || true)"
    fi

    if [[ -n "$zpoolStatus" ]]; then
        echo "Storage errors detected in ZFS:"
        echo "$zpoolStatus"
    elif [[ -n "$cephStatus" ]]; then
        echo "Storage errors detected in Ceph:"
        echo "$cephStatus"
    else
        echo "No ZFS/Ceph errors found."
    fi

    if [[ -n "$storageUsage" ]]; then
        echo "Storage usage warning:"
        echo "$storageUsage"
    else
        echo "No storage usage issues found."
    fi

    if [[ -n "$lockedStorage" ]]; then
        echo "Locked storage detected:"
        echo "$lockedStorage"
    else
        echo "No locked storage found."
    fi
}

###############################################################################
# Check memory errors and usage
###############################################################################
check_memory_errors() {
    echo "Checking memory errors..."
    local memoryErrors
    memoryErrors="$(dmesg | grep -iE 'memory error|out of memory|oom-killer' || true)"

    local memoryUsage
    memoryUsage="$(free -m | awk '/Mem:/ {if ($3/$2 * 100 > 90) printf "Warning: Memory usage is at %.1f%%\n", ($3/$2 * 100)}')"

    if [[ -n "$memoryErrors" ]]; then
        echo "Memory errors detected:"
        echo "$memoryErrors"
    else
        echo "No memory errors found."
    fi

    if [[ -n "$memoryUsage" ]]; then
        echo "Memory usage warning:"
        echo "$memoryUsage"
        echo "Processes consuming the most memory:"
        ps -eo pid,ppid,cmd,%mem --sort=-%mem | head -n 5
    else
        echo "No memory usage issues found."
    fi
}

###############################################################################
# Check CPU errors and usage
###############################################################################
check_cpu_errors() {
    echo "Checking CPU errors..."
    local cpuErrors
    cpuErrors="$(dmesg | grep -iE 'cpu error|thermal throttling|overheating' || true)"

    # Parse 'top' in batch mode, check %us usage if it’s > 90
    local cpuUsage
    cpuUsage="$(top -bn1 | awk '/^%Cpu/ {if ($2 > 90) print "Warning: CPU usage is at " $2 "%"}')"

    if [[ -n "$cpuErrors" ]]; then
        echo "CPU errors detected:"
        echo "$cpuErrors"
    else
        echo "No CPU errors found."
    fi

    if [[ -n "$cpuUsage" ]]; then
        echo "CPU usage warning:"
        echo "$cpuUsage"
        echo "Processes consuming the most CPU:"
        ps -eo pid,ppid,cmd,%cpu --sort=-%cpu | head -n 5
    else
        echo "No CPU usage issues found."
    fi
}

###############################################################################
# Check network errors
###############################################################################
check_network_errors() {
    echo "Checking network errors..."
    local networkErrors
    networkErrors="$(dmesg | grep -iE 'network error|link is down|nic error|carrier lost' || true)"

    if [[ -n "$networkErrors" ]]; then
        echo "Network errors detected:"
        echo "$networkErrors"
    else
        echo "No network errors found."
    fi
}

###############################################################################
# Check system logs for errors
###############################################################################
check_system_log_errors() {
    echo "Checking system logs for errors..."
    if command -v journalctl &>/dev/null; then
        local syslogErrors
        syslogErrors="$(journalctl -p err -b | grep -i 'error' || true)"
        if [[ -n "$syslogErrors" ]]; then
            echo "Errors detected in system logs:"
            echo "$syslogErrors"
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
echo "Starting system error check..."

# Ensure this is a Proxmox node, ensure script is run as root
check_root
check_proxmox

# Prompt to install packages not in a default Proxmox 8 install
# If user declines, relevant checks will be skipped
install_or_prompt "zfsutils-linux"
install_or_prompt "lvm2"

# Run checks
check_storage_errors
check_memory_errors
check_cpu_errors
check_network_errors
check_system_log_errors

echo "System error check completed!"

# Prompt to remove installed packages if any were installed during this session
prompt_keep_installed_packages

###############################################################################
# Testing status
###############################################################################
# Tested single-node
