#!/bin/bash
#
# BulkConfigureCPU.sh
#
# Configures CPU settings for a range of virtual machines (VMs) on a Proxmox VE cluster.
# Supports comprehensive CPU configuration including cores, sockets, NUMA, CPU type, vCPUs,
# CPU limits, affinity, units, and optional CPU flags for feature control.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   BulkConfigureCPU.sh 100 110 --cores 4 --sockets 2
#   BulkConfigureCPU.sh 100 110 --cores 8 --sockets 2 --numa 1
#   BulkConfigureCPU.sh 100 110 --type host --cpulimit 2
#   BulkConfigureCPU.sh 400 410 --cores 4 --sockets 2 --type host --numa 1 --cpulimit 4 --affinity 0-7
#   BulkConfigureCPU.sh 100 110 --cores 8 --vcpus 4
#   BulkConfigureCPU.sh 100 110 --cpuunits 2048
#   BulkConfigureCPU.sh 100 110 --type host --flags +aes,+avx,+avx2
#
# Arguments:
#   start_id           - Starting VM ID in the range
#   end_id             - Ending VM ID in the range
#   --cores <num>      - Cores per socket (1-128)
#   --sockets <num>    - Number of sockets (1-4)
#   --numa <0|1>       - Enable NUMA (0=disabled, 1=enabled)
#   --type <type>      - CPU type (host, kvm64, qemu64, max, etc.)
#   --vcpus <num>      - vCPUs to hotplug (1-total_cores)
#   --cpulimit <num>   - CPU usage limit (0-128, 0=unlimited)
#   --cpuunits <num>   - CPU weight/shares (2-262144, default: 1024)
#   --affinity <cpus>  - CPU affinity (e.g., 0,1,2,3 or 0-3)
#   --flags <flags>    - CPU flags (e.g., +aes,-pdpe1gb)
#
# CPU Types: host, max, kvm64, qemu64, Haswell, Broadwell, Skylake-Client, EPYC, EPYC-Rome, EPYC-Milan
# CPU Flags: +flag to enable (e.g., +aes, +avx, +avx2), -flag to disable (e.g., -pdpe1gb, -nx)
#
# Notes:
#   - Total vCPUs = cores x sockets
#   - NUMA recommended for VMs with >8 cores
#   - CPU affinity pins VM to specific host cores
#   - At least one CPU option must be specified
#
# Function Index:
#   - validate_custom_options
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- validate_custom_options -------------------------------------------------
# @function validate_custom_options
# @description Validates CPU-specific configuration options not covered by ArgumentParser.
validate_custom_options() {
    # Check that at least one CPU option is specified
    if [[ -z "$CORES" && -z "$SOCKETS" && -z "$NUMA" && -z "$TYPE" &&
        -z "$VCPUS" && -z "$CPULIMIT" && -z "$CPUUNITS" && -z "$AFFINITY" &&
        -z "$FLAGS" ]]; then
        __err__ "At least one CPU option must be specified"
        exit 64
    fi

    # Validate vCPUs doesn't exceed total cores
    if [[ -n "$VCPUS" && -n "$CORES" && -n "$SOCKETS" ]]; then
        local total_cores=$((CORES * SOCKETS))
        if ((VCPUS > total_cores)); then
            __err__ "vCPUs ($VCPUS) cannot exceed total cores ($total_cores)"
            exit 64
        fi
    fi

    # Validate affinity format
    if [[ -n "$AFFINITY" ]]; then
        if ! [[ "$AFFINITY" =~ ^[0-9,\-]+$ ]]; then
            __err__ "Invalid affinity format. Use: 0,1,2,3 or 0-3"
            exit 64
        fi
    fi

    # Validate CPU type doesn't contain spaces
    if [[ -n "$TYPE" && "$TYPE" =~ [[:space:]] ]]; then
        __err__ "CPU type cannot contain spaces"
        exit 64
    fi

    # Validate CPU flags format
    if [[ -n "$FLAGS" ]]; then
        if ! [[ "$FLAGS" =~ ^[+\-][a-z0-9_\-]+(,[+\-][a-z0-9_\-]+)*$ ]]; then
            __err__ "Invalid CPU flags format. Use: +flag1,-flag2,+flag3"
            exit 64
        fi
    fi

    # Warn about NUMA for small VMs
    if [[ -n "$NUMA" && "$NUMA" == "1" && -n "$CORES" && -n "$SOCKETS" ]]; then
        local total_cores=$((CORES * SOCKETS))
        if ((total_cores <= 4)); then
            __warn__ "NUMA enabled for small VM (${total_cores} cores) - may not be beneficial"
        fi
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Parse arguments using ArgumentParser
    __parse_args__ "start_id:vmid end_id:vmid --cores:cpu:? --sockets:number:? --numa:boolean:? --type:string:? --vcpus:cpu:? --cpulimit:number:? --cpuunits:number:? --affinity:string:? --flags:string:?" "$@"

    # Additional custom validation
    validate_custom_options

    __info__ "Bulk configure CPU: VMs ${START_ID} to ${END_ID} (cluster-wide)"
    [[ -n "$CORES" ]] && __info__ "  Cores: ${CORES}"
    [[ -n "$SOCKETS" ]] && __info__ "  Sockets: ${SOCKETS}"
    [[ -n "$NUMA" ]] && __info__ "  NUMA: ${NUMA}"
    [[ -n "$TYPE" ]] && __info__ "  Type: ${TYPE}"
    [[ -n "$VCPUS" ]] && __info__ "  vCPUs: ${VCPUS}"
    [[ -n "$CPULIMIT" ]] && __info__ "  CPU Limit: ${CPULIMIT}"
    [[ -n "$CPUUNITS" ]] && __info__ "  CPU Units: ${CPUUNITS}"
    [[ -n "$AFFINITY" ]] && __info__ "  Affinity: ${AFFINITY}"
    [[ -n "$FLAGS" ]] && __info__ "  Flags: ${FLAGS}"

    # Calculate total vCPUs if applicable
    if [[ -n "$CORES" && -n "$SOCKETS" ]]; then
        local total=$((CORES * SOCKETS))
        __info__ "  Total vCPUs: ${total}"
    fi

    # Confirm action
    if ! __prompt_user_yn__ "Configure CPU for VMs ${START_ID}-${END_ID}?"; then
        __info__ "Operation cancelled by user"
        exit 0
    fi

    # Local callback for bulk operation
    configure_cpu_callback() {
        local vmid="$1"
        local node

        node=$(__get_vm_node__ "$vmid")

        if [[ -z "$node" ]]; then
            __update__ "VM ${vmid} not found in cluster"
            return 1
        fi

        __update__ "Configuring CPU for VM ${vmid} on node ${node}..."

        # Build qm set command
        local cmd="qm set \"$vmid\" --node \"$node\""

        # Cores
        [[ -n "$CORES" ]] && cmd+=" --cores \"$CORES\""

        # Sockets
        [[ -n "$SOCKETS" ]] && cmd+=" --sockets \"$SOCKETS\""

        # NUMA
        [[ -n "$NUMA" ]] && cmd+=" --numa \"$NUMA\""

        # CPU Type (with optional flags)
        if [[ -n "$TYPE" ]]; then
            local cpu_config="$TYPE"

            # Add flags if specified
            [[ -n "$FLAGS" ]] && cpu_config+=",flags=${FLAGS}"

            cmd+=" --cpu \"$cpu_config\""
        elif [[ -n "$FLAGS" ]]; then
            # Flags without type change - need to get current type
            local current_type
            current_type=$(qm config "$vmid" --node "$node" 2>/dev/null | grep "^cpu:" | sed 's/cpu: *//' | cut -d',' -f1 || echo "kvm64")
            local cpu_config="${current_type},flags=${FLAGS}"
            cmd+=" --cpu \"$cpu_config\""
        fi

        # vCPUs
        [[ -n "$VCPUS" ]] && cmd+=" --vcpus \"$VCPUS\""

        # CPU Limit
        [[ -n "$CPULIMIT" ]] && cmd+=" --cpulimit \"$CPULIMIT\""

        # CPU Units
        [[ -n "$CPUUNITS" ]] && cmd+=" --cpuunits \"$CPUUNITS\""

        # Affinity
        [[ -n "$AFFINITY" ]] && cmd+=" --affinity \"$AFFINITY\""

        # Execute configuration
        if eval "$cmd" 2>&1; then
            return 0
        else
            return 1
        fi
    }

    # Use BulkOperations framework
    __bulk_vm_operation__ --name "CPU Configuration" --report "$START_ID" "$END_ID" configure_cpu_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "All CPU configurations completed successfully!"
}

main "$@"

# Testing status:
#   - 2025-11-04: Refactored to use ArgumentParser.sh declarative parsing
#   - Removed manual parse_args and validate_options functions
#   - Now uses __parse_args__ with automatic validation
#   - Fixed __prompt_yes_no__ -> __prompt_user_yn__
#   - Added missing Cluster.sh source for __get_vm_node__
