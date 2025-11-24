#!/bin/bash
#
# PortScan.sh
#
# Scans TCP ports using nmap.
# Can be run from any Linux system with nmap installed.
#
# Usage:
#   PortScan.sh <host> [<host2> ...]
#   PortScan.sh all   (only works from Proxmox cluster node)
#
# Arguments:
#   host - Target host IP or hostname
#   all - Scan all Proxmox cluster nodes (requires Proxmox environment)
#
# Examples:
#   PortScan.sh 192.168.1.50
#   PortScan.sh 192.168.1.50 192.168.1.51
#   PortScan.sh all   (from Proxmox node only)
#
# Notes:
#   - Can be run from any Linux system (not just Proxmox)
#   - Root privileges recommended for accurate scanning
#   - The 'all' option only works when run from a Proxmox cluster node
#   - Requires nmap package (will prompt to install if missing)
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Note: Variable arguments handled manually (hosts or "all")
if [[ $# -lt 1 ]]; then
    __err__ "Missing required argument"
    echo "Usage: $0 <host> [<host2> ...] | all"
    exit 64
fi

# --- main --------------------------------------------------------------------
main() {
    # Note: root recommended for SYN scans, but not strictly required
    # Remove __check_proxmox__ - these are general security tools, not Proxmox-specific

    __install_or_prompt__ "nmap"

    local -a targets

    if [[ "$1" == "all" ]]; then
        # Only check cluster if "all" is used (requires Proxmox environment)
        if ! __check_proxmox__ 2>/dev/null; then
            __err__ "The 'all' option requires running from a Proxmox cluster node"
            __err__ "To scan multiple hosts, specify them individually:"
            __err__ "  $0 192.168.1.50 192.168.1.51 192.168.1.52"
            exit 1
        fi

        __check_cluster_membership__

        __info__ "Discovering cluster nodes"
        mapfile -t targets < <(__get_remote_node_ips__)

        if [[ ${#targets[@]} -eq 0 ]]; then
            __err__ "No cluster nodes discovered"
            exit 1
        fi

        __ok__ "Found ${#targets[@]} cluster node(s)"
        for ip in "${targets[@]}"; do
            echo "  - $ip"
        done
        echo
    else
        targets=("$@")
    fi

    __warn__ "Starting port scan on ${#targets[@]} host(s)"
    __warn__ "Use responsibly and only with permission"
    echo

    # Create output directory
    local output_dir
    local default_dir

    # Use /root if running as root, otherwise use $HOME
    if [[ $EUID -eq 0 ]]; then
        default_dir="/root/security_scans"
    else
        default_dir="${HOME}/security_scans"
    fi

    output_dir="${default_dir}/portscan_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$output_dir"
    __info__ "Scan results will be saved to: $output_dir"
    echo

    local scanned=0
    local failed=0

    # Proxmox standard ports for reference
    __info__ "Standard Proxmox ports:"
    echo "  - 22   (SSH)"
    echo "  - 111  (rpcbind)"
    echo "  - 3128 (SPICE proxy)"
    echo "  - 5900-5999 (VNC)"
    echo "  - 8006 (Web UI)"
    echo "  - 85   (pvedaemon)"
    echo

    for host in "${targets[@]}"; do
        echo "================================================================"
        __info__ "Scanning: $host"
        echo "================================================================"

        local output_file="${output_dir}/${host//[^a-zA-Z0-9._-]/_}.txt"

        # Run scan with timeout and capture output
        # Note: Full port scan (-p-) can take a while, using aggressive timing
        if timeout 1800 nmap -p- --open -n -T4 \
            --host-timeout 900s \
            --max-retries 1 \
            "${host}" > "$output_file" 2>&1; then
            __ok__ "Scan completed: $host"

            # Show summary of open ports
            local open_ports
            open_ports=$(grep -oP '^\d+/tcp\s+open' "$output_file" | wc -l)
            __info__ "Found $open_ports open port(s)"
            __info__ "Results: $output_file"

            scanned=$((scanned + 1))
        else
            local exit_code=$?
            if [[ $exit_code -eq 124 ]]; then
                __warn__ "Scan timed out after 30 minutes: $host"
            else
                __warn__ "Scan failed: $host (exit code: $exit_code)"
            fi
            failed=$((failed + 1))
        fi
        echo
    done

    echo "================================================================"
    __ok__ "Port scan completed"
    echo
    __info__ "Summary:"
    echo "  Total targets: ${#targets[@]}"
    echo "  Successful:    $scanned"
    echo "  Failed:        $failed"
    echo "  Results saved: $output_dir"
    echo

    # Generate summary report
    local summary_file="${output_dir}/SUMMARY.txt"
    {
        echo "Proxmox Port Scan Summary"
        echo "========================="
        echo "Scan Date: $(date)"
        echo "Total Targets: ${#targets[@]}"
        echo "Successful: $scanned"
        echo "Failed: $failed"
        echo ""
        echo "Scanned Hosts:"
        for host in "${targets[@]}"; do
            echo "  - $host"
        done
        echo ""
        echo "Individual scan results are in separate files."
        echo ""
        echo "Expected Proxmox Ports:"
        echo "  - 22   (SSH)"
        echo "  - 111  (rpcbind)"
        echo "  - 3128 (SPICE proxy)"
        echo "  - 5900-5999 (VNC)"
        echo "  - 8006 (Web UI)"
        echo "  - 85   (pvedaemon)"
        echo ""
        echo "Review each file for complete port listings."
    } > "$summary_file"

    __ok__ "Summary report: $summary_file"
    echo

    __prompt_keep_installed_packages__

    if [[ $failed -gt 0 ]]; then
        exit 1
    fi
}

main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-21: Adapted to run from any Linux system (not just Proxmox)
# - 2025-11-21: Enhanced with output saving, timeouts, summary reports
# - 2025-11-20: Deep technical analysis performed
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: Hybrid parsing for "all" or variable hosts
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-21: Removed mandatory Proxmox requirement (only needed for 'all' option)
# - 2025-11-21: Removed mandatory root requirement (recommended for SYN scans)
# - 2025-11-21: Output directory adapts to user context ($HOME vs /root)
# - 2025-11-21: Added output capture to timestamped directory
# - 2025-11-21: Added 30-minute timeout per host with aggressive timing (-T4)
# - 2025-11-21: Added Proxmox standard ports reference
# - 2025-11-21: Added summary report generation
# - 2025-11-21: Added failed counter for proper exit code
# - 2025-11-21: Added open port count display per host
# - 2025-11-21: Improved output formatting and progress reporting
# - 2025-11-20: Fixed arithmetic increment syntax (line 84) - changed ((scanned += 1)) to scanned=$((scanned + 1))
#
# Known issues:
# -
#

