#!/bin/bash
#
# SSH.sh
#
# This script provides repeated-use SSH functions that can be sourced by other
# scripts.
#
# Usage:
#   source SSH.sh
#
# Function Index:
#   - __ssh_log__
#   - __wait_for_ssh__
#   - __ssh_exec__
#   - __scp_send__
#   - __scp_fetch__
#   - __ssh_exec_script__
#   - __ssh_exec_function__
#

# Source Logger for structured logging
if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Logger.sh" ]]; then
    # shellcheck source=Utilities/Logger.sh
    source "${UTILITYPATH}/Logger.sh"
fi

# Safe logging wrapper
__ssh_log__() {
    local level="$1"
    local message="$2"
    if declare -f __log__ >/dev/null 2>&1; then
        __log__ "$level" "$message" "SSH"
    fi
}

source "${UTILITYPATH}/Prompts.sh"

__install_or_prompt__ "sshpass"

###############################################################################
# SSH Functions
###############################################################################

# --- __wait_for_ssh__ ------------------------------------------------------------
# @function __wait_for_ssh__
# @description Repeatedly attempts to connect via SSH to a specified host using a given username and password until SSH is reachable or until the maximum number of attempts is exhausted.
# @usage __wait_for_ssh__ <host> <sshUsername> <sshPassword>
# @param 1 The SSH host (IP or domain).
# @param 2 The SSH username.
# @param 3 The SSH password.
# @return Returns 0 if a connection is established within the max attempts, otherwise exits with code 1.
# @example_output For __wait_for_ssh__ "192.168.1.100" "user" "pass", the output might be:
#   SSH is up on "192.168.1.100"
__wait_for_ssh__() {
    local host="$1"
    local sshUsername="$2"
    local sshPassword="$3"
    local maxAttempts=20
    local delay=3

    __ssh_log__ "INFO" "Waiting for SSH on $host (user: $sshUsername)"

    for attempt in $(seq 1 "$maxAttempts"); do
        __ssh_log__ "DEBUG" "SSH connection attempt $attempt/$maxAttempts to $host"
        if sshpass -p "$sshPassword" ssh -o BatchMode=no -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
            "$sshUsername@$host" exit 2>/dev/null; then
            echo "SSH is up on \"$host\""
            __ssh_log__ "INFO" "SSH connection successful to $host"
            return 0
        fi
        echo "Attempt $attempt/$maxAttempts: SSH not ready on \"$host\"; waiting $delay seconds..."
        sleep "$delay"
    done

    echo "Error: Could not connect to SSH on \"$host\" after $maxAttempts attempts."
    __ssh_log__ "ERROR" "Failed to establish SSH connection to $host after $maxAttempts attempts"
    exit 1
}

###############################################################################
# SSH/SCP Operations (with logging)
###############################################################################

# --- __ssh_exec__ ------------------------------------------------------------
# @function __ssh_exec__
# @description Executes a command on a remote host via SSH, supporting password or key-based authentication and optional sudo or shell invocation.
# @usage __ssh_exec__ --host <host> --user <user> [--password <pass> | --identity <key>] [--port <port>] [--sudo] [--shell <shell>] [--connect-timeout <seconds>] [--extra-ssh-arg <arg>] [--strict-host-key-checking] [--known-hosts-file <path>] --command "<command>"
# @flags
#   --host <host>                 SSH host (IP or domain). Required.
#   --user <user>                 SSH username. Required.
#   --password <password>         SSH password (invokes sshpass).
#   --identity <key>              Path to private key for key-based auth.
#   --port <port>                 SSH port (default 22).
#   --command <command>           Command to execute on the remote host. Required.
#   --sudo                        Prefix the remote command with sudo -H.
#   --shell <shell>               Execute the command via the provided shell as: shell -lc 'command'.
#   --connect-timeout <seconds>   SSH connection timeout (default 10).
#   --extra-ssh-arg <arg>         Additional raw argument to ssh (can be repeated).
#   --strict-host-key-checking    Enforce strict host key checking (disabled by default).
#   --known-hosts-file <path>     Custom known hosts file (implies strict host key checking unless overridden).
#   --                           Treat the remaining arguments as the remote command string.
# @example __ssh_exec__ --host 10.0.0.5 --user root --password secret --command "uname -a"
# @example __ssh_exec__ --host server --user admin --identity ~/.ssh/id_ed25519 --sudo --shell bash --command "apt update"
__ssh_exec__() {
    local host=""
    local user=""
    local password=""
    local identity=""
    local port=""
    local command=""
    local shell=""
    local knownHosts=""
    local connectTimeout="10"
    local useSudo=0
    local useStrict=0
    local commandProvided=0
    local -a extraSshArgs=()

    __ssh_log__ "DEBUG" "SSH exec called"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --host)
                host="$2"
                shift 2
                ;;
            --user)
                user="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            --identity)
                identity="$2"
                shift 2
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --command)
                command="$2"
                commandProvided=1
                shift 2
                ;;
            --shell)
                shell="$2"
                shift 2
                ;;
            --sudo)
                useSudo=1
                shift
                ;;
            --connect-timeout)
                connectTimeout="$2"
                shift 2
                ;;
            --extra-ssh-arg)
                extraSshArgs+=("$2")
                shift 2
                ;;
            --strict-host-key-checking)
                useStrict=1
                shift
                ;;
            --known-hosts-file)
                knownHosts="$2"
                useStrict=1
                shift 2
                ;;
            --)
                shift
                command="$*"
                commandProvided=1
                break
                ;;
            *)
                echo "Error: Unknown option '$1' passed to __ssh_exec__." >&2
                return 1
                ;;
        esac
    done

    if [ -z "$host" ] || [ -z "$user" ]; then
        __ssh_log__ "ERROR" "Missing required parameters: host or user"
        echo "Error: __ssh_exec__ requires --host and --user." >&2
        return 1
    fi

    if [ -z "$command" ] && [ "$commandProvided" -eq 0 ]; then
        __ssh_log__ "ERROR" "Missing command"
        echo "Error: __ssh_exec__ requires --command or -- followed by a command." >&2
        return 1
    fi

    if [ -n "$identity" ] && [ ! -f "$identity" ]; then
        __ssh_log__ "ERROR" "Identity file not found: $identity"
        echo "Error: Identity file '$identity' not found." >&2
        return 1
    fi

    __ssh_log__ "INFO" "Executing SSH command on $user@$host"

    local remoteCommand="$command"
    if [ -n "$shell" ]; then
        local shellWrapped=""
        printf -v shellWrapped '%s -lc %q' "$shell" "$remoteCommand"
        remoteCommand="$shellWrapped"
    fi

    if [ "$useSudo" -eq 1 ]; then
        remoteCommand="sudo -H $remoteCommand"
    fi

    local -a sshCmd=()
    if [ -n "$password" ]; then
        sshCmd+=(sshpass -p "$password")
    fi

    sshCmd+=(ssh)

    if [ -n "$identity" ]; then
        sshCmd+=(-i "$identity")
    fi

    if [ -n "$port" ]; then
        sshCmd+=(-p "$port")
    fi

    sshCmd+=(-o "BatchMode=no" -o "ConnectTimeout=$connectTimeout")

    if [ "$useStrict" -eq 0 ]; then
        sshCmd+=(-o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null")
    else
        if [ -n "$knownHosts" ]; then
            sshCmd+=(-o "UserKnownHostsFile=$knownHosts")
        fi
    fi

    if [ ${#extraSshArgs[@]} -gt 0 ]; then
        sshCmd+=("${extraSshArgs[@]}")
    fi

    sshCmd+=("$user@$host" "$remoteCommand")

    __ssh_log__ "DEBUG" "Executing: ${sshCmd[*]}"
    "${sshCmd[@]}"
    local exit_code=$?
    __ssh_log__ "DEBUG" "SSH command completed with exit code: $exit_code"
    return $exit_code
}

# --- __scp_send__ ------------------------------------------------------------
# @function __scp_send__
# @description Copies one or more local files/directories to a remote destination via SCP.
# @usage __scp_send__ --host <host> --user <user> [--password <pass> | --identity <key>] [--port <port>] [--recursive] [--connect-timeout <seconds>] [--extra-scp-arg <arg>] --source <path> [--source <path> ...] --destination <remotePath>
# @flags
#   --source <path>               Local file or directory to transfer (can be repeated).
#   --destination <remotePath>    Remote destination path. Required.
#   --recursive                   Transfer directories recursively.
#   --extra-scp-arg <arg>         Additional raw argument to scp (can be repeated).
#   Other connection-related flags mirror __ssh_exec__.
__scp_send__() {
    local host=""
    local user=""
    local password=""
    local identity=""
    local port=""
    local knownHosts=""
    local connectTimeout="10"
    local useStrict=0
    local recursive=0
    local -a sources=()
    local destination=""
    local -a extraScpArgs=()

    __ssh_log__ "DEBUG" "SCP send called"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --host)
                host="$2"
                shift 2
                ;;
            --user)
                user="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            --identity)
                identity="$2"
                shift 2
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --destination)
                destination="$2"
                shift 2
                ;;
            --source)
                sources+=("$2")
                shift 2
                ;;
            --recursive)
                recursive=1
                shift
                ;;
            --connect-timeout)
                connectTimeout="$2"
                shift 2
                ;;
            --extra-scp-arg)
                extraScpArgs+=("$2")
                shift 2
                ;;
            --strict-host-key-checking)
                useStrict=1
                shift
                ;;
            --known-hosts-file)
                knownHosts="$2"
                useStrict=1
                shift 2
                ;;
            --)
                shift
                ;;
            *)
                echo "Error: Unknown option '$1' passed to __scp_send__." >&2
                return 1
                ;;
        esac
    done

    if [ -z "$host" ] || [ -z "$user" ]; then
        __ssh_log__ "ERROR" "Missing required parameters: host or user"
        echo "Error: __scp_send__ requires --host and --user." >&2
        return 1
    fi

    if [ -z "$destination" ]; then
        __ssh_log__ "ERROR" "Missing destination"
        echo "Error: __scp_send__ requires --destination." >&2
        return 1
    fi

    if [ ${#sources[@]} -eq 0 ]; then
        __ssh_log__ "ERROR" "No source files specified"
        echo "Error: __scp_send__ requires at least one --source." >&2
        return 1
    fi

    if [ -n "$identity" ] && [ ! -f "$identity" ]; then
        __ssh_log__ "ERROR" "Identity file not found: $identity"
        echo "Error: Identity file '$identity' not found." >&2
        return 1
    fi

    __ssh_log__ "INFO" "Sending ${#sources[@]} file(s) to $user@$host:$destination"

    local -a scpCmd=()
    if [ -n "$password" ]; then
        scpCmd+=(sshpass -p "$password")
    fi

    scpCmd+=(scp -q)

    if [ "$recursive" -eq 1 ]; then
        scpCmd+=(-r)
    fi

    if [ -n "$identity" ]; then
        scpCmd+=(-i "$identity")
    fi

    if [ -n "$port" ]; then
        scpCmd+=(-P "$port")
    fi

    scpCmd+=(-o "ConnectTimeout=$connectTimeout")

    if [ "$useStrict" -eq 0 ]; then
        scpCmd+=(-o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null")
    else
        if [ -n "$knownHosts" ]; then
            scpCmd+=(-o "UserKnownHostsFile=$knownHosts")
        fi
    fi

    if [ ${#extraScpArgs[@]} -gt 0 ]; then
        scpCmd+=("${extraScpArgs[@]}")
    fi

    scpCmd+=("${sources[@]}" "$user@$host:$destination")

    __ssh_log__ "DEBUG" "Executing SCP send: ${scpCmd[*]}"
    "${scpCmd[@]}"
    local exit_code=$?
    __ssh_log__ "DEBUG" "SCP send completed with exit code: $exit_code"
    return $exit_code
}

# --- __scp_fetch__ -----------------------------------------------------------
# @function __scp_fetch__
# @description Copies files/directories from the remote host to the local machine via SCP.
# @usage __scp_fetch__ --host <host> --user <user> [--password <pass> | --identity <key>] [--port <port>] [--recursive] [--connect-timeout <seconds>] --source <remotePath> [--source <remotePath> ...] --destination <localPath>
__scp_fetch__() {
    local host=""
    local user=""
    local password=""
    local identity=""
    local port=""
    local knownHosts=""
    local connectTimeout="10"
    local useStrict=0
    local recursive=0
    local -a sources=()
    local destination=""
    local -a extraScpArgs=()

    __ssh_log__ "DEBUG" "SCP fetch called"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --host)
                host="$2"
                shift 2
                ;;
            --user)
                user="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            --identity)
                identity="$2"
                shift 2
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --destination)
                destination="$2"
                shift 2
                ;;
            --source)
                sources+=("$2")
                shift 2
                ;;
            --recursive)
                recursive=1
                shift
                ;;
            --connect-timeout)
                connectTimeout="$2"
                shift 2
                ;;
            --extra-scp-arg)
                extraScpArgs+=("$2")
                shift 2
                ;;
            --strict-host-key-checking)
                useStrict=1
                shift
                ;;
            --known-hosts-file)
                knownHosts="$2"
                useStrict=1
                shift 2
                ;;
            --)
                shift
                ;;
            *)
                echo "Error: Unknown option '$1' passed to __scp_fetch__." >&2
                return 1
                ;;
        esac
    done

    if [ -z "$host" ] || [ -z "$user" ]; then
        __ssh_log__ "ERROR" "Missing required parameters: host or user"
        echo "Error: __scp_fetch__ requires --host and --user." >&2
        return 1
    fi

    if [ -z "$destination" ]; then
        __ssh_log__ "ERROR" "Missing destination"
        echo "Error: __scp_fetch__ requires --destination." >&2
        return 1
    fi

    if [ ${#sources[@]} -eq 0 ]; then
        __ssh_log__ "ERROR" "No source files specified"
        echo "Error: __scp_fetch__ requires at least one --source." >&2
        return 1
    fi

    if [ -n "$identity" ] && [ ! -f "$identity" ]; then
        __ssh_log__ "ERROR" "Identity file not found: $identity"
        echo "Error: Identity file '$identity' not found." >&2
        return 1
    fi

    __ssh_log__ "INFO" "Fetching ${#sources[@]} file(s) from $user@$host to $destination"

    local -a scpCmd=()
    if [ -n "$password" ]; then
        scpCmd+=(sshpass -p "$password")
    fi

    scpCmd+=(scp -q)

    if [ "$recursive" -eq 1 ]; then
        scpCmd+=(-r)
    fi

    if [ -n "$identity" ]; then
        scpCmd+=(-i "$identity")
    fi

    if [ -n "$port" ]; then
        scpCmd+=(-P "$port")
    fi

    scpCmd+=(-o "ConnectTimeout=$connectTimeout")

    if [ "$useStrict" -eq 0 ]; then
        scpCmd+=(-o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null")
    else
        if [ -n "$knownHosts" ]; then
            scpCmd+=(-o "UserKnownHostsFile=$knownHosts")
        fi
    fi

    if [ ${#extraScpArgs[@]} -gt 0 ]; then
        scpCmd+=("${extraScpArgs[@]}")
    fi

    local -a remoteSources=()
    local remotePath
    for remotePath in "${sources[@]}"; do
        remoteSources+=("$user@$host:$remotePath")
    done

    scpCmd+=("${remoteSources[@]}" "$destination")

    __ssh_log__ "DEBUG" "Executing SCP fetch: ${scpCmd[*]}"
    "${scpCmd[@]}"
    local exit_code=$?
    __ssh_log__ "DEBUG" "SCP fetch completed with exit code: $exit_code"
    return $exit_code
}

# --- __ssh_exec_script__ -----------------------------------------------------
# @function __ssh_exec_script__
# @description Transfers a local script (or inline content) to the remote host, sets executable permissions, runs it, and optionally removes it afterward.
# @usage __ssh_exec_script__ --host <host> --user <user> [--password <pass> | --identity <key>] --script-path <path> [--remote-path <path>] [--arg <value> ...] [--sudo] [--keep-remote]
__ssh_exec_script__() {
    local host=""
    local user=""
    local password=""
    local identity=""
    local port=""
    local scriptPath=""
    local scriptContent=""
    local remotePath=""
    local connectTimeout="10"
    local useSudo=0
    local keepRemote=0
    local useStrict=0
    local knownHosts=""
    local -a scriptArgs=()
    local -a extraSshArgs=()

    __ssh_log__ "DEBUG" "SSH exec script called"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --host)
                host="$2"
                shift 2
                ;;
            --user)
                user="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            --identity)
                identity="$2"
                shift 2
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --script-path)
                scriptPath="$2"
                shift 2
                ;;
            --script-content)
                scriptContent="$2"
                shift 2
                ;;
            --remote-path)
                remotePath="$2"
                shift 2
                ;;
            --arg)
                scriptArgs+=("$2")
                shift 2
                ;;
            --sudo)
                useSudo=1
                shift
                ;;
            --keep-remote)
                keepRemote=1
                shift
                ;;
            --connect-timeout)
                connectTimeout="$2"
                shift 2
                ;;
            --extra-ssh-arg)
                extraSshArgs+=("$2")
                shift 2
                ;;
            --strict-host-key-checking)
                useStrict=1
                shift
                ;;
            --known-hosts-file)
                knownHosts="$2"
                useStrict=1
                shift 2
                ;;
            --)
                shift
                ;;
            *)
                echo "Error: Unknown option '$1' passed to __ssh_exec_script__." >&2
                return 1
                ;;
        esac
    done

    if [ -z "$host" ] || [ -z "$user" ]; then
        __ssh_log__ "ERROR" "Missing required parameters: host or user"
        echo "Error: __ssh_exec_script__ requires --host and --user." >&2
        return 1
    fi

    if [ -z "$scriptPath" ] && [ -z "$scriptContent" ]; then
        __ssh_log__ "ERROR" "No script specified"
        echo "Error: __ssh_exec_script__ requires --script-path or --script-content." >&2
        return 1
    fi

    if [ -n "$identity" ] && [ ! -f "$identity" ]; then
        __ssh_log__ "ERROR" "Identity file not found: $identity"
        echo "Error: Identity file '$identity' not found." >&2
        return 1
    fi

    __ssh_log__ "INFO" "Executing script on $user@$host"

    local tempFile=""
    local cleanupNeeded=0
    if [ -n "$scriptContent" ]; then
        tempFile="$(mktemp)"
        printf '%s\n' "$scriptContent" >"$tempFile"
        chmod +x "$tempFile"
        scriptPath="$tempFile"
        cleanupNeeded=1
    fi

    if [ ! -f "$scriptPath" ]; then
        echo "Error: Script path '$scriptPath' not found." >&2
        if [ "$cleanupNeeded" -eq 1 ]; then
            rm -f "$tempFile"
        fi
        return 1
    fi

    if [ -z "$remotePath" ]; then
        local baseName
        baseName="$(basename "$scriptPath")"
        remotePath="/tmp/${baseName}.$(date +%s).$$"
    fi

    local -a connectionFlags=(--host "$host" --user "$user" --connect-timeout "$connectTimeout")
    if [ -n "$password" ]; then
        connectionFlags+=(--password "$password")
    fi
    if [ -n "$identity" ]; then
        connectionFlags+=(--identity "$identity")
    fi
    if [ -n "$port" ]; then
        connectionFlags+=(--port "$port")
    fi
    if [ "$useStrict" -eq 1 ]; then
        connectionFlags+=(--strict-host-key-checking)
    fi
    if [ -n "$knownHosts" ]; then
        connectionFlags+=(--known-hosts-file "$knownHosts")
    fi
    if [ ${#extraSshArgs[@]} -gt 0 ]; then
        local arg
        for arg in "${extraSshArgs[@]}"; do
            connectionFlags+=(--extra-ssh-arg "$arg")
        done
    fi

    __scp_send__ "${connectionFlags[@]}" --source "$scriptPath" --destination "$remotePath"

    local chmodCommand=""
    printf -v chmodCommand 'chmod +x %q' "$remotePath"
    __ssh_exec__ "${connectionFlags[@]}" --command "$chmodCommand"

    local -a remoteParts=("$remotePath")
    if [ ${#scriptArgs[@]} -gt 0 ]; then
        remoteParts+=("${scriptArgs[@]}")
    fi

    local remoteRunCommand=""
    printf -v remoteRunCommand '%q ' "${remoteParts[@]}"
    remoteRunCommand="${remoteRunCommand%% }"

    if [ "$useSudo" -eq 1 ]; then
        __ssh_exec__ "${connectionFlags[@]}" --sudo --command "$remoteRunCommand"
    else
        __ssh_exec__ "${connectionFlags[@]}" --command "$remoteRunCommand"
    fi

    if [ "$keepRemote" -eq 0 ]; then
        local cleanupCommand=""
        printf -v cleanupCommand 'rm -f %q' "$remotePath"
        __ssh_exec__ "${connectionFlags[@]}" --command "$cleanupCommand"
    fi

    if [ "$cleanupNeeded" -eq 1 ] && [ -n "$tempFile" ]; then
        rm -f "$tempFile"
    fi

    __ssh_log__ "DEBUG" "Script execution completed"
}

# --- __ssh_exec_function__ --------------------------------------------------
# @function __ssh_exec_function__
# @description Ships one or more local Bash function definitions to the remote host and invokes a selected function with optional arguments.
# @usage __ssh_exec_function__ --host <host> --user <user> [--password <pass> | --identity <key>] --function <name> [--function <name> ...] [--call <name>] [--arg <value> ...] [--sudo]
# @flags
#   --function <name>         Local function name to include (required, can be repeated).
#   --call <name>             Function to execute on the remote end (defaults to the last --function provided).
#   --arg <value>             Argument to forward to the remote function (can be repeated).
#   --remote-path <path>      Remote script path (default auto-generated under /tmp).
#   --keep-remote             Keep the uploaded script after execution.
#   Other connection-related flags mirror __ssh_exec__.
# @example __ssh_exec_function__ --host node --user root --password secret --function configure_node --call configure_node --arg 10.0.0.5
__ssh_exec_function__() {
    local host=""
    local user=""
    local password=""
    local identity=""
    local port=""
    local connectTimeout="10"
    local useStrict=0
    local knownHosts=""
    local useSudo=0
    local keepRemote=0
    local remotePath=""
    local -a extraSshArgs=()
    local -a functionNames=()
    local callName=""
    local -a callArgs=()
    local -A seenFunctions=()

    __ssh_log__ "DEBUG" "SSH exec function called"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --host)
                host="$2"
                shift 2
                ;;
            --user)
                user="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            --identity)
                identity="$2"
                shift 2
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --connect-timeout)
                connectTimeout="$2"
                shift 2
                ;;
            --strict-host-key-checking)
                useStrict=1
                shift
                ;;
            --known-hosts-file)
                knownHosts="$2"
                useStrict=1
                shift 2
                ;;
            --extra-ssh-arg)
                extraSshArgs+=("$2")
                shift 2
                ;;
            --sudo)
                useSudo=1
                shift
                ;;
            --remote-path)
                remotePath="$2"
                shift 2
                ;;
            --keep-remote)
                keepRemote=1
                shift
                ;;
            --function)
                functionNames+=("$2")
                shift 2
                ;;
            --call)
                callName="$2"
                shift 2
                ;;
            --arg)
                callArgs+=("$2")
                shift 2
                ;;
            --)
                shift
                callArgs+=("$@")
                break
                ;;
            *)
                echo "Error: Unknown option '$1' passed to __ssh_exec_function__." >&2
                return 1
                ;;
        esac
    done

    if [ -z "$host" ] || [ -z "$user" ]; then
        __ssh_log__ "ERROR" "Missing required parameters: host or user"
        echo "Error: __ssh_exec_function__ requires --host and --user." >&2
        return 1
    fi

    if [ ${#functionNames[@]} -eq 0 ]; then
        __ssh_log__ "ERROR" "No functions specified"
        echo "Error: __ssh_exec_function__ requires at least one --function." >&2
        return 1
    fi

    if [ -z "$callName" ]; then
        local lastIndex=$((${#functionNames[@]} - 1))
        callName="${functionNames[$lastIndex]}"
    fi

    __ssh_log__ "INFO" "Executing function $callName on $user@$host with ${#functionNames[@]} function(s)"

    local -a functionDefs=()
    local fname
    for fname in "${functionNames[@]}"; do
        if [[ -n "${seenFunctions[$fname]:-}" ]]; then
            continue
        fi
        if ! declare -f "$fname" >/dev/null 2>&1; then
            echo "Error: Function '$fname' is not defined in the current shell." >&2
            return 1
        fi
        functionDefs+=("$(declare -f "$fname")")
        seenFunctions[$fname]=1
    done

    if ! declare -f "$callName" >/dev/null 2>&1; then
        echo "Error: Call target '$callName' is not defined." >&2
        return 1
    fi

    if [[ -z "${seenFunctions[$callName]:-}" ]]; then
        functionDefs+=("$(declare -f "$callName")")
        seenFunctions[$callName]=1
    fi

    local scriptFile
    scriptFile="$(mktemp)"

    {
        echo "#!/bin/bash"
        echo "set -euo pipefail"
        echo
        for def in "${functionDefs[@]}"; do
            printf '%s\n\n' "$def"
        done
        printf '%s\n' "$callName \"\$@\""
    } >"$scriptFile"

    local -a connectionFlags=(--host "$host" --user "$user" --connect-timeout "$connectTimeout")
    if [ -n "$password" ]; then
        connectionFlags+=(--password "$password")
    fi
    if [ -n "$identity" ]; then
        if [ ! -f "$identity" ]; then
            echo "Error: Identity file '$identity' not found." >&2
            rm -f "$scriptFile"
            return 1
        fi
        connectionFlags+=(--identity "$identity")
    fi
    if [ -n "$port" ]; then
        connectionFlags+=(--port "$port")
    fi
    if [ "$useStrict" -eq 1 ]; then
        connectionFlags+=(--strict-host-key-checking)
    fi
    if [ -n "$knownHosts" ]; then
        connectionFlags+=(--known-hosts-file "$knownHosts")
    fi
    if [ ${#extraSshArgs[@]} -gt 0 ]; then
        local arg
        for arg in "${extraSshArgs[@]}"; do
            connectionFlags+=(--extra-ssh-arg "$arg")
        done
    fi

    local -a scriptArgs=("${connectionFlags[@]}" --script-path "$scriptFile")
    if [ -n "$remotePath" ]; then
        scriptArgs+=(--remote-path "$remotePath")
    fi
    if [ "$keepRemote" -eq 1 ]; then
        scriptArgs+=(--keep-remote)
    fi
    if [ "$useSudo" -eq 1 ]; then
        scriptArgs+=(--sudo)
    fi

    local argValue
    for argValue in "${callArgs[@]}"; do
        scriptArgs+=(--arg "$argValue")
    done

    local rc
    __ssh_exec_script__ "${scriptArgs[@]}"
    rc=$?

    rm -f "$scriptFile"
    __ssh_log__ "DEBUG" "Function execution completed with exit code: $rc"
    return "$rc"
}

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Validated against CONTRIBUTING.md and PVE docs
# - 2025-11-24: Removed duplicate variable declarations in __scp_send__ and __scp_fetch__
# - 2025-11-24: Added missing BatchMode=no to __wait_for_ssh__ SSH command
#
# Fixes:
# - 2025-11-24: Fixed duplicate local variable declarations (lines 280-290, 440-449)
# - 2025-11-24: Fixed missing -o BatchMode=no in __wait_for_ssh__ (line 65)
#
# Known issues:
# -
#

