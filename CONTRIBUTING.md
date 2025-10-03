# Contributing Guide

Thank you for your interest in contributing to this repository! We appreciate your help in improving and expanding our bash scripts for Proxmox management and automation. Below are the guidelines and best practices we ask all contributors to follow.

---

## 1. Project Scope

This repository contains Bash scripts (`.sh` files) that help automate and manage Proxmox tasks. The goal is to maintain a clean, consistent, and secure set of scripts that are easy to understand and extend.

---

## 2. Getting Started

1. **Fork and Clone**  
   - Fork the repository to your own GitHub account.  
   - Clone your fork locally.

2. **Make Your Changes**
   - Follow the coding guidelines below.
   - Test your changes thoroughly in a development/test environment.

3. **Submit a Pull Request**
   - Open a pull request (PR) against the repository’s `main` branch.
   - Provide a clear title and description, referencing any related issues.

---

## 3. Shell Script Style Guide

> This section consolidates the repository’s scripting conventions (formerly in `Utilities/ScriptStyleGuide.md`) so everything you need lives in one place.

### 3.1 Core Principles

- Keep scripts simple, idempotent, and safe for Proxmox nodes.
- Prefer readable, well-documented code over clever one-liners.
- Reuse shared helpers under `Utilities/` instead of copying logic.

### 3.2 Where to Place Files

- Utilities and shared helpers: `Utilities/`
- Feature scripts: domain folders (e.g., `Host/`, `Cluster/`, `Storage/`)
- Use descriptive MixedCase filenames such as `CreateCluster.sh`.

### 3.3 Shebang and Strictness

- Start every script with `#!/bin/bash`.
- Avoid enabling `set -e` globally; prefer explicit error handling, `set -e` within narrow scopes, or traps for critical sections.
- When you need strict error handling, install an `ERR` trap to provide context on failure (see section 3.9).

### 3.4 Required Header

All scripts must begin with a comment block that covers:

- File name and short description
- Usage example(s) starting with `./`
- Relevant notes (root requirement, Proxmox requirement, etc.)
- A “Function Index” placeholder (see next section)

Example header:

```bash
#!/bin/bash
#
# MyScript.sh
#
# Short description of what the script does.
#
# Usage:
#   ./MyScript.sh <arg1> [--flag]
#
# Function Index:
#   - check_something
#   - do_work
#
```

### 3.5 Function Index

- Keep the header line exactly `# Function Index:` followed by individual `#   - function_name` lines.
- The helper at `.check/UpdateFunctionIndex.py` rewrites this section automatically by scanning for `name() {` or `function name()` definitions. Leave the list contiguous with the rest of the header comment.

### 3.6 Common Script Structure

1. Source needed utilities (e.g., `source "${UTILITYPATH}/Prompts.sh"`). When launched via `GUI.sh`, `${UTILITYPATH}` is already exported.
2. Perform prerequisite checks (`__check_root__`, `__check_proxmox__`, dependency checks with `command -v`).
3. Parse arguments and validate input. Print usage and exit on bad input.
4. Group functions logically with clear separators such as `# --- Preliminary Checks -----------------------------------------------------`.
5. Implement main logic inside a `main()` function and call it at the end of the script.
6. Record testing notes near the bottom of the file.

### 3.7 Coding Conventions

- Use consistent indentation (stick to the file’s existing spacing).
- Prefer `local var` inside functions.
- Quote all variable expansions (`"${var}"`) unless you intentionally rely on word splitting.
- Use `[[ ... ]]` for conditionals and `(( ... ))` for arithmetic.
- Choose descriptive variable names; reserve UPPERCASE for environment-level knobs and use lower/mixed case for locals.
- Avoid code duplication - factor shared logic into utilities.

### 3.8 Logging and User Feedback

- Source `Utilities/Communication.sh` to access helpers such as `__info__`, `__update__`, `__ok__`, and `__err__` for consistent messaging.
- `Utilities/Colors.sh` provides ANSI color helpers if you need custom formatting beyond the communication helpers.

### 3.9 Error Handling and Cleanup

- Install an error trap when using `Communication.sh`:
   ```bash
   trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR
   ```
- Use `trap cleanup EXIT` to ensure temporary files or background processes are removed.
- Provide specific error messages before exiting so users know what to fix.
- Check for required commands with `command -v` and exit with meaningful codes.

### 3.10 Argument Parsing

- Keep parsing straightforward. Use `getopts` when handling many flags; otherwise a simple `while`/`case` loop is fine.
- Always validate user input and print the usage block if the arguments are incorrect.

### 3.11 Testing Notes

- Add a `# Testing status` comment near the end of the script describing how you validated it (environments, scenarios, known limitations).
- Run [ShellCheck](https://www.shellcheck.net/) or equivalent linters and address warnings where practical.

### 3.12 Reusable Templates and Utilities

- Review `Utilities/_ExampleScript.sh` for a fully fleshed-out reference implementation that demonstrates every convention in practice.
- Key helper libraries under `Utilities/`:
   - `Colors.sh` – colorized output and styling helpers.
   - `Communication.sh` – messaging helpers and the standard error trap.
   - `Conversion.sh` – data conversion helpers (IP ↔ int, formatting, `__vmid_to_mac_prefix__`, etc.).
   - `Prompts.sh` – user prompts, dependency helpers (`__install_or_prompt__`, `__ensure_dependencies__`), and environment checks (`__check_root__`, `__check_proxmox__`, `__require_root_and_proxmox__`).
   - `Queries.sh` – wrappers around Proxmox queries (`__get_ip_from_vmid__`, `__get_ip_from_guest_agent__`, VM/LXC listings, etc.).
   - `SSH.sh` – utilities for reliable SSH waits, scp transfers, script uploads, and remote function execution (`__ssh_exec__`, `__scp_send__`, `__ssh_exec_script__`, `__ssh_exec_function__`).
- `Utilities/Utilities.md` provides higher-level documentation for these helpers; update it when you add or modify utilities.

### 3.13 GUI Invocation Expectations

- When invoked via `GUI.sh`, scripts should rely on `${UTILITYPATH}` for sourcing utilities and must be executable on their own (`./script.sh` or `bash script.sh`).
- Include at least one `./ExampleCommand.sh` usage line in the header - the GUI extracts these examples for display.
- Clean up background processes and temporary state on exit.

### 3.14 Quick Pre-Commit Checklist

- [ ] Header includes description, usage, and Function Index placeholder.
- [ ] All required utilities are sourced; no duplicated helper logic.
- [ ] Variables are quoted and scoped appropriately.
- [ ] Error handling and cleanup paths are present.
- [ ] Testing notes updated and (where possible) ShellCheck run.

### 3.15 Minimal End-to-End Example

For a quick reference, here’s a compact script skeleton that follows every requirement. Use this as a mental checklist or see `_ExampleScript.sh`:

```bash
#!/bin/bash
#
# SampleMinimal.sh
#
# Demonstrates the minimal structure for ProxmoxScripts contributions.
#
# Usage:
#   ./SampleMinimal.sh --example "value"
#
# Function Index:
#   - parse_args
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR
trap 'rm -f "${TMP_FILE:-}"' EXIT

parse_args() {
   EXAMPLE_VALUE=""
   while [[ $# -gt 0 ]]; do
      case "$1" in
         --example)
            EXAMPLE_VALUE="$2"; shift 2 ;;
         -h|--help)
            __info__ "Usage: ./SampleMinimal.sh --example <value>"; exit 0 ;;
         *)
            __err__ "Unknown argument: $1"; exit 64 ;;
      esac
   done

   [[ -n "$EXAMPLE_VALUE" ]] || { __err__ "--example is required"; exit 64; }
}

main() {
   __check_root__
   __info__ "Running with example value: ${EXAMPLE_VALUE}"
   # ... perform work here ...
   __ok__ "Done"
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-03: Ran locally on PVE 8.2 test node (root shell)
```

For a complete walk-through with richer prompts, colors, and validation patterns, study `Utilities/_ExampleScript.sh` alongside this minimal skeleton.

---

## 4. Submitting Changes

1. **Commit Messages**  
   - Use clear, concise commit messages. 
   - Reference any related issues (e.g., `Fixes #123`) in your commit or PR description.

2. **Pull Request Description**  
   - Use the [Pull Request Template](.github/PULL_REQUEST_TEMPLATE.md)
   - Provide a summary of what the PR does and why.  
   - Include screenshots, logs, or references if it helps the reviewer.

3. **Code Review**  
   - All pull requests undergo review from maintainers or other contributors.  
   - Address feedback promptly and be open to revising your approach.

4. **Testing**  
   - Test your script in a test or sandbox environment (especially for Proxmox clusters).  
   - Document any steps to reproduce your tests.

---

## 5. Good Practices

- **Small, Focused Changes**: Submit small, atomic pull requests to keep reviews manageable.  
- **Security Considerations**: Avoid storing or echoing sensitive data (tokens, passwords) in logs, follow the [Security Policy](SECURITY.md)
- **Documentation**: Update or create documentation relevant to your changes (e.g., script headers and comments).  
- **Respect the Code of Conduct**: Please be courteous and follow our [Code of Conduct](CODE_OF_CONDUCT.md).

---

## 6. Thank You

By following these guidelines, you help us maintain a clean, consistent codebase and an effective workflow. If you have any questions or suggestions for improving these guidelines, feel free to open an issue or drop a comment in a pull request.
