#!/bin/bash
#
# ChangeAllMACPrefix.sh
#
# Updates MAC address prefixes for all VM (qemu) and LXC config files under /etc/pve
# to match either an explicitly provided prefix or the datacenter value in
# /etc/pve/datacenter.cfg (mac_prefix). Creates timestamped backups and optionally
# supports a dry-run mode that reports changes without writing.
#
# Usage:
#   ./ChangeAllMACPrefix.sh [--prefix AA:BB:CC] [--dry-run]
#
# Example:
#   ./ChangeAllMACPrefix.sh --prefix DE:AD:BE --dry-run
#
# Notes:
#   - Must be run as root on a Proxmox node.
#   - If --prefix is omitted, the script reads mac_prefix from /etc/pve/datacenter.cfg.
#   - Only the first three octets are rewritten; host-specific last three octets are preserved.
#
# Function Index:
#   - usage
#   - rewrite_file_mac_prefix
#   - main
#

DCFG="/etc/pve/datacenter.cfg"
BACKUP_DIR="/root/mac_prefix_backups/$(date +%Y%m%d_%H%M%S)"
DRY_RUN=0
OVERRIDE_PREFIX=""

# Source shared utilities if UTILITYPATH is provided (GUI.sh exports it)
if [[ -n "${UTILITYPATH:-}" ]]; then
  [[ -f "${UTILITYPATH}/Prompts.sh" ]] && source "${UTILITYPATH}/Prompts.sh" # shellcheck source=/dev/null
  [[ -f "${UTILITYPATH}/Communication.sh" ]] && source "${UTILITYPATH}/Communication.sh" # shellcheck source=/dev/null
fi

usage() {
  cat <<EOF
Usage: $0 [--prefix XX:YY:ZZ] [--dry-run] [--help]

Reads datacenter mac_prefix from $DCFG (unless overridden) and rewrites
MAC addresses in /etc/pve/qemu-server/*.conf and /etc/pve/lxc/*.conf to use
that prefix. Creates backups under $BACKUP_DIR.

Options:
  --prefix   Override the datacenter prefix (format: AA:BB:CC)
  --dry-run  Show what would be changed without writing files
  --help     Show this message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      OVERRIDE_PREFIX="$2"; shift 2;;
    --dry-run)
      DRY_RUN=1; shift;;
    --help|-h)
      usage; exit 0;;
    *)
      echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

rewrite_file_mac_prefix() {
  local file="$1"
  local tmp="$BACKUP_DIR/$(basename "$file")"
  cp -a "$file" "$tmp"

  sed -E \
    -e "s/(net[0-9]+:[[:space:]]*[^=]+=)[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:/\1${PREFIX_UPPER}:/g" \
    -e "s/(hwaddr=)[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:/\1${PREFIX_UPPER}:/g" \
    "$tmp" > "$tmp".new

  if ! cmp -s "$file" "$tmp".new; then
    echo "Changes in $file:" 
    diff -u "$file" "$tmp".new || true
    if [[ $DRY_RUN -eq 0 ]]; then
      mv "$tmp".new "$file"
      echo "Updated $file (backup at $tmp)"
    else
      echo "(dry-run) would update $file (backup at $tmp)"
      rm -f "$tmp".new
    fi
  else
    rm -f "$tmp".new
    echo "No changes for $file"
  fi
}

main() {
  # Root / environment checks
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (or via sudo)." >&2
    exit 1
  fi
  # If helper checks exist, use them (non-fatal if absent)
  command -v __check_proxmox__ &>/dev/null && __check_proxmox__ || true

  if [[ -n "${OVERRIDE_PREFIX}" ]]; then
    PREFIX="$OVERRIDE_PREFIX"
  else
    if [[ ! -f "$DCFG" ]]; then
      echo "$DCFG not found; cannot determine datacenter mac_prefix. Use --prefix to override." >&2
      exit 1
    fi
    PREFIX="$(grep -E '^mac_prefix:' "$DCFG" || true)"
    PREFIX="${PREFIX#mac_prefix: }"
  fi

  PREFIX_UPPER="$(echo "$PREFIX" | tr '[:lower:]' '[:upper:]' | xargs)"
  if [[ ! "$PREFIX_UPPER" =~ ^([0-9A-F]{2}):([0-9A-F]{2}):([0-9A-F]{2})$ ]]; then
    echo "Invalid MAC prefix: '$PREFIX'" >&2
    echo "Expected format: AA:BB:CC" >&2
    exit 2
  fi

  if command -v __info__ &>/dev/null; then
    __info__ "Using prefix $PREFIX_UPPER; preparing backups..."
  else
    echo "Using MAC prefix: $PREFIX_UPPER"
    echo "Creating backup directory: $BACKUP_DIR"
  fi
  mkdir -p "$BACKUP_DIR"

  shopt -s nullglob
  local changed=0
  for f in /etc/pve/qemu-server/*.conf; do
    [[ -f "$f" ]] || continue
    rewrite_file_mac_prefix "$f"
    changed=1
  done
  for f in /etc/pve/lxc/*.conf; do
    [[ -f "$f" ]] || continue
    rewrite_file_mac_prefix "$f"
    changed=1
  done

  if [[ $changed -eq 0 ]]; then
    echo "No VM/LXC config files found under /etc/pve/qemu-server or /etc/pve/lxc"
  fi

  if [[ $DRY_RUN -eq 0 ]]; then
    echo "Reloading pvedaemon to apply datacenter changes..."
    systemctl reload pvedaemon 2>/dev/null || true
  else
    echo "Dry-run: skipping pvedaemon reload"
  fi

  if command -v __ok__ &>/dev/null; then
    __ok__ "Completed MAC prefix update"
  else
    echo "Done. Backups are in $BACKUP_DIR"
  fi
}

main "$@"

###############################################################################
# Testing status
###############################################################################
# Tested: (pending) Single-node environment, dry-run validation.
# Add real test notes after first production run.
