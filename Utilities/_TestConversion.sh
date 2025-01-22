#!/bin/bash
#
# _TestConversion.sh
#
# Usage:
# ./_TestConversion.sh
#
# A simple test script that sources "Conversion.sh" and tests its functions.
#
# Function Index:
#   - test_ip_to_int
#   - test_int_to_ip
#

if [ -z "${UTILITYPATH}" ]; then
  # UTILITYPATH is unset or empty
  export UTILITYPATH="$(pwd)"
fi

# Source the library
source "${UTILITYPATH}/Conversion.sh"

###############################################################################
# Helper Functions
###############################################################################

# Test if __ip_to_int__ outputs the expected integer
test_ip_to_int() {
  local ip="$1"
  local expected="$2"

  local result
  result="$(__ip_to_int__ "$ip")"

  if [[ "$result" == "$expected" ]]; then
    echo "[PASS] __ip_to_int__ \"$ip\" => $result"
  else
    echo "[FAIL] __ip_to_int__ \"$ip\" => $result (expected $expected)"
  fi
}

# Test if __int_to_ip__ outputs the expected dotted-IP string
test_int_to_ip() {
  local integer="$1"
  local expected="$2"

  local result
  result="$(__int_to_ip__ "$integer")"

  if [[ "$result" == "$expected" ]]; then
    echo "[PASS] __int_to_ip__ $integer => $result"
  else
    echo "[FAIL] __int_to_ip__ $integer => $result (expected $expected)"
  fi
}

###############################################################################
# Test Cases
###############################################################################

# IP to Int tests
test_ip_to_int "127.0.0.1" "2130706433"
test_ip_to_int "192.168.1.10" "3232235786"
test_ip_to_int "10.0.0.255" "167772415"

# Int to IP tests
test_int_to_ip "2130706433" "127.0.0.1"
test_int_to_ip "3232235786" "192.168.1.10"
test_int_to_ip "167772415"  "10.0.0.255"

echo
echo "All tests completed."
