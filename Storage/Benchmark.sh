#!/bin/bash
#
# Benchmark.sh
#
# A script to measure disk performance across local, ZFS, or Ceph storage using 'fio'.
# This script installs fio if it's missing, optionally keeps or removes it afterward,
# runs a series of read/write benchmarks, displays key results, and can export them to CSV.
#
# Usage:
#   Benchmark.sh <test-directory>
#
# Example:
#   Benchmark.sh /tmp/fio_test
#
# Notes:
#   - Requires root (for package installation and accurate results).
#   - Designed for Proxmox 8 environments.
#   - May install and remove packages on your system.
#
# Function Index:
#   - runFioTest
#   - parseFioOutput
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "test_directory:path" "$@"

###############################################################################
# Environment and Privilege Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Global Variables
###############################################################################
JQ_AVAILABLE=true
FIO_INSTALLED=false
TEST_DIR="$TEST_DIRECTORY"
READ_JSON=""
WRITE_JSON=""

###############################################################################
# Prepare Environment
###############################################################################

__install_or_prompt__ "jq"
__install_or_prompt__ "fio"

mkdir -p "$TEST_DIR"

READ_JSON="${TEST_DIR}/fio_read_results.json"
WRITE_JSON="${TEST_DIR}/fio_write_results.json"

###############################################################################
# FIO Benchmark Function
###############################################################################
runFioTest() {
  local jobName="$1"
  local rwMode="$2"
  local resultFile="$3"

  fio --directory="$TEST_DIR" \
      --name="$jobName" \
      --rw="$rwMode" \
      --direct=1 \
      --bs=4k \
      --iodepth=32 \
      --numjobs=1 \
      --time_based \
      --runtime=10 \
      --group_reporting=1 \
      --output-format=json \
      --output="$resultFile" &>/dev/null
}

###############################################################################
# Execute Benchmarks
###############################################################################
echo "Running disk benchmarks in: \"$TEST_DIR\""

echo "1/2) Running random read test..."
runFioTest "randread_test" "randread" "$READ_JSON"
echo "   [Done]"

echo "2/2) Running random write test..."
runFioTest "randwrite_test" "randwrite" "$WRITE_JSON"
echo "   [Done]"

###############################################################################
# Parse and Display Key Results
###############################################################################
parseFioOutput() {
  local resultFile="$1"
  local mode="$2"

  if $JQ_AVAILABLE; then
    local iops
    local bw
    local lat50
    local lat99
    iops=$(jq -r '.jobs[0].read.iops + .jobs[0].write.iops' "$resultFile")
    bw=$(jq -r '((.jobs[0].read.bw_bytes + .jobs[0].write.bw_bytes)/1048576) | floor' "$resultFile")
    lat50=$(jq -r '.jobs[0].clat.percentile."50.000000"' "$resultFile")
    lat99=$(jq -r '.jobs[0].clat.percentile."99.000000"' "$resultFile")

    echo " - $mode:"
    echo "     IOPS: \"$iops\""
    echo "     BW:   \"${bw}\" MB/s"
    echo "     Latency (p50): \"${lat50}\"us"
    echo "     Latency (p99): \"${lat99}\"us"
  else
    echo " - $mode: (Install 'jq' for detailed parsing)"
    grep -Eo '"iops":[0-9]+|"bw_bytes":[0-9]+' "$resultFile" | head -n 4
  fi
}

echo
echo "Benchmark Summary (key metrics):"
parseFioOutput "$READ_JSON" "Random Read"
parseFioOutput "$WRITE_JSON" "Random Write"

###############################################################################
# Optional Extended Results
###############################################################################
read -r -p "Would you like to view extended info? (y/N): " SHOW_EXTENDED
if [[ "$SHOW_EXTENDED" =~ ^[Yy]$ ]]; then
  echo "Extended results for Random Read (JSON):"
  cat "$READ_JSON"
  echo
  echo "Extended results for Random Write (JSON):"
  cat "$WRITE_JSON"
fi

###############################################################################
# Optional CSV Export
###############################################################################
read -r -p "Would you like to save results to CSV? (y/N): " SAVE_CSV
if [[ "$SAVE_CSV" =~ ^[Yy]$ ]]; then
  CSV_PATH="${TEST_DIR}/fio_results.csv"
  echo "job_name,iops,bw_mb_s,lat50_us,lat99_us" > "$CSV_PATH"

  for jsonFile in "$READ_JSON" "$WRITE_JSON"; do
    if $JQ_AVAILABLE; then
      declare jobName
      declare iops
      declare bw
      declare lat50
      declare lat99
      jobName=$(jq -r '.jobs[0].jobname' "$jsonFile")
      iops=$(jq -r '.jobs[0].read.iops + .jobs[0].write.iops' "$jsonFile")
      bw=$(jq -r '((.jobs[0].read.bw_bytes + .jobs[0].write.bw_bytes)/1048576) | floor' "$jsonFile")
      lat50=$(jq -r '.jobs[0].clat.percentile."50.000000"' "$jsonFile")
      lat99=$(jq -r '.jobs[0].clat.percentile."99.000000"' "$jsonFile")
      echo "${jobName},${iops},${bw},${lat50},${lat99}" >> "$CSV_PATH"
    else
      echo "Warning: 'jq' not installed, cannot export extended metrics to CSV."
    fi
  done

  echo "CSV results saved to: \"$CSV_PATH\""
fi

###############################################################################
# Clean Up and Prompt to Keep Installed Packages
###############################################################################
__prompt_keep_installed_packages__

echo
echo "Disk benchmark process complete."
