# ProxmoxScripts Shell Script Style Guide

This style guide captures the conventions used across the ProxmoxScripts repository 
and in the `Utilities/_ExampleScript.sh` example. Follow it when adding or updating 
shell scripts so they look and behave consistently.

## Core principles

- Keep scripts simple, idempotent, and safe to run on Proxmox nodes.
- Provide a clear header with usage examples and notes.
- Reuse shared utilities in `Utilities/` rather than copying behavior.

## Where to place files

- Utilities/helpers: `Utilities/`
- Feature scripts: folders grouped by domain (e.g. `Host/`, `Cluster/`, `Storage/`)
- Filenames: descriptive, MixedCase like `CreateCluster.sh`.

## Shebang and strictness

- Use a bash shebang: `#!/bin/bash`
- Avoid `set -e` globally. Prefer explicit error handling and traps where the
  script needs them.

## File header

All scripts should include a top comment block with:

- filename and short description
- usage example(s)
- notes (root requirement, Proxmox requirement, special permissions)
- a `Function Index:` list for longer scripts

Example header snippet:

```bash
#!/bin/bash
#
# MyScript.sh
#
# Short description...
#
# Function Index:
#   - check_something
#   - do_work
#
```

### Function Index format (required)

The repository contains a tool (`.check/UpdateFunctionIndex.py`) that updates a
script's Function Index automatically. To keep that working:

- The Function Index header must be exactly: `# Function Index:`
- List each function as `#   - function_name` on its own line.
- The updater scans the top contiguous comment block (lines starting with `#`) and
  replaces the Function Index block with the names it finds.
- Functions are discovered by matching `name() {` or `function name() {`.

Only include bare function names in the index (no signatures or extra notes).

## Common structure

1. Source shared utilities (e.g. `source "${UTILITYPATH}/Prompts.sh"`). Note:
   when called via `GUI.sh`, `${UTILITYPATH}` is exported for you.
2. Initial checks: `__check_root__`, `__check_proxmox__` as needed.
3. Argument parsing and validation (error + usage on bad input).
4. Functions grouped and documented; use separators:
   (`###############################################################################`).
5. Main logic wrapped in a `main()` function and executed at the bottom.
6. Testing notes at the end of the file.

## Coding conventions

- Use consistent indentation (follow existing file style).
- Prefer `local var` inside functions.
- Use `[[ ... ]]` and `(( ... ))` where appropriate.
- Always quote expansions: `"${var}"`.
- Use `command -v foo &>/dev/null` to check for commands.

## Logging and user feedback

- Reuse `Utilities/Communication.sh` helpers:
  - `__info__ "message"`
  - `__update__ "message"`
  - `__ok__ "message"`
  - `__err__ "message"`
- Non-interactive scripts may prefer simple `echo` and structured output.

## Error handling

- When using `Communication.sh`, install the ERR trap:

```bash
trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR
```

- Prefer an idempotent `cleanup()` run on EXIT (via `trap cleanup EXIT`).

## Argument parsing

- Keep it simple. Use `getopts` for many flags; otherwise simple case-based
  parsing is fine.

## Testing & comments

- Add a `# Testing status` block near the end describing how the script was
  tested.
- Keep inline comments short and relevant.

## Reusable template

Use `Utilities/ScriptTemplate.sh` as a starting point for new scripts.

## Key utility scripts

The repository provides several utility scripts under `Utilities/` that are
commonly used by other scripts. Whenever possible, source and reuse these
helpers instead of duplicating logic.

- `Colors.sh` – helpers for printing colored text and gradients, and small
  helpers for asynchronous visual effects. Useful for consistent, colorful
  CLI output.
- `Communication.sh` – spinner and message helpers (`__info__`, `__update__`,
  `__ok__`, `__err__`), and an error trap helper `__handle_err__`. Use this to
  keep user-facing output consistent across scripts.
- `Conversion.sh` – small data conversion helpers (IP <-> integer, formatting,
  etc.) used widely by network and VM utilities.
- `Prompts.sh` – interactive prompt helpers, package-install prompts
  (`__install_or_prompt__`), and environment checks (`__check_root__`,
  `__check_proxmox__`). Source this for safe prompting and prerequisite checks.
- `Queries.sh` – functions to query Proxmox state (VM lists, LXC/QEMU details,
  and `__get_ip_from_vmid__` for IP resolution). Prefer these helpers over ad-
  hoc parsing of `qm`/`pct` output.
- `SSH.sh` – SSH convenience helpers such as `__wait_for_ssh__` that repeatedly
  try to connect until a host is reachable. Use these for reliable remote
  operations instead of rolling custom wait loops.

## Documentation: `Utilities.md`

There is also `Utilities/Utilities.md` which provides an overview of available
functions and higher-level documentation for the helpers above. Check that
document when you're looking for a function name or usage example.

If you maintain or add utilities, consider adding or updating `Utilities.md` –
it can be updated programmatically by a script placed under `.check/` (for
example, a small tool that extracts doc blocks and generates the Markdown).

## Scripts invocation via `GUI.sh`

- Do not duplicate utility behavior. Source helpers from `${UTILITYPATH}`.
- Scripts must be runnable as an executable or with `bash script.sh` (assuming 
  a manual utility path export)
- Include an example invocation line starting with `./` (the GUI extracts this
  to show usage).
- Prefer `__info__`/`__update__`/`__ok__`/`__err__` to keep UX consistent.
- Ensure background processes are cleaned up (trap on EXIT).

## Quick pre-commit checklist

- [ ] Does it expose functions with standard definitions for the index updater?
- [ ] Does the header contain usage and description?
- [ ] Did you source the appropriate helpers?
- [ ] Are variables quoted and local where appropriate?
- [ ] Does the script exit with useful error codes?
- [ ] Did you run smoke tests and record the results?

