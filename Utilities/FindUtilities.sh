#!/bin/bash
#
# A helper function to locate Utilities/Utilities.sh by traversing **relative paths only**,
# moving upward until it finds a file named "CCPVE.sh" in the same directory, which denotes
# our script's root. It then checks for "Utilities/Utilities.sh" in that directory.
#
# This function attempts to handle cases where you might source it or run it directly
# from different directories. However, if you're typing functions interactively at the
# shell prompt (where $0 might just be "bash"), the function can't reliably detect the
# script location. In that scenario, best practice is to place this function in an actual
# script file and run that script normally (rather than copy/pasting it in an interactive
# shell).
#
# Usage in a script:
#   UTILITIES_SCRIPT="$(find_utilities_script)" || exit 1
#   source "$UTILITIES_SCRIPT"

# ---------------------------------------------------------------------------
# @function find_utilities_script
# @description
#   Finds the root directory of the scripts folder by traversing upward until
#   it finds a folder containing a Utilities subfolder.
#   Returns the full path to Utilities/Utilities.sh if found, or exits with an
#   error if not found within 15 levels.
# ---------------------------------------------------------------------------
find_utilities_script() {
  # Check current directory first
  if [[ -d "./Utilities" ]]; then
    echo "./Utilities/Utilities.sh"
    return 0
  fi

  local rel_path=""
  for _ in {1..15}; do
    cd ..
    # If rel_path is empty, set it to '..' else prepend '../'
    if [[ -z "$rel_path" ]]; then
      rel_path=".."
    else
      rel_path="../$rel_path"
    fi

    if [[ -d "./Utilities" ]]; then
      echo "$rel_path/Utilities/Utilities.sh"
      return 0
    fi
  done

  echo "Error: Could not find 'Utilities' folder within 15 levels." >&2
  return 1
}

###############################################################################
# Locate and source the Utilities script
###############################################################################
#UTILITIES_SCRIPT="$(find_utilities_script)" || exit 1
#source "$UTILITIES_SCRIPT"