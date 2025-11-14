#!/bin/bash
#
# AddStorage.sh
#
# Adds NFS, SMB/CIFS, or Proxmox Backup Server (PBS) storage to a Proxmox VE cluster.
# This script configures the storage in the datacenter and makes it available across all nodes.
#
# Usage:
#   AddStorage.sh nfs NFS-Storage 192.168.1.100 --export /mnt/nfs-share
#   AddStorage.sh nfs NFS-Backup 192.168.1.100 --export /backup --content backup
#   AddStorage.sh smb SMB-Storage 192.168.1.200 --export SharedFolder --username admin --password pass123
#   AddStorage.sh cifs CIFS-ISO 192.168.1.200 --export ISOs --username admin --password pass123 --domain WORKGROUP
#   AddStorage.sh pbs PBS-Backup 192.168.1.50 --username backup@pbs --password secret --datastore main --fingerprint "AA:BB:CC:DD..."
#
# Arguments:
#   storage_type         - Type of storage: 'nfs', 'smb', 'cifs', or 'pbs'
#   storage_id           - Unique identifier/name for this storage in Proxmox
#   server               - Server hostname or IP address
#   --export <path>      - Export path for NFS (e.g., /mnt/storage) or share name for SMB/CIFS
#                          (Required for NFS/SMB/CIFS, not used for PBS)
#   --content <types>    - Content types (default: vztmpl,backup,iso,snippets for NFS/SMB, backup for PBS)
#   --username <user>    - Username for SMB/CIFS or PBS authentication (required for PBS)
#   --password <pass>    - Password for SMB/CIFS or PBS authentication (required for PBS)
#   --domain <domain>    - Domain for SMB/CIFS authentication
#   --fingerprint <fp>   - SSL fingerprint for PBS (strongly recommended for security)
#   --datastore <name>   - Datastore name for PBS (default: same as storage_id)
#   --nodes <nodes>      - Comma-separated list of nodes (default: all nodes)
#   --options <opts>     - Additional NFS mount options (e.g., vers=3,soft)
#
# Content Types: images, rootdir, vztmpl, backup, iso, snippets
#
# Notes:
#   - For PBS storage, --export is not required (PBS doesn't use export paths)
#   - PBS requires --username and --password, should have --fingerprint for security
#   - Get PBS fingerprint: proxmox-backup-manager cert info | grep Fingerprint
#
# Function Index:
#   - validate_custom_options
#   - validate_storage_id
#   - add_nfs_storage
#   - add_smb_storage
#   - add_pbs_storage
#   - main
#

set -euo pipefail

# Ensure Proxmox binaries are in PATH
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Define error handler before sourcing (in case sourcing fails)
__early_err__() {
    echo "[ERROR] Failed to initialize script at line $1: $2" >&2
    echo "UTILITYPATH=${UTILITYPATH:-not set}" >&2
    echo "Check that utilities were transferred correctly" >&2
    exit 1
}
trap '__early_err__ $LINENO "$BASH_COMMAND"' ERR

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Logger.sh
source "${UTILITYPATH}/Logger.sh"

# Now use the proper error handler from Communication.sh
trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- validate_custom_options -------------------------------------------------
# @function validate_custom_options
# @description Validates storage-specific configuration options not covered by ArgumentParser.
validate_custom_options() {
    # Validate storage type
    local storage_type_lower="${STORAGE_TYPE,,}"
    case "$storage_type_lower" in
        nfs|smb|cifs|pbs)
            STORAGE_TYPE="$storage_type_lower"
            ;;
        *)
            __err__ "Invalid storage type: ${STORAGE_TYPE}"
            __err__ "Must be one of: nfs, smb, cifs, pbs"
            exit 64
            ;;
    esac

    # Validate storage ID format (alphanumeric, hyphen, underscore)
    validate_storage_id "$STORAGE_ID"

    # For non-PBS storage, export path is required
    if [[ "$STORAGE_TYPE" != "pbs" && -z "$EXPORT" ]]; then
        __err__ "Export path/share is required for ${STORAGE_TYPE} storage (use --export)"
        exit 64
    fi

    # For PBS, username and password are required
    if [[ "$STORAGE_TYPE" == "pbs" ]]; then
        if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
            __err__ "PBS storage requires --username and --password"
            exit 64
        fi
        
        if [[ -z "$FINGERPRINT" ]]; then
            __warn__ "WARNING: PBS without fingerprint is insecure!"
            __warn__ "Get fingerprint from PBS: proxmox-backup-manager cert info | grep Fingerprint"
        fi
    fi
}

# --- validate_storage_id -----------------------------------------------------
# @function validate_storage_id
# @description Validates storage ID format and checks if it already exists.
# @param 1 Storage ID to validate
validate_storage_id() {
    local id="$1"

    # Check format (alphanumeric, hyphen, underscore)
    if ! [[ "$id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        __err__ "Invalid storage ID format: ${id}"
        __err__ "Storage ID must contain only letters, numbers, hyphens, and underscores"
        exit 64
    fi

    # Check if storage already exists (only if pvesm is available)
    if command -v pvesm >/dev/null 2>&1; then
        if pvesm status 2>/dev/null | grep -q "^${id} "; then
            __err__ "Storage '${id}' already exists"
            exit 64
        fi
    fi
}

# --- add_nfs_storage ---------------------------------------------------------
# @function add_nfs_storage
# @description Adds NFS storage to the cluster.
add_nfs_storage() {
    __info__ "Adding NFS storage '${STORAGE_ID}'..."

    local cmd="pvesm add nfs ${STORAGE_ID} --server ${SERVER} --export ${EXPORT}"

    [[ -n "$CONTENT" ]] && cmd+=" --content ${CONTENT}"
    [[ -n "$NODES" ]] && cmd+=" --nodes ${NODES}"
    [[ -n "$OPTIONS" ]] && cmd+=" --options ${OPTIONS}"

    if eval "$cmd"; then
        __ok__ "NFS storage '${STORAGE_ID}' added successfully"
        return 0
    else
        __err__ "Failed to add NFS storage"
        return 1
    fi
}

# --- add_smb_storage ---------------------------------------------------------
# @function add_smb_storage
# @description Adds SMB/CIFS storage to the cluster.
add_smb_storage() {
    __info__ "Adding SMB/CIFS storage '${STORAGE_ID}'..."

    local cmd="pvesm add cifs ${STORAGE_ID} --server ${SERVER} --share ${EXPORT}"

    [[ -n "$USERNAME" ]] && cmd+=" --username ${USERNAME}"
    [[ -n "$PASSWORD" ]] && cmd+=" --password ${PASSWORD}"
    [[ -n "$DOMAIN" ]] && cmd+=" --domain ${DOMAIN}"
    [[ -n "$CONTENT" ]] && cmd+=" --content ${CONTENT}"
    [[ -n "$NODES" ]] && cmd+=" --nodes ${NODES}"

    if eval "$cmd"; then
        __ok__ "${STORAGE_TYPE^^} storage '${STORAGE_ID}' added successfully"
        return 0
    else
        __err__ "Failed to add ${STORAGE_TYPE^^} storage"
        return 1
    fi
}

# --- add_pbs_storage ---------------------------------------------------------
# @function add_pbs_storage
# @description Adds Proxmox Backup Server storage to the cluster.
add_pbs_storage() {
    __info__ "Adding PBS storage '${STORAGE_ID}'..."

    local datastore_name="${DATASTORE:-$STORAGE_ID}"
    local content="${CONTENT:-backup}"

    local cmd="pvesm add pbs ${STORAGE_ID} --server ${SERVER} --username ${USERNAME} --password ${PASSWORD} --datastore ${datastore_name} --content ${content}"

    [[ -n "$FINGERPRINT" ]] && cmd+=" --fingerprint ${FINGERPRINT}"
    [[ -n "$NODES" ]] && cmd+=" --nodes ${NODES}"

    if eval "$cmd"; then
        __ok__ "PBS storage '${STORAGE_ID}' added successfully"
        return 0
    else
        __err__ "Failed to add PBS storage"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __log_function_entry__ "$@"
    
    __check_root__
    __log_debug__ "Root check passed" "STORAGE"
    
    __check_proxmox__
    __log_debug__ "Proxmox check passed" "STORAGE"

    # Parse arguments using ArgumentParser
    __log_debug__ "Parsing arguments: $*" "STORAGE"
    __parse_args__ "storage_type:string storage_id:string server:string --export:string:? --content:string:? --username:string:? --password:string:? --domain:string:? --fingerprint:string:? --datastore:string:? --nodes:string:? --options:string:?" "$@"
    __log_debug__ "Arguments parsed successfully" "STORAGE"

    # Additional custom validation
    __log_debug__ "Validating custom options" "STORAGE"
    validate_custom_options
    __log_debug__ "Custom validation passed" "STORAGE"

    __info__ "Storage Configuration:"
    __info__ "  Type: ${STORAGE_TYPE}"
    __info__ "  ID: ${STORAGE_ID}"
    __info__ "  Server: ${SERVER}"
    [[ -n "$EXPORT" ]] && __info__ "  Export/Share: ${EXPORT}"
    [[ -n "$CONTENT" ]] && __info__ "  Content: ${CONTENT}"
    [[ -n "$USERNAME" ]] && __info__ "  Username: ${USERNAME}"
    [[ -n "$DOMAIN" ]] && __info__ "  Domain: ${DOMAIN}"
    [[ -n "$DATASTORE" ]] && __info__ "  Datastore: ${DATASTORE}"
    [[ -n "$NODES" ]] && __info__ "  Nodes: ${NODES}"
    [[ -n "$OPTIONS" ]] && __info__ "  Options: ${OPTIONS}"

    # Confirm action
    if ! __prompt_user_yn__ "Add ${STORAGE_TYPE^^} storage '${STORAGE_ID}'?"; then
        __info__ "Operation cancelled by user"
        exit 0
    fi

    # Add storage based on type
    case "$STORAGE_TYPE" in
        nfs)
            add_nfs_storage
            ;;
        smb|cifs)
            add_smb_storage
            ;;
        pbs)
            add_pbs_storage
            ;;
    esac

    # Display storage status
    __info__ "Storage status:"
    pvesm status | grep -E "^(Name|${STORAGE_ID})"
}

main "$@"

# Testing status:
#   - 2025-11-04: Refactored to use ArgumentParser.sh declarative parsing
#   - Removed manual usage() and parse_args() functions
#   - Now uses __parse_args__ with automatic validation
#   - Fixed __prompt_yes_no__ -> __prompt_user_yn__
#   - Handles optional path argument for PBS storage
