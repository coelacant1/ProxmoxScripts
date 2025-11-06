#!/bin/bash
#
# ChangeAllMACPrefix.sh
#
# Updates MAC address prefixes for all VM and LXC configurations.
#
# Usage:
#   ChangeAllMACPrefix.sh [--prefix AA:BB:CC] [--dry-run]
#
# Optional Arguments:
#   --prefix <mac> - MAC prefix (AA:BB:CC format)
#   --dry-run      - Show changes without applying
#
# Examples:
#   ChangeAllMACPrefix.sh --prefix DE:AD:BE --dry-run
#   ChangeAllMACPrefix.sh
#
# Function Index:
#   - rewrite_file_mac_prefix
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "--prefix:string:? --dry-run:flag" "$@"

DCFG="/etc/pve/datacenter.cfg"

# --- rewrite_file_mac_prefix ------------------------------------------------
rewrite_file_mac_prefix() {
    local file="$1"
    local prefix_upper="$2"
    local backup_dir="$3"
    local dry_run="$4"

    local tmp="$backup_dir/$(basename "$file")"
    cp -a "$file" "$tmp"

    sed -E \
        -e "s/(net[0-9]+:[[:space:]]*[^=]+=)[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:/\1${prefix_upper}:/g" \
        -e "s/(hwaddr=)[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:/\1${prefix_upper}:/g" \
        "$tmp" > "$tmp".new

    if ! cmp -s "$file" "$tmp".new; then
        __info__ "Changes detected: $(basename "$file")"
        diff -u "$file" "$tmp".new || true

        if [[ "$dry_run" != "true" ]]; then
            mv "$tmp".new "$file"
            __ok__ "Updated: $(basename "$file")"
        else
            __warn__ "[DRY-RUN] Would update: $(basename "$file")"
            rm -f "$tmp".new
        fi
        return 0
    else
        rm -f "$tmp".new
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Determine MAC prefix
    local prefix
    if [[ -n "$PREFIX" ]]; then
        prefix="$PREFIX"
        __info__ "Using provided prefix: $prefix"
    else
        if [[ ! -f "$DCFG" ]]; then
            __err__ "Datacenter config not found: $DCFG"
            echo "Use --prefix to specify MAC prefix"
            exit 1
        fi

        prefix="$(grep -E '^mac_prefix:' "$DCFG" | cut -d: -f2- | xargs || true)"

        if [[ -z "$prefix" ]]; then
            __err__ "No mac_prefix found in $DCFG"
            echo "Use --prefix to specify MAC prefix"
            exit 1
        fi

        __info__ "Using datacenter prefix: $prefix"
    fi

    # Validate and normalize prefix
    local prefix_upper
    prefix_upper="$(echo "$prefix" | tr '[:lower:]' '[:upper:]' | xargs)"

    if [[ ! "$prefix_upper" =~ ^([0-9A-F]{2}):([0-9A-F]{2}):([0-9A-F]{2})$ ]]; then
        __err__ "Invalid MAC prefix: $prefix"
        echo "Expected format: AA:BB:CC"
        exit 64
    fi

    # Setup backup directory
    local backup_dir="/root/mac_prefix_backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    if [[ "$DRY_RUN" == "true" ]]; then
        __warn__ "DRY-RUN MODE - No changes will be applied"
    fi

    __info__ "MAC prefix: $prefix_upper"
    __info__ "Backup directory: $backup_dir"

    echo
    if ! __prompt_yes_no__ "Update all VM/LXC MAC addresses to use prefix $prefix_upper?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    # Process config files
    shopt -s nullglob
    local -a qemu_files=(/etc/pve/qemu-server/*.conf)
    local -a lxc_files=(/etc/pve/lxc/*.conf)
    shopt -u nullglob

    local total_files=$((${#qemu_files[@]} + ${#lxc_files[@]}))

    if [[ $total_files -eq 0 ]]; then
        __warn__ "No VM/LXC config files found"
        exit 0
    fi

    __info__ "Processing ${#qemu_files[@]} VM(s) and ${#lxc_files[@]} LXC(s)"
    echo

    local changed=0
    local processed=0

    for file in "${qemu_files[@]}" "${lxc_files[@]}"; do
        [[ -f "$file" ]] || continue
        ((processed++))

        if rewrite_file_mac_prefix "$file" "$prefix_upper" "$backup_dir" "$DRY_RUN"; then
            ((changed++))
        fi
    done

    echo
    __info__ "Summary:"
    __info__ "  Files processed: $processed"
    __info__ "  Files changed: $changed"
    __info__ "  Files unchanged: $((processed - changed))"

    if [[ "$DRY_RUN" != "true" ]]; then
        if [[ $changed -gt 0 ]]; then
            __update__ "Reloading pvedaemon"
            if systemctl reload pvedaemon 2>/dev/null; then
                __ok__ "pvedaemon reloaded"
            else
                __warn__ "Failed to reload pvedaemon"
            fi
        fi

        echo
        __ok__ "MAC prefix update completed!"
        __info__ "Backups saved to: $backup_dir"
    else
        echo
        __warn__ "DRY-RUN: No changes applied"
        __info__ "Run without --dry-run to apply changes"
    fi
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Updated to use ArgumentParser.sh
#   - Pending validation
