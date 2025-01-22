#!/bin/bash
#
# _TestCommunication.sh
#
# Usage:
# ./_TestCommunication.sh
#
# Demonstrates usage of the Communication.sh script:
#   - Sourcing the script
#   - Starting/stopping the spinner
#   - Printing info, success, and error messages
#   - Handling errors via a trap
#
# Function Index:
#   - simulate_task
#   - simulate_error
#

if [ -z "${UTILITYPATH}" ]; then
  # UTILITYPATH is unset or empty
  export UTILITYPATH="$(pwd)"
fi

source "${UTILITYPATH}/Communication.sh"

# Example function that simulates a task
simulate_task() {
  # "Info" starts the spinner in the background
  __info__ "Simulating a long-running task..."
  
  # Sleep for 2 seconds to mimic a longer process
  sleep 2
  
  # Update the text while the spinner is still going
  __update__ "Halfway done..."
  sleep 2
  
  # Indicate success
  __ok__ "Task completed successfully."
}

# Example function that simulates an error
simulate_error() {
  __info__ "Starting a failing command..."
  sleep 1
  
  # We'll run a command that doesn't exist to force an error
  non_existent_command
  
  # If the script reaches here, the spinner won't have stopped yet,
  # but the error trap will trigger first, printing an error.
}

###############################################################################
# MAIN SCRIPT
###############################################################################
echo "=== Communication.sh Demo ==="

# By default, Communication.sh sets a trap for errors:
# trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR
# which prints the line, exit code, and command that failed.

# 1) Demonstrate a successful task
simulate_task

echo
sleep 1
echo "Now we will demonstrate an intentional error."
sleep 1

# 2) Demonstrate an error scenario
simulate_error

# (Script ends here, but the ERR trap in Communication.sh will fire on the failing command.)
echo "This line won't be reached if 'set -e' is in effect (because of the error)."
