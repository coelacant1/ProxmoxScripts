#!/bin/bash
#
# AddStorage.sh
#
# Adds NFS, SMB/CIFS, or Proxmox Backup Server (PBS) storage to a Proxmox VE cluster.
# This script configures the storage in the datacenter and makes it available across all nodes.
#
# Usage:
#   ./AddStorage.sh <storage_type> <storage_id> <server> [path] [options]
#
# Arguments:
#   storage_type - Type of storage: 'nfs', 'smb', 'cifs', or 'pbs'
#   storage_id   - Unique identifier/name for this storage in Proxmox
#   server       - Server hostname or IP address
#   path         - Export path for NFS (e.g., /mnt/storage) or share name for SMB/CIFS
#                  (Not required for PBS)
#
# Optional Arguments:
#   --content <types>    - Content types (default: vztmpl,backup,iso,snippets for NFS/SMB, backup for PBS)
#   --username <user>    - Username for SMB/CIFS or PBS authentication (required for PBS)
#   --password <pass>    - Password for SMB/CIFS or PBS authentication (required for PBS)
#   --domain <domain>    - Domain for SMB/CIFS authentication
#   --fingerprint <fp>   - SSL fingerprint for PBS (strongly recommended for security)
#                          Get fingerprint: proxmox-backup-manager cert info | grep Fingerprint
#   --datastore <name>   - Datastore name for PBS (default: same as storage_id)
#   --nodes <nodes>      - Comma-separated list of nodes (default: all nodes)
#   --options <opts>     - Additional NFS mount options (e.g., vers=3,soft)
#
# Examples:
#   # Add NFS storage
#   ./AddStorage.sh nfs NFS-Storage 192.168.1.100 /mnt/nfs-share
#   ./AddStorage.sh nfs NFS-Backup 192.168.1.100 /backup --content backup
#
#   # Add SMB/CIFS storage
#   ./AddStorage.sh smb SMB-Storage 192.168.1.200 SharedFolder --username admin --password pass123
#   ./AddStorage.sh cifs CIFS-ISO 192.168.1.200 ISOs --username admin --password pass123 --domain WORKGROUP
#
#   # Add Proxmox Backup Server (no path argument needed)
#   # Get fingerprint from PBS: proxmox-backup-manager cert info | grep Fingerprint
#   ./AddStorage.sh pbs PBS-Backup 192.168.1.50 --username backup@pbs --password secret --datastore main --fingerprint "AA:BB:CC:DD..."
#   ./AddStorage.sh pbs PBS-Backup 192.168.1.50 --username backup@pbs --password secret --datastore main --fingerprint "12:34:56:78..."
#
# Function Index:
#   - usage
#   - parse_args
#   - validate_storage_id
#   - add_nfs_storage
#   - add_smb_storage
#   - add_pbs_storage
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Global variables
STORAGE_TYPE=""
STORAGE_ID=""
SERVER=""
EXPORT_PATH=""
CONTENT=""
USERNAME=""
PASSWORD=""
DOMAIN=""
FINGERPRINT=""
DATASTORE=""
NODES=""
MOUNT_OPTIONS=""

# --- usage -------------------------------------------------------------------
# @function usage
# @description Prints usage information and exits.
usage() {
    cat <<-USAGE
Usage: ${0##*/} <storage_type> <storage_id> <server> [path] [options]

Adds NFS, SMB/CIFS, or PBS storage to the Proxmox cluster.

Arguments:
  storage_type - Storage type: 'nfs', 'smb', 'cifs', or 'pbs'
  storage_id   - Unique storage identifier/name
  server       - Server hostname or IP address
  path         - Export path (NFS) or share name (SMB/CIFS)
                 Not required for PBS storage

Optional Arguments:
  --content <types>      - Content types (comma-separated)
                          Default: vztmpl,backup,iso,snippets (NFS/SMB)
                                   backup (PBS)
  --username <user>      - Username (SMB/CIFS/PBS) - required for PBS
  --password <pass>      - Password (SMB/CIFS/PBS) - required for PBS
  --domain <domain>      - Domain (SMB/CIFS only)
  --fingerprint <fp>     - SSL fingerprint (PBS) - strongly recommended
                          Get from PBS: proxmox-backup-manager cert info
  --datastore <name>     - Datastore name (PBS only)
  --nodes <nodes>        - Target nodes (comma-separated, default: all)
  --options <opts>       - NFS mount options (e.g., vers=3,soft)

Examples:
  # NFS storage
  ${0##*/} nfs NFS-Storage 192.168.1.100 /mnt/nfs-share
  ${0##*/} nfs NFS-Backup 192.168.1.100 /backup --content backup

  # SMB/CIFS storage
  ${0##*/} smb SMB-Storage 192.168.1.200 SharedFolder --username admin --password pass123
  ${0##*/} cifs CIFS-ISO 192.168.1.200 ISOs --username admin --password pass123 --domain WORKGROUP

  # Proxmox Backup Server (no path argument)
  ${0##*/} pbs PBS-Backup 192.168.1.50 --username backup@pbs --password secret --datastore main --fingerprint "AA:BB:CC:DD..."
  ${0##*/} pbs PBS-Backup 192.168.1.50 --username backup@pbs --password secret --datastore main --fingerprint "12:34:56:78..."

Content Types:
  - images (VM disk images)
  - rootdir (LXC root directories)
  - vztmpl (LXC templates)
  - backup (Backups)
  - iso (ISO images)
  - snippets (Snippets/cloud-init)
USAGE
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 3 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    STORAGE_TYPE="${1,,}"  # Convert to lowercase
    STORAGE_ID="$2"
    SERVER="$3"
    shift 3

    # Validate storage type
    case "$STORAGE_TYPE" in
        nfs|smb|cifs|pbs)
            ;;
        *)
            __err__ "Invalid storage type: ${STORAGE_TYPE}"
            __err__ "Must be one of: nfs, smb, cifs, pbs"
            exit 64
            ;;
    esac

    # For PBS, EXPORT_PATH is not needed; for others, it's the 4th argument
    if [[ "$STORAGE_TYPE" != "pbs" ]]; then
        if [[ $# -lt 1 || "$1" == --* ]]; then
            __err__ "Missing required argument: path/export/share"
            usage
            exit 64
        fi
        EXPORT_PATH="$1"
        shift
    fi

    # Parse optional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --content)
                CONTENT="$2"
                shift 2
                ;;
            --username)
                USERNAME="$2"
                shift 2
                ;;
            --password)
                PASSWORD="$2"
                shift 2
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --fingerprint)
                FINGERPRINT="$2"
                shift 2
                ;;
            --datastore)
                DATASTORE="$2"
                shift 2
                ;;
            --nodes)
                NODES="$2"
                shift 2
                ;;
            --options)
                MOUNT_OPTIONS="$2"
                shift 2
                ;;
            *)
                __err__ "Unknown option: $1"
                usage
                exit 64
                ;;
        esac
    done

    # Set default content types if not specified
    if [[ -z "$CONTENT" ]]; then
        case "$STORAGE_TYPE" in
            nfs|smb|cifs)
                CONTENT="vztmpl,backup,iso,snippets"
                ;;
            pbs)
                CONTENT="backup"
                ;;
        esac
    fi

    # Set default datastore for PBS if not specified
    if [[ "$STORAGE_TYPE" == "pbs" ]] && [[ -z "$DATASTORE" ]]; then
        DATASTORE="$STORAGE_ID"
    fi

    # Validate required fields based on storage type
    if [[ "$STORAGE_TYPE" == "pbs" ]]; then
        if [[ -z "$USERNAME" ]]; then
            __err__ "PBS storage requires --username"
            exit 64
        fi
        if [[ -z "$PASSWORD" ]]; then
            __err__ "PBS storage requires --password"
            exit 64
        fi
        if [[ -z "$FINGERPRINT" ]]; then
            __warn__ "PBS storage strongly recommends --fingerprint for secure connection"
            __warn__ "Proceeding without fingerprint - connection may fail"
            __info__ "To get the fingerprint, run on the PBS server:"
            __info__ "  proxmox-backup-manager cert info | grep Fingerprint"
        fi
    fi
}

# --- validate_storage_id -----------------------------------------------------
# @function validate_storage_id
# @description Checks if storage ID already exists.
# @return 0 if storage doesn't exist, 1 if it does
validate_storage_id() {
    if pvesm status --storage "$STORAGE_ID" &>/dev/null; then
        __err__ "Storage ID '${STORAGE_ID}' already exists"
        __info__ "Use a different storage ID or remove the existing storage first"
        return 1
    fi
    return 0
}

# --- add_nfs_storage ---------------------------------------------------------
# @function add_nfs_storage
# @description Adds NFS storage to the cluster.
add_nfs_storage() {
    __info__ "Adding NFS storage: ${STORAGE_ID}"
    __info__ "  Server: ${SERVER}"
    __info__ "  Export: ${EXPORT_PATH}"
    __info__ "  Content: ${CONTENT}"
    [[ -n "$NODES" ]] && __info__ "  Nodes: ${NODES}"
    [[ -n "$MOUNT_OPTIONS" ]] && __info__ "  Options: ${MOUNT_OPTIONS}"

    local cmd="pvesm add nfs \"${STORAGE_ID}\" --server \"${SERVER}\" --export \"${EXPORT_PATH}\" --content \"${CONTENT}\""
    
    [[ -n "$NODES" ]] && cmd+=" --nodes \"${NODES}\""
    [[ -n "$MOUNT_OPTIONS" ]] && cmd+=" --options \"${MOUNT_OPTIONS}\""

    # Redirect stdin to prevent any interactive prompts from hanging
    if eval "$cmd" </dev/null 2>&1; then
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
    __info__ "Adding SMB/CIFS storage: ${STORAGE_ID}"
    __info__ "  Server: ${SERVER}"
    __info__ "  Share: ${EXPORT_PATH}"
    __info__ "  Content: ${CONTENT}"
    [[ -n "$USERNAME" ]] && __info__ "  Username: ${USERNAME}"
    [[ -n "$DOMAIN" ]] && __info__ "  Domain: ${DOMAIN}"
    [[ -n "$NODES" ]] && __info__ "  Nodes: ${NODES}"

    local cmd="pvesm add cifs \"${STORAGE_ID}\" --server \"${SERVER}\" --share \"${EXPORT_PATH}\" --content \"${CONTENT}\""
    
    if [[ -n "$USERNAME" ]]; then
        cmd+=" --username \"${USERNAME}\""
        
        if [[ -n "$PASSWORD" ]]; then
            cmd+=" --password \"${PASSWORD}\""
        fi
    fi
    
    [[ -n "$DOMAIN" ]] && cmd+=" --domain \"${DOMAIN}\""
    [[ -n "$NODES" ]] && cmd+=" --nodes \"${NODES}\""

    # Redirect stdin to prevent any interactive prompts from hanging
    if eval "$cmd" </dev/null 2>&1; then
        __ok__ "SMB/CIFS storage '${STORAGE_ID}' added successfully"
        return 0
    else
        __err__ "Failed to add SMB/CIFS storage"
        return 1
    fi
}

# --- add_pbs_storage ---------------------------------------------------------
# @function add_pbs_storage
# @description Adds Proxmox Backup Server storage to the cluster.
add_pbs_storage() {
    __info__ "Adding PBS storage: ${STORAGE_ID}"
    __info__ "  Server: ${SERVER}"
    __info__ "  Username: ${USERNAME}"
    __info__ "  Datastore: ${DATASTORE}"
    
    if [[ -n "$FINGERPRINT" ]]; then
        __info__ "  Fingerprint: ${FINGERPRINT}"
    else
        __warn__ "  Fingerprint: NOT PROVIDED (connection may fail)"
    fi
    
    [[ -n "$NODES" ]] && __info__ "  Nodes: ${NODES}"

    local cmd="pvesm add pbs \"${STORAGE_ID}\" --server \"${SERVER}\" --username \"${USERNAME}\" --datastore \"${DATASTORE}\""
    
    if [[ -n "$PASSWORD" ]]; then
        cmd+=" --password \"${PASSWORD}\""
    fi
    
    [[ -n "$FINGERPRINT" ]] && cmd+=" --fingerprint \"${FINGERPRINT}\""
    [[ -n "$NODES" ]] && cmd+=" --nodes \"${NODES}\""

    # Redirect stdin to prevent any interactive prompts from hanging
    if eval "$cmd" </dev/null 2>&1; then
        __ok__ "PBS storage '${STORAGE_ID}' added successfully"
        return 0
    else
        __err__ "Failed to add PBS storage"
        if [[ -z "$FINGERPRINT" ]]; then
            echo
            __info__ "Common issue: Missing or incorrect SSL fingerprint"
            __info__ "Get the fingerprint from your PBS server:"
            __info__ "  SSH to PBS: ssh root@${SERVER}"
            __info__ "  Run: proxmox-backup-manager cert info | grep Fingerprint"
            __info__ "  Or check PBS web UI: Configuration -> Certificates"
        fi
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - adds storage based on type.
main() {
    __check_root__
    __check_proxmox__

    # Validate storage ID doesn't already exist
    if ! validate_storage_id; then
        exit 1
    fi

    # Confirm action with user
    __info__ "Adding ${STORAGE_TYPE^^} storage to cluster:"
    __info__ "  Storage ID: ${STORAGE_ID}"
    __info__ "  Server: ${SERVER}"

    # Add storage based on type
    case "$STORAGE_TYPE" in
        nfs)
            if add_nfs_storage; then
                echo
                __ok__ "Storage added successfully"
                __info__ "You can now use '${STORAGE_ID}' in your VMs and containers"
            else
                exit 1
            fi
            ;;
        smb|cifs)
            if add_smb_storage; then
                echo
                __ok__ "Storage added successfully"
                __info__ "You can now use '${STORAGE_ID}' in your VMs and containers"
            else
                exit 1
            fi
            ;;
        pbs)
            if add_pbs_storage; then
                echo
                __ok__ "Storage added successfully"
                __info__ "You can now use '${STORAGE_ID}' for backups"
            else
                exit 1
            fi
            ;;
    esac

    # Show storage status
    echo
    __info__ "Storage status:"
    pvesm status --storage "$STORAGE_ID" 2>/dev/null || true
}

###############################################################################
# Script Entry Point
###############################################################################
parse_args "$@"
main
