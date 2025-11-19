#!/bin/bash
#
# _ExampleStateManagement.sh
#
# Example demonstrating StateManager.sh integration for VM/CT configuration
# backup, restore, and comparison operations.
#
# Usage:
#   _ExampleStateManagement.sh save <vmid|ctid> [state_name]
#   _ExampleStateManagement.sh restore <vmid|ctid> <state_name> [--force]
#   _ExampleStateManagement.sh compare <vmid|ctid> <state_name>
#   _ExampleStateManagement.sh list [vmid|ctid]
#   _ExampleStateManagement.sh snapshot-cluster
#
# Examples:
#   # Save VM 100 state before changes
#   _ExampleStateManagement.sh save 100 before_upgrade
#
#   # Compare current state with saved state
#   _ExampleStateManagement.sh compare 100 before_upgrade
#
#   # Restore VM to previous state (with confirmation)
#   _ExampleStateManagement.sh restore 100 before_upgrade
#
#   # Restore VM to previous state (no confirmation)
#   _ExampleStateManagement.sh restore 100 before_upgrade --force
#
#   # List all saved states for VM 100
#   _ExampleStateManagement.sh list 100
#
#   # Snapshot entire cluster
#   _ExampleStateManagement.sh snapshot-cluster
#
# Function Index:
#   - usage
#   - main
#

set -euo pipefail

###############################################################################
# Setup / Globals
###############################################################################

# Source utilities
source "${UTILITYPATH}/StateManager.sh"
source "${UTILITYPATH}/Communication.sh"
source "${UTILITYPATH}/Logger.sh"

###############################################################################
# Initial checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Usage
###############################################################################
usage() {
    cat <<-USAGE
		Usage: ${0##*/} <command> [options]

		Commands:
		  save <id> [name]              Save VM/CT state
		  restore <id> <name> [--force] Restore VM/CT from saved state
		  compare <id> <name>           Compare current state with saved state
		  list [id]                     List saved states (optionally for specific VM/CT)
		  snapshot-cluster              Save state of entire cluster

		Arguments:
		  id                            VMID (100-999) or CTID (1000+)
		  name                          State name (default: timestamp)
		  --force                       Skip confirmation prompt

		Examples:
		  ${0##*/} save 100 before_upgrade
		  ${0##*/} compare 100 before_upgrade
		  ${0##*/} restore 100 before_upgrade
		  ${0##*/} list 100
		  ${0##*/} snapshot-cluster

		State Files Location: /var/lib/proxmox-states/

	USAGE
    exit 1
}

###############################################################################
# Main Logic
###############################################################################
main() {
    local command="${1:-}"

    if [[ -z "$command" ]]; then
        usage
    fi

    case "$command" in
        save)
            local id="${2:-}"
            local name="${3:-$(date +%Y%m%d_%H%M%S)}"

            if [[ -z "$id" ]]; then
                __error__ "ID required for save command"
                usage
            fi

            # Determine if VM or CT based on ID range
            if [[ $id -lt 1000 ]]; then
                __info__ "Saving VM $id state as '$name'..."
                __state_save_vm__ "$id" "$name"
            else
                __info__ "Saving CT $id state as '$name'..."
                __state_save_ct__ "$id" "$name"
            fi
            ;;

        restore)
            local id="${2:-}"
            local name="${3:-}"
            local force_flag="${4:-}"

            if [[ -z "$id" ]] || [[ -z "$name" ]]; then
                __error__ "ID and state name required for restore command"
                usage
            fi

            # Determine if VM or CT based on ID range
            if [[ $id -lt 1000 ]]; then
                __info__ "Restoring VM $id from state '$name'..."
                __state_restore_vm__ "$id" "$name" "$force_flag"
            else
                __info__ "Restoring CT $id from state '$name'..."
                __state_restore_ct__ "$id" "$name" "$force_flag"
            fi
            ;;

        compare)
            local id="${2:-}"
            local name="${3:-}"

            if [[ -z "$id" ]] || [[ -z "$name" ]]; then
                __error__ "ID and state name required for compare command"
                usage
            fi

            # Determine if VM or CT based on ID range
            if [[ $id -lt 1000 ]]; then
                __info__ "Comparing VM $id with state '$name'..."
                __state_compare_vm__ "$id" "$name"
            else
                __info__ "Comparing CT $id with state '$name'..."
                __state_compare_ct__ "$id" "$name"
            fi
            ;;

        list)
            local id="${2:-}"

            if [[ -z "$id" ]]; then
                __info__ "Listing all saved states..."
                __state_list__
            else
                __info__ "Listing states for ID $id..."
                __state_list__ "$id"
            fi
            ;;

        snapshot-cluster)
            __info__ "Creating snapshot of entire cluster..."
            __state_snapshot_cluster__
            ;;

        *)
            __error__ "Unknown command: $command"
            usage
            ;;
    esac
}

# Run main
main "$@"
