#!/bin/bash
#
# Function Index:
#   - pvecm
#   - pvesh
#   - test_check_cluster_membership
#   - test_get_number_of_nodes
#   - test_init_node_mappings
#   - test_get_cluster_lxc
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

test_get_cluster_lxc() {
    local lxcs
    lxcs=$(__get_cluster_lxc__ 2>/dev/null)
    assert_exit_code 0 $? "Should get LXC containers"
}

test_get_server_vms() {
    local vms
    vms=$(__get_server_vms__ "local" 2>/dev/null)
    assert_exit_code 0 $? "Should get server VMs"
}

################################################################################
# RUN TEST SUITE
################################################################################

run_test_suite "Queries Functions" \
    test_check_cluster_membership \
    test_get_number_of_nodes \
    test_init_node_mappings \
    test_get_cluster_lxc \
    test_get_server_vms

exit $?
