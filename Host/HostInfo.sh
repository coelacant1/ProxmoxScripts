#!/bin/bash
#
# HostInfo.sh
#
# Comprehensive Proxmox host information display
#
# Usage:
#   HostInfo.sh [--json]
#
# Examples:
#   HostInfo.sh
#   HostInfo.sh --json
#
# Function Index:
#   - get_cpu_info
#   - get_memory_info
#   - get_storage_info
#   - get_network_info
#   - get_pcie_devices
#   - get_proxmox_info
#   - display_info
#   - display_json
#   - main
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export UTILITYPATH="${UTILITYPATH:-$REPO_ROOT/Utilities}"

# shellcheck source=Utilities/ArgumentParser.sh
source "$UTILITYPATH/ArgumentParser.sh" 2>/dev/null || {
    echo "Error: Cannot find ArgumentParser.sh"
    exit 1
}
    echo "Error: Cannot find Communication.sh"
    exit 1
}
# shellcheck source=Utilities/Prompts.sh
source "$UTILITYPATH/Prompts.sh" 2>/dev/null || {
    echo "Error: Cannot find Prompts.sh"
    exit 1
}

export -f __check_root__ 2>/dev/null || true
export -f __check_proxmox__ 2>/dev/null || true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Parse arguments with ArgumentParser
__parse_args__ "--json:flag" "$@"

# --- get_cpu_info -------------------------------------------------------------
# @function get_cpu_info
# @description Retrieves detailed CPU information
get_cpu_info() {
    local cpu_model cpu_cores cpu_threads cpu_mhz cpu_cache cpu_flags

    cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    cpu_cores=$(lscpu | grep "^Core(s) per socket" | cut -d: -f2 | xargs)
    local sockets=$(lscpu | grep "^Socket(s)" | cut -d: -f2 | xargs)
    cpu_threads=$(lscpu | grep "^CPU(s):" | head -1 | cut -d: -f2 | xargs)
    cpu_mhz=$(lscpu | grep "CPU max MHz" | cut -d: -f2 | xargs || echo "N/A")
    cpu_cache=$(lscpu | grep "L3 cache" | cut -d: -f2 | xargs || echo "N/A")

    # CPU flags of interest
    local virtualization=$(lscpu | grep -E "Virtualization|VT-x|AMD-V" | cut -d: -f2 | xargs || echo "None")

    echo "CPU_MODEL|$cpu_model"
    echo "CPU_SOCKETS|$sockets"
    echo "CPU_CORES|$cpu_cores"
    echo "CPU_THREADS|$cpu_threads"
    echo "CPU_MHZ|$cpu_mhz"
    echo "CPU_CACHE|$cpu_cache"
    echo "CPU_VIRT|$virtualization"
}

# --- get_memory_info ----------------------------------------------------------
# @function get_memory_info
# @description Retrieves memory information including type, speed, and channels
get_memory_info() {
    local total_mem used_mem free_mem available_mem mem_type mem_speed

    # Basic memory info
    total_mem=$(free -h | awk '/^Mem:/ {print $2}')
    used_mem=$(free -h | awk '/^Mem:/ {print $3}')
    free_mem=$(free -h | awk '/^Mem:/ {print $4}')
    available_mem=$(free -h | awk '/^Mem:/ {print $7}')

    # Detailed memory info from dmidecode
    if command -v dmidecode &>/dev/null; then
        mem_type=$(dmidecode -t memory 2>/dev/null | grep -m1 "Type:" | grep -v "Type Detail" | cut -d: -f2 | xargs || echo "Unknown")
        mem_speed=$(dmidecode -t memory 2>/dev/null | grep -m1 "Speed:" | grep -v "Configured" | cut -d: -f2 | xargs || echo "Unknown")
        local mem_channels=$(dmidecode -t memory 2>/dev/null | grep -c "Memory Device" || echo "Unknown")
        local mem_sticks=$(dmidecode -t memory 2>/dev/null | grep "Size:" | grep -v "No Module Installed" | grep -vc "^$" || echo "0")
    else
        mem_type="Unknown"
        mem_speed="Unknown"
        mem_channels="Unknown"
        mem_sticks="Unknown"
    fi

    echo "MEM_TOTAL|$total_mem"
    echo "MEM_USED|$used_mem"
    echo "MEM_FREE|$free_mem"
    echo "MEM_AVAILABLE|$available_mem"
    echo "MEM_TYPE|$mem_type"
    echo "MEM_SPEED|$mem_speed"
    echo "MEM_CHANNELS|$mem_channels"
    echo "MEM_STICKS|$mem_sticks"
}

# --- get_storage_info ---------------------------------------------------------
# @function get_storage_info
# @description Retrieves storage device and filesystem information
get_storage_info() {
    # Block devices
    echo "STORAGE_DEVICES_START"
    lsblk -dno NAME,SIZE,TYPE,MODEL 2>/dev/null | while read -r line; do
        echo "DEVICE|$line"
    done
    echo "STORAGE_DEVICES_END"

    # Filesystem usage
    echo "STORAGE_FS_START"
    df -h -t ext4 -t xfs -t zfs -t btrfs 2>/dev/null | tail -n +2 | while read -r line; do
        echo "FS|$line"
    done
    echo "STORAGE_FS_END"

    # ZFS pools if available
    if command -v zpool &>/dev/null; then
        echo "STORAGE_ZFS_START"
        zpool list -H 2>/dev/null | while read -r line; do
            echo "ZPOOL|$line"
        done
        echo "STORAGE_ZFS_END"
    fi

    # LVM info
    if command -v vgs &>/dev/null; then
        echo "STORAGE_LVM_START"
        vgs --noheadings -o vg_name,vg_size,vg_free 2>/dev/null | while read -r line; do
            echo "VG|$line"
        done
        echo "STORAGE_LVM_END"
    fi
}

# --- get_network_info ---------------------------------------------------------
# @function get_network_info
# @description Retrieves network interface information
get_network_info() {
    echo "NETWORK_START"
    ip -o link show 2>/dev/null | while read -r line; do
        local iface=$(echo "$line" | awk '{print $2}' | tr -d ':')
        local state=$(echo "$line" | grep -oP 'state \K\w+')
        local mac=$(echo "$line" | grep -oP 'link/ether \K[0-9a-f:]+' || echo "N/A")

        # Get speed if available
        local speed="N/A"
        if [[ -f "/sys/class/net/$iface/speed" ]]; then
            speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null || echo "N/A")
            [[ "$speed" != "N/A" ]] && speed="${speed}Mb/s"
        fi

        # Get IP address
        local ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || echo "N/A")

        echo "IFACE|$iface|$state|$mac|$speed|$ip"
    done
    echo "NETWORK_END"
}

# --- get_pcie_devices ---------------------------------------------------------
# @function get_pcie_devices
# @description Retrieves PCIe device information
get_pcie_devices() {
    echo "PCIE_START"
    lspci 2>/dev/null | while read -r line; do
        echo "PCIE|$line"
    done
    echo "PCIE_END"
}

# --- get_proxmox_info ---------------------------------------------------------
# @function get_proxmox_info
# @description Retrieves Proxmox-specific information
get_proxmox_info() {
    local pve_version kernel_version uptime_info hostname cluster_status

    pve_version=$(pveversion 2>/dev/null | head -1 || echo "N/A")
    kernel_version=$(uname -r)
    uptime_info=$(uptime -p 2>/dev/null || uptime | cut -d',' -f1)
    hostname=$(hostname -f)

    # Check cluster status
    if command -v pvecm &>/dev/null; then
        cluster_status=$(pvecm status 2>/dev/null | grep -E "Cluster name|Quorum:" || echo "Standalone")
    else
        cluster_status="Standalone"
    fi

    # Get VM/LXC counts
    local vm_count=0
    local lxc_count=0
    if command -v qm &>/dev/null; then
        vm_count=$(qm list 2>/dev/null | tail -n +2 | wc -l || echo "0")
    fi
    if command -v pct &>/dev/null; then
        lxc_count=$(pct list 2>/dev/null | tail -n +2 | wc -l || echo "0")
    fi

    echo "PVE_VERSION|$pve_version"
    echo "KERNEL|$kernel_version"
    echo "UPTIME|$uptime_info"
    echo "HOSTNAME|$hostname"
    echo "CLUSTER|$cluster_status"
    echo "VM_COUNT|$vm_count"
    echo "LXC_COUNT|$lxc_count"
}

# --- display_info -------------------------------------------------------------
# @function display_info
# @description Displays collected information in a formatted manner
display_info() {
    local -A data

    # Collect all information
    while IFS='|' read -r key value rest; do
        if [[ -n "$key" && -n "$value" ]]; then
            if [[ "$key" == "DEVICE" || "$key" == "FS" || "$key" == "ZPOOL" || "$key" == "VG" || "$key" == "IFACE" || "$key" == "PCIE" ]]; then
                data["$key"]+="$value|$rest"$'\n'
            else
                data["$key"]="$value"
            fi
        fi
    done < <(
        get_proxmox_info
        get_cpu_info
        get_memory_info
        get_storage_info
        get_network_info
        get_pcie_devices
    )

    # ASCII Art Header
    echo -e "${CYAN}"
    cat <<'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║   ██████╗ ██████╗  ██████╗ ██╗  ██╗███╗   ███╗ ██████╗ ██╗  ██╗   ║
║   ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝████╗ ████║██╔═══██╗╚██╗██╔╝   ║
║   ██████╔╝██████╔╝██║   ██║ ╚███╔╝ ██╔████╔██║██║   ██║ ╚███╔╝    ║
║   ██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗ ██║╚██╔╝██║██║   ██║ ██╔██╗    ║
║   ██║     ██║  ██║╚██████╔╝██╔╝ ██╗██║ ╚═╝ ██║╚██████╔╝██╔╝ ██╗   ║
║   ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ║
║                                                                   ║
║                         HOST INFORMATION                          ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""

    # System Information
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${YELLOW}  SYSTEM INFORMATION${NC}"
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Hostname:${NC}      ${data[HOSTNAME]}"
    echo -e "${CYAN}Proxmox:${NC}       ${data[PVE_VERSION]}"
    echo -e "${CYAN}Kernel:${NC}        ${data[KERNEL]}"
    echo -e "${CYAN}Uptime:${NC}        ${data[UPTIME]}"
    echo -e "${CYAN}Cluster:${NC}       ${data[CLUSTER]}"
    echo -e "${CYAN}VMs/LXCs:${NC}      ${GREEN}${data[VM_COUNT]}${NC} VMs, ${GREEN}${data[LXC_COUNT]}${NC} LXCs"
    echo ""

    # CPU Information
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${YELLOW}  CPU INFORMATION${NC}"
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Model:${NC}         ${data[CPU_MODEL]}"
    echo -e "${CYAN}Sockets:${NC}       ${data[CPU_SOCKETS]}"
    echo -e "${CYAN}Cores:${NC}         ${data[CPU_CORES]} cores/socket (${data[CPU_THREADS]} threads total)"
    echo -e "${CYAN}Frequency:${NC}     ${data[CPU_MHZ]:-N/A} MHz"
    echo -e "${CYAN}Cache:${NC}         ${data[CPU_CACHE]:-N/A}"
    echo -e "${CYAN}Virtualization:${NC} ${data[CPU_VIRT]:-N/A}"
    echo ""

    # Memory Information
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${YELLOW}  MEMORY INFORMATION${NC}"
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Total:${NC}         ${data[MEM_TOTAL]}"
    echo -e "${CYAN}Used:${NC}          ${data[MEM_USED]}"
    echo -e "${CYAN}Free:${NC}          ${data[MEM_FREE]}"
    echo -e "${CYAN}Available:${NC}     ${data[MEM_AVAILABLE]}"
    echo -e "${CYAN}Type:${NC}          ${data[MEM_TYPE]}"
    echo -e "${CYAN}Speed:${NC}         ${data[MEM_SPEED]}"
    echo -e "${CYAN}Sticks:${NC}        ${data[MEM_STICKS]} of ${data[MEM_CHANNELS]} slots"
    echo ""

    # Storage - Block Devices
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${YELLOW}  STORAGE - BLOCK DEVICES${NC}"
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$(printf '%-15s %-10s %-10s %s' 'DEVICE' 'SIZE' 'TYPE' 'MODEL')${NC}"
    echo -e "────────────────────────────────────────────────────────────────────────────"
    if [[ -v data[DEVICE] ]]; then
        echo "${data[DEVICE]}" | while IFS='|' read -r rest; do
            [[ -z "$rest" ]] && continue
            echo "$rest"
        done
    fi
    echo ""

    # Storage - Filesystems
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${YELLOW}  STORAGE - FILESYSTEMS${NC}"
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$(printf '%-25s %-8s %-8s %-8s %-5s %s' 'FILESYSTEM' 'SIZE' 'USED' 'AVAIL' 'USE%' 'MOUNTED')${NC}"
    echo -e "────────────────────────────────────────────────────────────────────────────"
    if [[ -v data[FS] ]]; then
        echo "${data[FS]}" | while IFS='|' read -r rest; do
            [[ -z "$rest" ]] && continue
            echo "$rest"
        done
    fi
    echo ""

    # Storage - ZFS (if available)
    if [[ -v data[ZPOOL] && -n "${data[ZPOOL]}" ]]; then
        echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}${YELLOW}  STORAGE - ZFS POOLS${NC}"
        echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}$(printf '%-15s %-10s %-10s %-10s %-10s' 'NAME' 'SIZE' 'ALLOC' 'FREE' 'HEALTH')${NC}"
        echo -e "────────────────────────────────────────────────────────────────────────────"
        echo "${data[ZPOOL]}" | while IFS='|' read -r rest; do
            [[ -z "$rest" ]] && continue
            echo "$rest"
        done
        echo ""
    fi

    # Storage - LVM (if available)
    if [[ -v data[VG] && -n "${data[VG]}" ]]; then
        echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}${YELLOW}  STORAGE - LVM VOLUME GROUPS${NC}"
        echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}$(printf '%-20s %-15s %s' 'VG NAME' 'SIZE' 'FREE')${NC}"
        echo -e "────────────────────────────────────────────────────────────────────────────"
        echo "${data[VG]}" | while IFS='|' read -r rest; do
            [[ -z "$rest" ]] && continue
            echo "$rest"
        done
        echo ""
    fi

    # Network Information
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${YELLOW}  NETWORK INTERFACES${NC}"
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$(printf '%-12s %-10s %-20s %-12s %s' 'INTERFACE' 'STATE' 'MAC' 'SPEED' 'IP')${NC}"
    echo -e "────────────────────────────────────────────────────────────────────────────"
    if [[ -v data[IFACE] ]]; then
        echo "${data[IFACE]}" | while IFS='|' read -r iface state mac speed ip; do
            [[ -z "$iface" ]] && continue
            local state_color="${GREEN}"
            [[ "$state" != "UP" ]] && state_color="${RED}"
            echo -e "$(printf '%-12s' "$iface") ${state_color}$(printf '%-10s' "$state")${NC} $(printf '%-20s %-12s %s' "$mac" "$speed" "$ip")"
        done
    fi
    echo ""

    # PCIe Devices
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${YELLOW}  PCIE DEVICES${NC}"
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
    if [[ -v data[PCIE] ]]; then
        echo "${data[PCIE]}" | grep -iE "VGA|Audio|Network|RAID|SATA|NVMe|USB|Ethernet" | while IFS='|' read -r rest; do
            [[ -z "$rest" ]] && continue
            # Highlight important device types
            if echo "$rest" | grep -qi "vga"; then
                echo -e "${MAGENTA}$rest${NC}"
            elif echo "$rest" | grep -qi "network\|ethernet"; then
                echo -e "${GREEN}$rest${NC}"
            elif echo "$rest" | grep -qi "nvme\|sata\|raid"; then
                echo -e "${CYAN}$rest${NC}"
            else
                echo "$rest"
            fi
        done
    fi
    echo ""
    echo -e "${BOLD}${WHITE}════════════════════════════════════════════════════════════════════════════${NC}"
}

# --- display_json -------------------------------------------------------------
# @function display_json
# @description Outputs information in JSON format
display_json() {
    local -A data
    local -a devices filesystems zpools vgs ifaces pcie

    # Collect all information
    local in_section=""
    while IFS='|' read -r key value rest; do
        case "$key" in
            STORAGE_DEVICES_START) in_section="devices" ;;
            STORAGE_DEVICES_END) in_section="" ;;
            STORAGE_FS_START) in_section="fs" ;;
            STORAGE_FS_END) in_section="" ;;
            STORAGE_ZFS_START) in_section="zfs" ;;
            STORAGE_ZFS_END) in_section="" ;;
            STORAGE_LVM_START) in_section="lvm" ;;
            STORAGE_LVM_END) in_section="" ;;
            NETWORK_START) in_section="net" ;;
            NETWORK_END) in_section="" ;;
            PCIE_START) in_section="pcie" ;;
            PCIE_END) in_section="" ;;
            DEVICE) [[ "$in_section" == "devices" ]] && devices+=("$value|$rest") ;;
            FS) [[ "$in_section" == "fs" ]] && filesystems+=("$value|$rest") ;;
            ZPOOL) [[ "$in_section" == "zfs" ]] && zpools+=("$value|$rest") ;;
            VG) [[ "$in_section" == "lvm" ]] && vgs+=("$value|$rest") ;;
            IFACE) [[ "$in_section" == "net" ]] && ifaces+=("$value|$rest") ;;
            PCIE) [[ "$in_section" == "pcie" ]] && pcie+=("$value|$rest") ;;
            *) [[ -n "$key" && -n "$value" ]] && data["$key"]="$value" ;;
        esac
    done < <(
        get_proxmox_info
        get_cpu_info
        get_memory_info
        get_storage_info
        get_network_info
        get_pcie_devices
    )

    # Output JSON
    echo "{"
    echo "  \"system\": {"
    echo "    \"hostname\": \"${data[HOSTNAME]}\","
    echo "    \"proxmox_version\": \"${data[PVE_VERSION]}\","
    echo "    \"kernel\": \"${data[KERNEL]}\","
    echo "    \"uptime\": \"${data[UPTIME]}\","
    echo "    \"cluster\": \"${data[CLUSTER]}\","
    echo "    \"vm_count\": ${data[VM_COUNT]},"
    echo "    \"lxc_count\": ${data[LXC_COUNT]}"
    echo "  },"
    echo "  \"cpu\": {"
    echo "    \"model\": \"${data[CPU_MODEL]}\","
    echo "    \"sockets\": ${data[CPU_SOCKETS]},"
    echo "    \"cores\": ${data[CPU_CORES]},"
    echo "    \"threads\": ${data[CPU_THREADS]},"
    echo "    \"frequency_mhz\": \"${data[CPU_MHZ]}\","
    echo "    \"cache\": \"${data[CPU_CACHE]}\","
    echo "    \"virtualization\": \"${data[CPU_VIRT]}\""
    echo "  },"
    echo "  \"memory\": {"
    echo "    \"total\": \"${data[MEM_TOTAL]}\","
    echo "    \"used\": \"${data[MEM_USED]}\","
    echo "    \"free\": \"${data[MEM_FREE]}\","
    echo "    \"available\": \"${data[MEM_AVAILABLE]}\","
    echo "    \"type\": \"${data[MEM_TYPE]}\","
    echo "    \"speed\": \"${data[MEM_SPEED]}\","
    echo "    \"channels\": ${data[MEM_CHANNELS]},"
    echo "    \"sticks\": ${data[MEM_STICKS]}"
    echo "  },"
    echo "  \"storage\": {"
    echo "    \"devices\": ["
    local first=1
    for dev in "${devices[@]}"; do
        [[ $first -eq 0 ]] && echo ","
        echo -n "      \"$dev\""
        first=0
    done
    echo ""
    echo "    ],"
    echo "    \"filesystems\": ["
    first=1
    for fs in "${filesystems[@]}"; do
        [[ $first -eq 0 ]] && echo ","
        echo -n "      \"$fs\""
        first=0
    done
    echo ""
    echo "    ]"
    echo "  },"
    echo "  \"network\": ["
    first=1
    for iface in "${ifaces[@]}"; do
        [[ $first -eq 0 ]] && echo ","
        echo -n "    \"$iface\""
        first=0
    done
    echo ""
    echo "  ]"
    echo "}"
}

# --- main ---------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    if [[ "$JSON" == "true" ]]; then
        display_json
    else
        display_info
    fi
}

main "$@"

# Testing Status:
#   - Tested execution on 11/17
#   - Updated to use ArgumentParser.sh

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

