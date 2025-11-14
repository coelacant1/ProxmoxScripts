#!/bin/bash
#
# BulkOperations.sh
#
# Standardized framework for bulk VM/CT operations with progress tracking,
# error handling, and reporting. Reduces code duplication in bulk scripts.
#
# Usage:
#   source "${UTILITYPATH}/BulkOperations.sh"
#
# Features:
#   - Progress tracking with counters
#   - Detailed error reporting
#   - Operation summaries
#   - Retry logic for failed operations
#   - Parallel execution support
#   - Filtering capabilities
#
# Function Index:
#   - __bulk_operation__
#   - __bulk_vm_operation__
#   - vm_wrapper
#   - __bulk_ct_operation__
#   - ct_wrapper
#   - __bulk_summary__
#   - __bulk_report__
#   - __bulk_print_results__
#   - __bulk_with_retry__
#   - __bulk_filter__
#   - __bulk_parallel__
#   - __bulk_save_state__
#   - __bulk_load_state__
#   - __bulk_validate_range__
#

set -euo pipefail

# Source Logger for structured logging
if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Logger.sh" ]]; then
    # shellcheck source=Utilities/Logger.sh
    source "${UTILITYPATH}/Logger.sh"
fi

# Safe logging wrapper
__bulk_log__() {
    local level="$1"
    local message="$2"
    if declare -f __log__ >/dev/null 2>&1; then
        __log__ "$level" "$message" "BULK"
    fi
}

# Source dependencies
source "${UTILITYPATH}/Operations.sh"
source "${UTILITYPATH}/Communication.sh"

# Global state for bulk operations
declare -g BULK_TOTAL=0
declare -g BULK_SUCCESS=0
declare -g BULK_FAILED=0
declare -g BULK_SKIPPED=0
declare -g BULK_OPERATION_NAME=""
declare -g BULK_START_TIME=0
declare -A BULK_FAILED_IDS
declare -A BULK_SUCCESS_IDS
declare -A BULK_SKIPPED_IDS

###############################################################################
# Core Operations
###############################################################################

# --- __bulk_operation__ ------------------------------------------------------
# @function __bulk_operation__
# @description Generic bulk operation handler with progress tracking.
# @usage __bulk_operation__ <start_id> <end_id> <callback> [args...]
# @param 1 Start ID
# @param 2 End ID
# @param 3 Callback function name
# @param @ Additional arguments to pass to callback
# @return 0 on success, 1 if any operations failed
#
# The callback function receives: id [args...]
# Callback should return 0 on success, non-zero on failure
__bulk_operation__() {
    local start_id="$1"
    local end_id="$2"
    local callback="$3"
    shift 3

    __bulk_log__ "INFO" "Starting bulk operation: range $start_id-$end_id, callback=$callback"

    # Validate range
    if ! __validate_vmid_range__ "$start_id" "$end_id" 2>/dev/null; then
        __bulk_log__ "ERROR" "Invalid ID range: $start_id-$end_id"
        echo "Error: Invalid ID range" >&2
        return 1
    fi

    # Initialize counters
    BULK_TOTAL=$((end_id - start_id + 1))
    BULK_SUCCESS=0
    BULK_FAILED=0
    BULK_SKIPPED=0
    BULK_START_TIME=$(date +%s)
    BULK_FAILED_IDS=()
    BULK_SUCCESS_IDS=()
    BULK_SKIPPED_IDS=()

    __bulk_log__ "DEBUG" "Initialized counters: total=$BULK_TOTAL"
    __info__ "Starting bulk operation: ${BULK_OPERATION_NAME:-operation}"
    __update__ "Processing IDs ${start_id} to ${end_id} (${BULK_TOTAL} total)"

    # Process each ID
    for ((id=start_id; id<=end_id; id++)); do
        local current=$((id - start_id + 1))
        __bulk_log__ "TRACE" "Processing ID $id ($current/$BULK_TOTAL)"
        __update__ "Processing ID ${id} (${current}/${BULK_TOTAL})..."

        if "$callback" "$id" "$@" 2>/dev/null; then
            ((BULK_SUCCESS++))
            BULK_SUCCESS_IDS[$id]=1
            __bulk_log__ "DEBUG" "Success: ID $id"
        else
            ((BULK_FAILED++))
            BULK_FAILED_IDS[$id]=1
            __bulk_log__ "WARN" "Failed: ID $id"
        fi
    done

    __bulk_log__ "INFO" "Bulk operation complete: success=$BULK_SUCCESS, failed=$BULK_FAILED, skipped=$BULK_SKIPPED"
    # Show summary
    __bulk_summary__

    # Return status
    if (( BULK_FAILED > 0 )); then
        return 1
    else
        return 0
    fi
}

# --- __bulk_vm_operation__ ---------------------------------------------------
# @function __bulk_vm_operation__
# @description Bulk operation on VMs with existence checking.
# @usage __bulk_vm_operation__ [options] <start_id> <end_id> <callback> [args...]
# @param --name Operation name for reporting
# @param --skip-stopped Skip VMs that are stopped
# @param --skip-running Skip VMs that are running
# @param --report Show detailed report
# @param 1 Start VMID
# @param 2 End VMID
# @param 3 Callback function
# @param @ Additional callback arguments
# @return 0 on success, 1 if any operations failed
__bulk_vm_operation__() {
    local operation_name=""
    local skip_stopped=false
    local skip_running=false
    local show_report=false

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                operation_name="$2"
                BULK_OPERATION_NAME="$2"
                shift 2
                ;;
            --skip-stopped)
                skip_stopped=true
                shift
                ;;
            --skip-running)
                skip_running=true
                shift
                ;;
            --report)
                show_report=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    local start_id="$1"
    local end_id="$2"
    local callback="$3"
    shift 3

    __bulk_log__ "INFO" "Starting VM bulk operation: $operation_name (range: $start_id-$end_id, skip_stopped: $skip_stopped, skip_running: $skip_running)"

    # Wrapper function that checks VM existence and state
    vm_wrapper() {
        local vmid="$1"
        shift

        # Check existence
        if ! __vm_exists__ "$vmid"; then
            ((BULK_SKIPPED++))
            BULK_SKIPPED_IDS[$vmid]="not found"
            __bulk_log__ "DEBUG" "Skipped VM $vmid: not found"
            return 1
        fi

        # Check state filters
        if [[ "$skip_stopped" == "true" ]] && ! __vm_is_running__ "$vmid"; then
            ((BULK_SKIPPED++))
            BULK_SKIPPED_IDS[$vmid]="stopped"
            __bulk_log__ "DEBUG" "Skipped VM $vmid: stopped"
            return 1
        fi

        if [[ "$skip_running" == "true" ]] && __vm_is_running__ "$vmid"; then
            ((BULK_SKIPPED++))
            BULK_SKIPPED_IDS[$vmid]="running"
            __bulk_log__ "DEBUG" "Skipped VM $vmid: running"
            return 1
        fi

        # Execute callback
        __bulk_log__ "TRACE" "Executing callback for VM $vmid"
        "$callback" "$vmid" "$@"
    }

    # Run bulk operation
    __bulk_operation__ "$start_id" "$end_id" vm_wrapper "$@"
    local result=$?

    # Show detailed report if requested
    if [[ "$show_report" == "true" ]]; then
        __bulk_log__ "DEBUG" "Generating detailed report"
        __bulk_report__
    fi

    return $result
}

# --- __bulk_ct_operation__ ---------------------------------------------------
# @function __bulk_ct_operation__
# @description Bulk operation on CTs with existence checking.
# @usage __bulk_ct_operation__ [options] <start_id> <end_id> <callback> [args...]
# @param --name Operation name for reporting
# @param --skip-stopped Skip CTs that are stopped
# @param --skip-running Skip CTs that are running
# @param --report Show detailed report
# @param 1 Start CTID
# @param 2 End CTID
# @param 3 Callback function
# @param @ Additional callback arguments
# @return 0 on success, 1 if any operations failed
__bulk_ct_operation__() {
    local operation_name=""
    local skip_stopped=false
    local skip_running=false
    local show_report=false

    __bulk_log__ "DEBUG" "Starting bulk CT operation"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                operation_name="$2"
                BULK_OPERATION_NAME="$2"
                __bulk_log__ "DEBUG" "Operation name: $operation_name"
                shift 2
                ;;
            --skip-stopped)
                skip_stopped=true
                __bulk_log__ "DEBUG" "Will skip stopped CTs"
                shift
                ;;
            --skip-running)
                skip_running=true
                __bulk_log__ "DEBUG" "Will skip running CTs"
                shift
                ;;
            --report)
                show_report=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    local start_id="$1"
    local end_id="$2"
    local callback="$3"
    shift 3

    __bulk_log__ "INFO" "Bulk CT operation: $operation_name (range: $start_id-$end_id, callback: $callback)"

    # Wrapper function that checks CT existence and state
    ct_wrapper() {
        local ctid="$1"
        shift

        # Check existence
        if ! __ct_exists__ "$ctid"; then
            ((BULK_SKIPPED++))
            BULK_SKIPPED_IDS[$ctid]="not found"
            return 1
        fi

        # Check state filters
        if [[ "$skip_stopped" == "true" ]] && ! __ct_is_running__ "$ctid"; then
            ((BULK_SKIPPED++))
            BULK_SKIPPED_IDS[$ctid]="stopped"
            return 1
        fi

        if [[ "$skip_running" == "true" ]] && __ct_is_running__ "$ctid"; then
            ((BULK_SKIPPED++))
            BULK_SKIPPED_IDS[$ctid]="running"
            return 1
        fi

        # Execute callback
        "$callback" "$ctid" "$@"
    }

    # Run bulk operation
    __bulk_operation__ "$start_id" "$end_id" ct_wrapper "$@"
    local result=$?

    # Show detailed report if requested
    if [[ "$show_report" == "true" ]]; then
        __bulk_report__
    fi

    return $result
}

###############################################################################
# Reporting Functions
###############################################################################

# --- __bulk_summary__ --------------------------------------------------------
# @function __bulk_summary__
# @description Print summary of bulk operation results.
# @usage __bulk_summary__
# @return 0 always
__bulk_summary__() {
    local end_time=$(date +%s)
    local duration=$((end_time - BULK_START_TIME))

    __bulk_log__ "INFO" "Bulk summary: total=$BULK_TOTAL, success=$BULK_SUCCESS, failed=$BULK_FAILED, skipped=$BULK_SKIPPED, duration=${duration}s"

    echo ""
    __ok__ "Bulk operation complete"
    echo ""
    echo "Summary:"
    echo "  Total:     ${BULK_TOTAL}"
    echo "  Success:   ${BULK_SUCCESS}"
    echo "  Failed:    ${BULK_FAILED}"
    echo "  Skipped:   ${BULK_SKIPPED}"
    echo "  Duration:  ${duration}s"

    if (( BULK_FAILED > 0 )); then
        echo ""
        __warn__ "Some operations failed"
    fi
}

# --- __bulk_report__ ---------------------------------------------------------
# @function __bulk_report__
# @description Print detailed report including failed/skipped IDs.
# @usage __bulk_report__
# @return 0 always
__bulk_report__() {
    __bulk_log__ "DEBUG" "Generating detailed bulk report"
    __bulk_summary__

    # Show failed IDs
    if (( BULK_FAILED > 0 )); then
        __bulk_log__ "DEBUG" "Reporting $BULK_FAILED failed IDs"
        echo ""
        echo "Failed IDs:"
        for id in "${!BULK_FAILED_IDS[@]}"; do
            echo "  - $id"
        done | sort -n
    fi

    # Show skipped IDs with reasons
    if (( BULK_SKIPPED > 0 )); then
        __bulk_log__ "DEBUG" "Reporting $BULK_SKIPPED skipped IDs"
        echo ""
        echo "Skipped IDs:"
        for id in "${!BULK_SKIPPED_IDS[@]}"; do
            local reason="${BULK_SKIPPED_IDS[$id]}"
            echo "  - $id ($reason)"
        done | sort -n
    fi
}

# --- __bulk_print_results__ --------------------------------------------------
# @function __bulk_print_results__
# @description Print results in machine-readable format.
# @usage __bulk_print_results__ [--format json|csv]
# @param --format Output format (default: text)
# @return 0 always
__bulk_print_results__() {
    local format="text"

    if [[ "$1" == "--format" ]]; then
        format="$2"
    fi

    __bulk_log__ "DEBUG" "Printing results in format: $format"

    case "$format" in
        json)
            echo "{"
            echo "  \"total\": ${BULK_TOTAL},"
            echo "  \"success\": ${BULK_SUCCESS},"
            echo "  \"failed\": ${BULK_FAILED},"
            echo "  \"skipped\": ${BULK_SKIPPED},"
            echo "  \"failed_ids\": [$(printf '%s,' "${!BULK_FAILED_IDS[@]}" | sed 's/,$//')],"
            echo "  \"success_ids\": [$(printf '%s,' "${!BULK_SUCCESS_IDS[@]}" | sed 's/,$//')]"
            echo "}"
            ;;
        csv)
            echo "status,id"
            for id in "${!BULK_SUCCESS_IDS[@]}"; do
                echo "success,$id"
            done
            for id in "${!BULK_FAILED_IDS[@]}"; do
                echo "failed,$id"
            done
            for id in "${!BULK_SKIPPED_IDS[@]}"; do
                echo "skipped,$id"
            done
            ;;
        *)
            __bulk_report__
            ;;
    esac
}

###############################################################################
# Advanced Operations
###############################################################################

# --- __bulk_with_retry__ -----------------------------------------------------
# @function __bulk_with_retry__
# @description Retry failed operations with configurable attempts.
# @usage __bulk_with_retry__ <retries> <start_id> <end_id> <callback> [args...]
# @param 1 Number of retry attempts
# @param 2 Start ID
# @param 3 End ID
# @param 4 Callback function
# @param @ Additional callback arguments
# @return 0 if all eventually succeed, 1 otherwise
__bulk_with_retry__() {
    local max_retries="$1"
    local start_id="$2"
    local end_id="$3"
    local callback="$4"
    shift 4

    __bulk_log__ "INFO" "Bulk operation with retry: max_retries=$max_retries, range=$start_id-$end_id, callback=$callback"

    # First attempt
    __bulk_operation__ "$start_id" "$end_id" "$callback" "$@"

    # Retry failed operations
    local retry_count=1
    while (( BULK_FAILED > 0 && retry_count <= max_retries )); do
        __bulk_log__ "DEBUG" "Retry attempt $retry_count/$max_retries for $BULK_FAILED failed operations"
        __info__ "Retry attempt ${retry_count}/${max_retries} for ${BULK_FAILED} failed operations"

        # Get failed IDs
        local failed_ids=("${!BULK_FAILED_IDS[@]}")

        # Reset counters
        BULK_FAILED_IDS=()
        BULK_TOTAL=${#failed_ids[@]}
        BULK_SUCCESS=0
        BULK_FAILED=0

        # Retry each failed ID
        for id in "${failed_ids[@]}"; do
            if "$callback" "$id" "$@" 2>/dev/null; then
                ((BULK_SUCCESS++))
                BULK_SUCCESS_IDS[$id]=1
            else
                ((BULK_FAILED++))
                BULK_FAILED_IDS[$id]=1
            fi
        done

        ((retry_count++))
        sleep 2
    done

    __bulk_summary__

    if (( BULK_FAILED > 0 )); then
        return 1
    else
        return 0
    fi
}

# --- __bulk_filter__ ---------------------------------------------------------
# @function __bulk_filter__
# @description Filter IDs based on a condition function.
# @usage __bulk_filter__ <start_id> <end_id> <filter_fn>
# @param 1 Start ID
# @param 2 End ID
# @param 3 Filter function (returns 0 to include, 1 to exclude)
# @return Prints filtered IDs to stdout, one per line
__bulk_filter__() {
    local start_id="$1"
    local end_id="$2"
    local filter_fn="$3"

    __bulk_log__ "DEBUG" "Filtering IDs: range=$start_id-$end_id, filter=$filter_fn"

    local count=0
    for ((id=start_id; id<=end_id; id++)); do
        if "$filter_fn" "$id" 2>/dev/null; then
            echo "$id"
            ((count++))
        fi
    done
    
    __bulk_log__ "DEBUG" "Filter returned $count IDs"
}

# --- __bulk_parallel__ -------------------------------------------------------
# @function __bulk_parallel__
# @description Execute operations in parallel (experimental).
# @usage __bulk_parallel__ <max_jobs> <start_id> <end_id> <callback> [args...]
# @param 1 Maximum parallel jobs
# @param 2 Start ID
# @param 3 End ID
# @param 4 Callback function
# @param @ Additional callback arguments
# @return 0 on success, 1 if any failed
#
# NOTE: This is experimental and may have issues with spinners/output
__bulk_parallel__() {
    local max_jobs="$1"
    local start_id="$2"
    local end_id="$3"
    local callback="$4"
    shift 4

    __bulk_log__ "WARN" "Starting parallel execution (experimental): max_jobs=$max_jobs, range=$start_id-$end_id"
    __warn__ "Parallel execution is experimental"

    # Initialize counters
    BULK_TOTAL=$((end_id - start_id + 1))
    BULK_SUCCESS=0
    BULK_FAILED=0
    BULK_START_TIME=$(date +%s)

    # Create temporary directory for results
    local tmpdir="/tmp/bulk_parallel_$$"
    mkdir -p "$tmpdir"

    local running=0
    for ((id=start_id; id<=end_id; id++)); do
        # Wait if at max jobs
        while (( running >= max_jobs )); do
            wait -n
            ((running--))
        done

        # Start job in background
        (
            if "$callback" "$id" "$@" &>/dev/null; then
                echo "success" > "$tmpdir/$id"
            else
                echo "failed" > "$tmpdir/$id"
            fi
        ) &

        ((running++))
    done

    # Wait for all jobs
    wait

    # Collect results
    for ((id=start_id; id<=end_id; id++)); do
        if [[ -f "$tmpdir/$id" ]]; then
            local result=$(cat "$tmpdir/$id")
            if [[ "$result" == "success" ]]; then
                ((BULK_SUCCESS++))
                BULK_SUCCESS_IDS[$id]=1
            else
                ((BULK_FAILED++))
                BULK_FAILED_IDS[$id]=1
            fi
        fi
    done

    # Cleanup
    rm -rf "$tmpdir"

    __bulk_summary__

    if (( BULK_FAILED > 0 )); then
        return 1
    else
        return 0
    fi
}

###############################################################################
# Utility Functions
###############################################################################

# --- __bulk_save_state__ -----------------------------------------------------
# @function __bulk_save_state__
# @description Save bulk operation state to file for resume.
# @usage __bulk_save_state__ <filename>
# @param 1 Filename to save state
# @return 0 on success, 1 on error
__bulk_save_state__() {
    local filename="$1"

    __bulk_log__ "DEBUG" "Saving bulk state to: $filename"

    {
        echo "BULK_TOTAL=$BULK_TOTAL"
        echo "BULK_SUCCESS=$BULK_SUCCESS"
        echo "BULK_FAILED=$BULK_FAILED"
        echo "BULK_SKIPPED=$BULK_SKIPPED"
        echo "BULK_FAILED_IDS=(${!BULK_FAILED_IDS[@]})"
        echo "BULK_SUCCESS_IDS=(${!BULK_SUCCESS_IDS[@]})"
    } > "$filename"
    
    __bulk_log__ "INFO" "Bulk state saved successfully"
}

# --- __bulk_load_state__ -----------------------------------------------------
# @function __bulk_load_state__
# @description Load bulk operation state from file.
# @usage __bulk_load_state__ <filename>
# @param 1 Filename to load state from
# @return 0 on success, 1 on error
__bulk_load_state__() {
    local filename="$1"

    __bulk_log__ "DEBUG" "Loading bulk state from: $filename"

    if [[ ! -f "$filename" ]]; then
        __bulk_log__ "ERROR" "State file not found: $filename"
        echo "Error: State file not found: $filename" >&2
        return 1
    fi

    source "$filename"
    __bulk_log__ "INFO" "Bulk state loaded successfully"
}

# --- __bulk_validate_range__ -------------------------------------------------
# @function __bulk_validate_range__
# @description Validate that a range is reasonable for bulk operations.
# @usage __bulk_validate_range__ <start> <end> [--max-range <n>]
# @param 1 Start ID
# @param 2 End ID
# @param --max-range Maximum allowed range (default: 1000)
# @return 0 if valid, 1 if invalid
__bulk_validate_range__() {
    local start_id="$1"
    local end_id="$2"
    shift 2

    __bulk_log__ "DEBUG" "Validating bulk range: $start_id-$end_id"

    local max_range=1000

    if [[ "$1" == "--max-range" ]]; then
        max_range="$2"
        __bulk_log__ "DEBUG" "Using custom max_range: $max_range"
    fi

    if ! __validate_vmid_range__ "$start_id" "$end_id" 2>/dev/null; then
        __bulk_log__ "ERROR" "Invalid VMID range"
        return 1
    fi

    local range=$((end_id - start_id + 1))

    if (( range > max_range )); then
        __bulk_log__ "ERROR" "Range too large: $range > $max_range"
        echo "Error: Range too large ($range > $max_range)" >&2
        echo "Use --max-range to override" >&2
        return 1
    fi

    __bulk_log__ "DEBUG" "Range validation passed: $range IDs"
    return 0
}

###############################################################################
# Example Usage (commented out)
###############################################################################
#
# # Simple bulk start
# __bulk_vm_operation__ --name "Start VMs" --report \
#   100 110 __vm_start__
#
# # Bulk configure with custom function
# configure_vm() {
#   local vmid="$1"
#   local memory="$2"
#   __vm_set_config__ "$vmid" --memory "$memory"
# }
# __bulk_vm_operation__ --name "Configure Memory" \
#   100 110 configure_vm 2048
#
# # With retry
# __bulk_with_retry__ 3 100 110 __vm_start__
#
# # Skip stopped VMs
# __bulk_vm_operation__ --skip-stopped --name "Restart VMs" \
#   100 110 __vm_restart__
#
# # Parallel execution (experimental)
# __bulk_parallel__ 5 100 110 __vm_start__
#
