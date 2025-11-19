#!/bin/bash
#
# OptimizeNestedVirtualization.sh
#
# Enables nested virtualization on Proxmox for Intel or AMD CPUs.
# Detects CPU vendor and configures kernel modules accordingly.
#
# Usage:
#   OptimizeNestedVirtualization.sh
#
# Examples:
#   OptimizeNestedVirtualization.sh
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Enabling nested virtualization"

    # Detect CPU vendor
    local cpu_vendor
    cpu_vendor=$(lscpu | awk -F: '/Vendor ID:/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')

    if [[ -z "$cpu_vendor" ]]; then
        __err__ "Unable to detect CPU vendor"
        exit 1
    fi

    __info__ "Detected CPU vendor: $cpu_vendor"

    # Configure based on CPU vendor
    if [[ "$cpu_vendor" =~ [Ii]ntel ]]; then
        __info__ "Configuring nested virtualization for Intel"
        echo "options kvm-intel nested=Y" >/etc/modprobe.d/kvm-intel.conf

        if lsmod | grep -q kvm_intel; then
            __update__ "Reloading kvm_intel module"
            rmmod kvm_intel 2>/dev/null || true
        fi
        modprobe kvm_intel

        local nested_status
        nested_status=$(cat /sys/module/kvm_intel/parameters/nested 2>/dev/null)
        if [[ "$nested_status" == "Y" || "$nested_status" == "1" ]]; then
            __ok__ "Nested virtualization enabled for Intel"
        else
            __warn__ "Unable to confirm nested virtualization is enabled"
        fi

    elif [[ "$cpu_vendor" =~ [Aa][Mm][Dd] ]]; then
        __info__ "Configuring nested virtualization for AMD"
        echo "options kvm-amd nested=1" >/etc/modprobe.d/kvm-amd.conf

        if lsmod | grep -q kvm_amd; then
            __update__ "Reloading kvm_amd module"
            rmmod kvm_amd 2>/dev/null || true
        fi
        modprobe kvm_amd

        local nested_status
        nested_status=$(cat /sys/module/kvm_amd/parameters/nested 2>/dev/null)
        if [[ "$nested_status" == "1" || "$nested_status" == "Y" ]]; then
            __ok__ "Nested virtualization enabled for AMD"
        else
            __warn__ "Unable to confirm nested virtualization is enabled"
        fi

    else
        __warn__ "Unknown CPU vendor, attempting Intel configuration"
        echo "options kvm-intel nested=Y" >/etc/modprobe.d/kvm-intel.conf
        if lsmod | grep -q kvm_intel; then
            rmmod kvm_intel 2>/dev/null || true
        fi
        modprobe kvm_intel
    fi

    echo
    __ok__ "Nested virtualization configuration completed!"
    __info__ "Set VM CPU type to 'host': qm set <VMID> --cpu host"
    __warn__ "A reboot may be required if issues persist"
    __info__ "Verify with: cat /sys/module/kvm_*/parameters/nested"
}

main

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
