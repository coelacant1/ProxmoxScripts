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
#   BulkConfigureCPU.sh <start_id> <end_id> [options]
#
# Arguments:
#   start_id  - The starting VM ID in the range to be processed
#   end_id    - The ending VM ID in the range to be processed
#
# CPU Configuration Options:
#   --cores <num>           - Number of cores per socket (1-128)
#   --sockets <num>         - Number of CPU sockets (1-4)
#   --numa <0|1>            - Enable NUMA (0=disabled, 1=enabled)
#   --type <type>           - CPU type (host, kvm64, qemu64, max, etc.)
#   --vcpus <num>           - Number of vCPUs to hotplug (1-total_cores)
#   --cpulimit <num>        - CPU usage limit (0-128, 0=unlimited)
#   --cpuunits <num>        - CPU weight/shares (2-262144, default: 1024)
#   --affinity <cpus>       - CPU affinity (e.g., 0,1,2,3 or 0-3)
#   --flags <flags>         - CPU flags to enable/disable (e.g., +aes,-pdpe1gb)
#
# Examples:
#   # Set cores and sockets
#   BulkConfigureCPU.sh 100 110 --cores 4 --sockets 2
#
#   # Configure with NUMA enabled
#   BulkConfigureCPU.sh 100 110 --cores 8 --sockets 2 --numa 1
#
#   # Set CPU type and limit
#   BulkConfigureCPU.sh 100 110 --type host --cpulimit 2
#
#   # Full configuration with affinity
#   BulkConfigureCPU.sh 400 410 --cores 4 --sockets 2 --type host --numa 1 --cpulimit 4 --affinity 0-7
#
#   # Configure vCPU hotplug
#   BulkConfigureCPU.sh 100 110 --cores 8 --vcpus 4
#
#   # Set CPU shares/priority
#   BulkConfigureCPU.sh 100 110 --cpuunits 2048
#
#   # Enable/disable CPU flags
#   BulkConfigureCPU.sh 100 110 --type host --flags +aes,+avx,+avx2
#
# CPU Types:
#   - host      : Pass-through host CPU (best performance, less portable)
#   - max       : Enable all features supported by accelerator (QEMU 4.0+)
#   - kvm64     : Common baseline 64-bit (most portable)
#   - qemu64    : QEMU default (very portable)
#   - Penryn    : Intel Core 2 Duo
#   - SandyBridge, IvyBridge, Haswell, Broadwell, Skylake-Client
#   - EPYC, EPYC-Rome, EPYC-Milan (AMD server)
#   - And many others...
#
# CPU Flags:
#   - +flag     : Enable feature (e.g., +aes, +avx, +avx2)
#   - -flag     : Disable feature (e.g., -pdpe1gb, -nx)
#   Common flags: aes, avx, avx2, avx512f, pdpe1gb, md-clear, pcid, spec-ctrl
#
# Function Index:
#   - usage
#   - parse_args
#   - validate_options
#   - main
#   - configure_cpu_callback
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Global variables
START_ID=""
END_ID=""
CORES=""
SOCKETS=""
NUMA=""
CPU_TYPE=""
VCPUS=""
CPULIMIT=""
CPUUNITS=""
AFFINITY=""
CPU_FLAGS=""

# --- usage -------------------------------------------------------------------
# @function usage
# @description Prints usage information and exits.
usage() {
    cat <<-USAGE
Usage: ${0##*/} <start_id> <end_id> [options]

Configures CPU settings for a range of VMs cluster-wide.

Arguments:
  start_id  - Starting VM ID
  end_id    - Ending VM ID

CPU Options:
  --cores <num>        - Cores per socket (1-128)
  --sockets <num>      - Number of sockets (1-4)
  --numa <0|1>         - Enable NUMA (0=off, 1=on)
  --type <type>        - CPU type (host, kvm64, qemu64, max, etc.)
  --vcpus <num>        - Hotplug vCPUs (1-total_cores)
  --cpulimit <num>     - CPU limit (0-128, 0=unlimited)
  --cpuunits <num>     - CPU weight/shares (2-262144, default: 1024)
  --affinity <cpus>    - CPU affinity (e.g., 0,1,2,3 or 0-3)
  --flags <flags>      - CPU flags (e.g., +aes,-pdpe1gb)

CPU Types (common):
  host          - Pass-through host CPU (best performance)
  max           - All features supported (QEMU 4.0+)
  kvm64         - Baseline 64-bit (most portable)
  qemu64        - QEMU default
  Haswell       - Intel Haswell
  Broadwell     - Intel Broadwell
  Skylake-Client- Intel Skylake
  EPYC          - AMD EPYC
  EPYC-Rome     - AMD EPYC Rome
  EPYC-Milan    - AMD EPYC Milan

CPU Flags:
  +flag  - Enable (e.g., +aes, +avx, +avx2, +spec-ctrl)
  -flag  - Disable (e.g., -pdpe1gb, -nx)

Examples:
  # Basic: 4 cores, 2 sockets
  ${0##*/} 100 110 --cores 4 --sockets 2

  # With NUMA for large VMs
  ${0##*/} 100 110 --cores 8 --sockets 2 --numa 1

  # Host CPU with limits
  ${0##*/} 100 110 --type host --cpulimit 2

  # Full config with affinity
  ${0##*/} 400 410 --cores 4 --sockets 2 --type host --numa 1 --cpulimit 4 --affinity 0-7

  # vCPU hotplug (start with 4, allow up to 8)
  ${0##*/} 100 110 --cores 8 --vcpus 4

  # Priority (higher units = more CPU time)
  ${0##*/} 100 110 --cpuunits 2048

  # Enable security features
  ${0##*/} 100 110 --type host --flags +spec-ctrl,+md-clear

Notes:
  - Total vCPUs = cores × sockets
  - NUMA recommended for VMs with >8 cores
  - CPU affinity pins VM to specific host cores
  - cpuunits default is 1024 (higher = more priority)
USAGE
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 2 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    START_ID="$1"
    END_ID="$2"
    shift 2

    # Validate IDs are numeric
    if ! [[ "$START_ID" =~ ^[0-9]+$ ]] || ! [[ "$END_ID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    # Validate range
    if (( START_ID > END_ID )); then
        __err__ "Start ID must be less than or equal to end ID"
        exit 64
    fi

    # Parse optional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cores)
                CORES="$2"
                shift 2
                ;;
            --sockets)
                SOCKETS="$2"
                shift 2
                ;;
            --numa)
                NUMA="$2"
                shift 2
                ;;
            --type)
                CPU_TYPE="$2"
                shift 2
                ;;
            --vcpus)
                VCPUS="$2"
                shift 2
                ;;
            --cpulimit)
                CPULIMIT="$2"
                shift 2
                ;;
            --cpuunits)
                CPUUNITS="$2"
                shift 2
                ;;
            --affinity)
                AFFINITY="$2"
                shift 2
                ;;
            --flags)
                CPU_FLAGS="$2"
                shift 2
                ;;
            *)
                __err__ "Unknown option: $1"
                usage
                exit 64
                ;;
        esac
    done

    # Check that at least one option is specified
    if [[ -z "$CORES" && -z "$SOCKETS" && -z "$NUMA" && -z "$CPU_TYPE" && \
          -z "$VCPUS" && -z "$CPULIMIT" && -z "$CPUUNITS" && -z "$AFFINITY" && \
          -z "$CPU_FLAGS" ]]; then
        __err__ "At least one CPU option must be specified"
        usage
        exit 64
    fi
}

# --- validate_options --------------------------------------------------------
# @function validate_options
# @description Validates CPU configuration options.
validate_options() {
    # Validate cores
    if [[ -n "$CORES" ]]; then
        if ! [[ "$CORES" =~ ^[0-9]+$ ]] || (( CORES < 1 || CORES > 128 )); then
            __err__ "Cores must be between 1 and 128"
            exit 64
        fi
    fi

    # Validate sockets
    if [[ -n "$SOCKETS" ]]; then
        if ! [[ "$SOCKETS" =~ ^[0-9]+$ ]] || (( SOCKETS < 1 || SOCKETS > 4 )); then
            __err__ "Sockets must be between 1 and 4"
            exit 64
        fi
    fi

    # Validate NUMA
    if [[ -n "$NUMA" && ! "$NUMA" =~ ^[01]$ ]]; then
        __err__ "NUMA must be 0 or 1"
        exit 64
    fi

    # Validate vCPUs
    if [[ -n "$VCPUS" ]]; then
        if ! [[ "$VCPUS" =~ ^[0-9]+$ ]] || (( VCPUS < 1 )); then
            __err__ "vCPUs must be at least 1"
            exit 64
        fi

        # Check if vcpus exceeds total cores
        if [[ -n "$CORES" && -n "$SOCKETS" ]]; then
            local total_cores=$((CORES * SOCKETS))
            if (( VCPUS > total_cores )); then
                __err__ "vCPUs ($VCPUS) cannot exceed total cores ($total_cores)"
                exit 64
            fi
        fi
    fi

    # Validate CPU limit
    if [[ -n "$CPULIMIT" ]]; then
        if ! [[ "$CPULIMIT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            __err__ "CPU limit must be a number"
            exit 64
        fi

        if (( $(echo "$CPULIMIT < 0" | bc -l) )) || (( $(echo "$CPULIMIT > 128" | bc -l) )); then
            __err__ "CPU limit must be between 0 and 128"
            exit 64
        fi
    fi

    # Validate CPU units
    if [[ -n "$CPUUNITS" ]]; then
        if ! [[ "$CPUUNITS" =~ ^[0-9]+$ ]] || (( CPUUNITS < 2 || CPUUNITS > 262144 )); then
            __err__ "CPU units must be between 2 and 262144"
            exit 64
        fi
    fi

    # Validate affinity format
    if [[ -n "$AFFINITY" ]]; then
        # Check for valid format: numbers, commas, hyphens only
        if ! [[ "$AFFINITY" =~ ^[0-9,\-]+$ ]]; then
            __err__ "Invalid affinity format. Use: 0,1,2,3 or 0-3"
            exit 64
        fi
    fi

    # Validate CPU type (basic check - Proxmox will validate the actual type)
    if [[ -n "$CPU_TYPE" ]]; then
        # Just check it's not empty and doesn't contain invalid characters
        if [[ "$CPU_TYPE" =~ [[:space:]] ]]; then
            __err__ "CPU type cannot contain spaces"
            exit 64
        fi
    fi

    # Validate CPU flags format
    if [[ -n "$CPU_FLAGS" ]]; then
        # Check format: +flag or -flag, comma separated
        if ! [[ "$CPU_FLAGS" =~ ^[+\-][a-z0-9_\-]+(,[+\-][a-z0-9_\-]+)*$ ]]; then
            __err__ "Invalid CPU flags format. Use: +flag1,-flag2,+flag3"
            exit 64
        fi
    fi

    # Warn about NUMA for small VMs
    if [[ -n "$NUMA" && "$NUMA" == "1" && -n "$CORES" && -n "$SOCKETS" ]]; then
        local total_cores=$((CORES * SOCKETS))
        if (( total_cores <= 4 )); then
            __warn__ "NUMA enabled for small VM (${total_cores} cores) - may not be beneficial"
        fi
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Validate options
    validate_options

    __info__ "Bulk configure CPU: VMs ${START_ID} to ${END_ID} (cluster-wide)"
    [[ -n "$CORES" ]] && __info__ "  Cores: ${CORES}"
    [[ -n "$SOCKETS" ]] && __info__ "  Sockets: ${SOCKETS}"
    [[ -n "$NUMA" ]] && __info__ "  NUMA: ${NUMA}"
    [[ -n "$CPU_TYPE" ]] && __info__ "  Type: ${CPU_TYPE}"
    [[ -n "$VCPUS" ]] && __info__ "  vCPUs: ${VCPUS}"
    [[ -n "$CPULIMIT" ]] && __info__ "  CPU Limit: ${CPULIMIT}"
    [[ -n "$CPUUNITS" ]] && __info__ "  CPU Units: ${CPUUNITS}"
    [[ -n "$AFFINITY" ]] && __info__ "  Affinity: ${AFFINITY}"
    [[ -n "$CPU_FLAGS" ]] && __info__ "  Flags: ${CPU_FLAGS}"

    # Calculate total vCPUs if applicable
    if [[ -n "$CORES" && -n "$SOCKETS" ]]; then
        local total=$((CORES * SOCKETS))
        __info__ "  Total vCPUs: ${total}"
    fi

    # Confirm action
    if ! __prompt_yes_no__ "Configure CPU for VMs ${START_ID}-${END_ID}?"; then
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
        if [[ -n "$CPU_TYPE" ]]; then
            local cpu_config="$CPU_TYPE"

            # Add flags if specified
            [[ -n "$CPU_FLAGS" ]] && cpu_config+=",flags=${CPU_FLAGS}"

            cmd+=" --cpu \"$cpu_config\""
        elif [[ -n "$CPU_FLAGS" ]]; then
            # Flags without type change - need to get current type
            local current_type
            current_type=$(qm config "$vmid" --node "$node" 2>/dev/null | grep "^cpu:" | sed 's/cpu: *//' | cut -d',' -f1 || echo "kvm64")
            local cpu_config="${current_type},flags=${CPU_FLAGS}"
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

parse_args "$@"
main

# Testing status:
#   - Updated to use BulkOperations framework
