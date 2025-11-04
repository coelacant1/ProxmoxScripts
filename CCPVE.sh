#!/bin/bash
#
# CCPVE.sh
#
# The main script to download and extract the ProxmoxScripts repository, then make all scripts
# in the repository executable and finally call CCPVEOffline.sh.
#
# Usage:
#   ./CCPVE.sh [-h]
#   ./CCPVE.sh --list
#   ./CCPVE.sh --run <relative/script/path.sh> [--args "arg1 arg2 ..."]
#   ./CCPVE.sh --testing
#   ./CCPVE.sh --branch <branch-name>
#
# Examples:
#   bash -c "$(wget -qLO - https://github.com/coelacant1/ProxmoxScripts/raw/main/CCPVE.sh)" --list
#   bash -c "$(wget -qLO - https://github.com/coelacant1/ProxmoxScripts/raw/main/CCPVE.sh)" --run Host/QuickDiagnostic.sh
#   bash <(curl -L pve.coela.sh) --run Storage/Benchmark.sh --args "--device /dev/sda --mode quick"
#
# This script requires 'unzip' and 'wget'. If not installed, it will prompt to install them.
#
# Example:
#   bash -c "$(wget -qLO - https://github.com/coelacant1/ProxmoxScripts/raw/main/CCPVE.sh)"
#

set -euo pipefail

apt update || true

# By default do not show the GUI header; use -h to display it
SHOW_HEADER="false"
RUN_SCRIPT=""
RUN_ARGS=""
DO_LIST="false"
# Branch selection (default: main)
GIT_BRANCH="main"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            SHOW_HEADER="true"
            shift
            ;;
        --run)
            RUN_SCRIPT="$2"; shift 2 ;;
        --args)
            RUN_ARGS="$2"; shift 2 ;;
        --list)
            DO_LIST="true"; shift ;;
        --testing)
            # Short-hand to use the testing branch
            GIT_BRANCH="testing"; shift ;;
        --branch)
            if [ -n "$2" ]; then
                GIT_BRANCH="$2"; shift 2
            else
                echo "Error: --branch requires an argument" >&2; exit 1
            fi
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            exit 1 ;;
    esac
done

# --- Branch Warning Banner --------------------------------------------------
if [ "$GIT_BRANCH" != "main" ]; then
    # Basic ANSI colors (avoid relying on repo utilities before download)
    YELLOW="\033[1;33m"; RED="\033[1;31m"; RESET="\033[0m"; BOLD="\033[1m";
    if [ "$GIT_BRANCH" = "testing" ]; then
        echo -e "${YELLOW}=============================================================${RESET}" >&2
        echo -e "${YELLOW}${BOLD}  TESTING BRANCH SELECTED${RESET}" >&2
        echo -e "${YELLOW}  This branch contains experimental / unstable changes.${RESET}" >&2
        echo -e "${YELLOW}  Branch: ${BOLD}${GIT_BRANCH}${RESET}" >&2
        echo -e "${YELLOW}=============================================================${RESET}" >&2
    else
        echo -e "${RED}${BOLD}WARNING:${RESET} Using non-main branch: ${YELLOW}${GIT_BRANCH}${RESET}" >&2
    fi
fi

# --- Check Dependencies -----------------------------------------------------
if ! command -v unzip &>/dev/null; then
    echo "The 'unzip' utility is required to extract the downloaded files but is not installed."
    read -r -p "Would you like to install 'unzip' now? [y/N]: " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        apt-get install -y unzip
    else
        echo "Aborting script because 'unzip' is not installed."
        exit 1
    fi
fi

if ! command -v wget &>/dev/null; then
    echo "The 'wget' utility is required to download the repository ZIP but is not installed."
    read -r -p "Would you like to install 'wget' now? [y/N]: " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        apt-get install -y wget
    else
        echo "Aborting script because 'wget' is not installed."
        exit 1
    fi
fi

# --- Configuration ----------------------------------------------------------
REPO_ZIP_URL="https://github.com/coelacant1/ProxmoxScripts/archive/refs/heads/${GIT_BRANCH}.zip"
TARGET_DIR="/tmp/cc_pve"

# --- Download and Extract ---------------------------------------------------
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

echo "Downloading repository ZIP from $REPO_ZIP_URL..."
if ! wget -q -O "$TARGET_DIR/repo.zip" "$REPO_ZIP_URL"; then
    echo "Error: Failed to download from $REPO_ZIP_URL"
    exit 1
fi

echo "Extracting ZIP..."
if ! unzip -q "$TARGET_DIR/repo.zip" -d "$TARGET_DIR"; then
    echo "Error: Failed to unzip the downloaded file."
    exit 1
fi

# Find the first extracted folder that isn't a dot-folder
BASE_EXTRACTED_DIR=$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".*" | head -n1)
if [ -z "$BASE_EXTRACTED_DIR" ]; then
    echo "Error: No extracted content found."
    exit 1
fi

echo "Repository extracted into: $BASE_EXTRACTED_DIR"

# --- Make Scripts Executable -----------------------------------------------
echo "Making all scripts executable..."
cd "$BASE_EXTRACTED_DIR" || exit 1
if [ -f "./MakeScriptsExecutable.sh" ]; then
    bash "./MakeScriptsExecutable.sh"
else
    echo "Warning: MakeScriptsExecutable.sh not found. Skipping."
fi

# --- Call GUI.sh --------------------------------------------------
if [ -f "./GUI.sh" ]; then
    # --- List Mode --------------------------------------------------------------
    if [ "$DO_LIST" = "true" ]; then
        echo "Listing runnable scripts (relative paths):"
        # Exclude Utilities and hidden dirs
        find . -type f -name '*.sh' \
            ! -path './Utilities/*' ! -path '*/.*/*' \
            | sed 's|^./||' | sort
        echo "Use: CCPVE.sh --run <path> [--args \"...\"]"
        exit 0
    fi

    # --- Direct Run Mode --------------------------------------------------------
    if [ -n "$RUN_SCRIPT" ]; then
        # Normalize path (strip leading ./ if present)
        RUN_SCRIPT="${RUN_SCRIPT#./}"
        if [ ! -f "$RUN_SCRIPT" ]; then
            echo "Error: Requested script '$RUN_SCRIPT' not found after extraction." >&2
            echo "Hint: Use --list to see available scripts." >&2
            exit 2
        fi
        echo "Executing requested script: $RUN_SCRIPT"
        chmod +x "$RUN_SCRIPT" || true
        export UTILITYPATH="$(realpath ./Utilities)"
        # shellcheck disable=SC2086
        bash "$RUN_SCRIPT" ${RUN_ARGS}
        echo "Done."
        exit 0
    fi

    echo "Calling GUI.sh..."
    if [ "$SHOW_HEADER" = "true" ]; then
        bash "./GUI.sh" -h
    else
        bash "./GUI.sh"
    fi
else
    echo "Warning: GUI.sh not found. Skipping."
fi

echo "Done."
