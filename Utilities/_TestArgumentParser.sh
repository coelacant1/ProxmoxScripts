#!/bin/bash
#
# Function Index:
#   - test_simple_positional
#   - test_func
#   - test_with_flags
#   - test_func
#   - test_optional_with_default
#   - test_func
#   - test_optional_override_default
#   - test_func
#   - test_validation_numeric
#   - test_func
#   - test_validation_ip
#   - test_func
#   - test_validation_ip_invalid
#   - test_func
#   - test_validation_port
#   - test_func
#   - test_validation_port_invalid
#   - test_func
#   - test_validation_cidr
#   - test_func
#   - test_vmid_range
#   - test_func
#   - test_vmid_range_invalid
#   - test_func
#   - test_missing_required
#   - test_func
#   - test_optional_question_mark
#   - test_func
#   - test_multiple_flags
#   - test_func
#   - test_mixed_order
#   - test_func
#

set -euo pipefail

################################################################################
# _TestArgumentParser.sh - Test suite for ArgumentParser.sh
################################################################################
#
# Test suite for ArgumentParser v2 declarative parsing and validation.
#
# Usage: ./_TestArgumentParser.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"

source "${SCRIPT_DIR}/TestFramework.sh"
source "${SCRIPT_DIR}/ArgumentParser.sh"

################################################################################
# TEST: SIMPLE POSITIONAL ARGUMENTS
################################################################################

test_simple_positional() {
    local result
    test_func() {
        parse_args "vmid:number cores:number" "$@" 2>/dev/null
        [[ "$VMID" == "100" && "$CORES" == "4" ]]
    }

    test_func 100 4
    assert_exit_code 0 $? "Should parse simple positional arguments"
}

################################################################################
# TEST: POSITIONAL WITH FLAGS
################################################################################

test_with_flags() {
    test_func() {
        parse_args "start:number end:number --force:flag --node:string" "$@" 2>/dev/null
        [[ "$START" == "100" && "$END" == "110" && "$FORCE" == "true" && "$NODE" == "pve01" ]]
    }

    test_func 100 110 --force --node pve01
    assert_exit_code 0 $? "Should parse positional args with flags"
}

################################################################################
# TEST: OPTIONAL ARGUMENTS WITH DEFAULTS
################################################################################

test_optional_with_default() {
    test_func() {
        parse_args "vmid:number port:number:22" "$@" 2>/dev/null
        [[ "$VMID" == "100" && "$PORT" == "22" ]]
    }

    test_func 100
    assert_exit_code 0 $? "Should apply default value"
}

test_optional_override_default() {
    test_func() {
        parse_args "vmid:number port:number:22" "$@" 2>/dev/null
        [[ "$VMID" == "100" && "$PORT" == "8006" ]]
    }

    test_func 100 8006
    assert_exit_code 0 $? "Should override default value"
}

################################################################################
# TEST: NUMERIC VALIDATION
################################################################################

test_validation_numeric() {
    test_func() {
        parse_args "vmid:number" "$@" 2>/dev/null
    }

    test_func "abc" 2>/dev/null
    assert_exit_code 1 $? "Should reject non-numeric value"
}

################################################################################
# TEST: IP VALIDATION
################################################################################

test_validation_ip() {
    test_func() {
        parse_args "ip:ip" "$@" 2>/dev/null
        [[ "$IP" == "192.168.1.100" ]]
    }

    test_func 192.168.1.100
    assert_exit_code 0 $? "Should accept valid IP"
}

test_validation_ip_invalid() {
    test_func() {
        parse_args "ip:ip" "$@" 2>/dev/null
    }

    test_func 999.999.999.999 2>/dev/null
    assert_exit_code 1 $? "Should reject invalid IP"
}

################################################################################
# TEST: PORT VALIDATION
################################################################################

test_validation_port() {
    test_func() {
        parse_args "port:port" "$@" 2>/dev/null
        [[ "$PORT" == "8006" ]]
    }

    test_func 8006
    assert_exit_code 0 $? "Should accept valid port"
}

test_validation_port_invalid() {
    test_func() {
        parse_args "port:port" "$@" 2>/dev/null
    }

    test_func 99999 2>/dev/null
    assert_exit_code 1 $? "Should reject port > 65535"
}

################################################################################
# TEST: CIDR VALIDATION
################################################################################

test_validation_cidr() {
    test_func() {
        parse_args "network:cidr" "$@" 2>/dev/null
        [[ "$NETWORK" == "192.168.1.0/24" ]]
    }

    test_func 192.168.1.0/24
    assert_exit_code 0 $? "Should accept valid CIDR"
}

################################################################################
# TEST: VMID RANGE VALIDATION
################################################################################

test_vmid_range() {
    test_func() {
        parse_args "start:number end:number" "$@" 2>/dev/null
        [[ "$START" == "100" && "$END" == "110" ]]
    }

    test_func 100 110
    assert_exit_code 0 $? "Should accept valid VMID range"
}

test_vmid_range_invalid() {
    test_func() {
        parse_args "start:number end:number" "$@" 2>/dev/null
    }

    test_func 110 100 2>/dev/null
    assert_exit_code 1 $? "Should reject start > end"
}

################################################################################
# TEST: REQUIRED ARGUMENTS
################################################################################

test_missing_required() {
    test_func() {
        parse_args "vmid:number cores:number" "$@" 2>/dev/null
    }

    test_func 100 2>/dev/null
    assert_exit_code 1 $? "Should reject missing required argument"
}

################################################################################
# TEST: OPTIONAL ARGUMENTS
################################################################################

test_optional_question_mark() {
    test_func() {
        parse_args "vmid:number node:string:?" "$@" 2>/dev/null
        [[ "$VMID" == "100" && -z "$NODE" ]]
    }

    test_func 100
    assert_exit_code 0 $? "Should accept optional with ? notation"
}

################################################################################
# TEST: MULTIPLE FLAGS
################################################################################

test_multiple_flags() {
    test_func() {
        parse_args "vmid:number --force:flag --verbose:flag --dry-run:flag" "$@" 2>/dev/null
        [[ "$VMID" == "100" && "$FORCE" == "true" && "$VERBOSE" == "true" && "$DRY_RUN" == "false" ]]
    }

    test_func 100 --force --verbose
    assert_exit_code 0 $? "Should parse multiple boolean flags"
}

################################################################################
# TEST: MIXED ORDER ARGUMENTS
################################################################################

test_mixed_order() {
    test_func() {
        parse_args "start:number end:number --force:flag --node:string" "$@" 2>/dev/null
        [[ "$START" == "100" && "$END" == "110" && "$FORCE" == "true" && "$NODE" == "pve01" ]]
    }

    test_func 100 --force 110 --node pve01
    assert_exit_code 0 $? "Should parse mixed positional and flags in any order"
}

################################################################################
# RUN TEST SUITE
################################################################################

run_test_suite "ArgumentParser Functions" \
    test_simple_positional \
    test_with_flags \
    test_optional_with_default \
    test_optional_override_default \
    test_validation_numeric \
    test_validation_ip \
    test_validation_ip_invalid \
    test_validation_port \
    test_validation_port_invalid \
    test_validation_cidr \
    test_vmid_range \
    test_vmid_range_invalid \
    test_missing_required \
    test_optional_question_mark \
    test_multiple_flags \
    test_mixed_order

exit $?
