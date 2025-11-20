#!/bin/bash
#
# Function Index:
#   - pvecm
#   - pvesh
#   - test_check_cluster_membership
#   - test_get_number_of_nodes
#   - test_init_node_mappings
#   - test_get_cluster_cts
#   - test_get_server_vms
#

set -euo pipefail

################################################################################
# _TestCluster.sh - Test suite for Cluster.sh
################################################################################
#
# Test suite for Cluster.sh cluster and VM/CT query functions.
#
# Usage: ./_TestCluster.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"

source "${SCRIPT_DIR}/TestFramework.sh"

###############################################################################
# MOCK FUNCTIONS
###############################################################################

pvecm() {
    case "$1" in
        status)
            echo "Cluster status"
            return 0
            ;;
        nodes)
            echo "node1"
            echo "node2"
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

pvesh() {
    echo '{"data":[{"vmid":100},{"vmid":200}]}'
    return 0
}

export -f pvecm
export -f pvesh

source "${SCRIPT_DIR}/Cluster.sh"

################################################################################
# TEST: QUERIES FUNCTIONS
################################################################################

test_check_cluster_membership() {
    __check_cluster_membership__ 2>/dev/null
    assert_exit_code 0 $? "Should check cluster"
}

test_get_number_of_nodes() {
    local count
    count=$(__get_number_of_cluster_nodes__ 2>/dev/null)
    assert_exit_code 0 $? "Should get node count"
}

test_init_node_mappings() {
    __init_node_mappings__ 2>/dev/null
    assert_exit_code 0 $? "Should init mappings"
}

test_get_cluster_cts() {
    local cts
    cts=$(__get_cluster_cts__ 2>/dev/null)
    assert_exit_code 0 $? "Should get cluster containers"
}

test_get_server_vms() {
    local vms
    vms=$(__get_server_vms__ "local" 2>/dev/null)
    assert_exit_code 0 $? "Should get server VMs"
}

################################################################################
# RUN TEST SUITE
################################################################################

test_framework_init

run_test_suite "Queries Functions" \
    test_check_cluster_membership \
    test_get_number_of_nodes \
    test_init_node_mappings \
    test_get_cluster_lxc \
    test_get_server_vms

exit $?

###############################################################################
# Script notes:
###############################################################################
# Last checked: YYYY-MM-DD
#
# Changes:
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

