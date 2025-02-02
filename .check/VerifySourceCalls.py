#!/usr/bin/env python3

import os
import re
import sys
import argparse
from pathlib import Path

# -----------------------------------------------------------------------------
# HARD-CODED DIRECTORIES:
# Adjust these as needed for your environment.
# -----------------------------------------------------------------------------
script_dir = Path(__file__).resolve().parent

SCRIPTS_DIR = script_dir.parent  # if your scripts are one level up
UTILITIES_DIR = script_dir.parent / "Utilities"

# -----------------------------------------------------------------------------
# Regex for function definitions: "__myFunction__() {" or "function __myFunction__ {"
# We capture the entire name with underscores.
# -----------------------------------------------------------------------------
FUNC_DEF_REGEX = re.compile(
    r'^(?:function\s+)?(__[a-zA-Z0-9_]+__)\s*\(\)\s*\{'
)

# -----------------------------------------------------------------------------
# Regex for lines that source a utility:
#   source "${UTILITYPATH}/Something.sh"
#   . "${UTILITYPATH}/Something.sh"
# We'll capture "Something.sh" as group(1).
# -----------------------------------------------------------------------------
SOURCE_REGEX = re.compile(
    r'^\s*(?:source|\.)\s+"?\$\{?UTILITYPATH\}?/([a-zA-Z0-9_.-]+)"?'
)
# If your scripts always explicitly have ".sh" in the filename, adapt as needed:
#   r'^\s*(?:source|\.)\s+"?\$\{?UTILITYPATH\}?/([a-zA-Z0-9_.-]+\.sh)"?'

# -----------------------------------------------------------------------------
# Regex for function call tokens like "__something__"
# We'll detect them as distinct tokens in a line.
# -----------------------------------------------------------------------------
CALL_REGEX = re.compile(r'^__[a-zA-Z0-9_]+__$')

# -----------------------------------------------------------------------------
# 1) Build a global map:  function -> set of utility filenames that define it
# -----------------------------------------------------------------------------
def build_global_function_map(utilities_dir):
    """
    Recursively parse all .sh files under 'utilities_dir'
    Return { "__func__": {"FileA.sh", "FileB.sh"} }
    """
    global_map = {}
    utilities_path = Path(utilities_dir).resolve()

    if not utilities_path.is_dir():
        print(f"[WARNING] utilities_dir '{utilities_dir}' does not exist.")
        return global_map

    all_utility_scripts = list(utilities_path.rglob("*.sh"))
    for util_script in all_utility_scripts:
        funcs = parse_functions_in_file(util_script)
        for f in funcs:
            if f not in global_map:
                global_map[f] = set()
            global_map[f].add(util_script.name)
    return global_map

# -----------------------------------------------------------------------------
# 2) Parse function definitions from a single file
# -----------------------------------------------------------------------------
def parse_functions_in_file(filepath):
    results = set()
    if not os.path.isfile(filepath):
        return results

    with open(filepath, "r", encoding="utf-8", newline='\n') as f:
        for line in f:
            match = FUNC_DEF_REGEX.search(line.rstrip())
            if match:
                func_name = match.group(1)
                results.add(func_name)
    return results

# -----------------------------------------------------------------------------
# 3) Identify which utilities are included in a script & local function definitions
# -----------------------------------------------------------------------------
def parse_script_for_includes_and_local_funcs(script_path):
    includes = set()
    local_funcs = parse_functions_in_file(script_path)

    if not os.path.isfile(script_path):
        return includes, local_funcs

    with open(script_path, "r", encoding="utf-8", newline='\n') as f:
        for line in f:
            line_stripped = line.strip()
            s_match = SOURCE_REGEX.search(line_stripped)
            if s_match:
                # e.g., "Prompts.sh" or "Queries.sh"
                includes.add(s_match.group(1))
    return includes, local_funcs

# -----------------------------------------------------------------------------
# 4) Gather function calls from lines that are not function definitions
# -----------------------------------------------------------------------------
def gather_function_calls(script_path):
    calls = set()
    if not os.path.isfile(script_path):
        return calls

    with open(script_path, "r", encoding="utf-8", newline='\n') as f:
        for line in f:
            if FUNC_DEF_REGEX.search(line.strip()):
                # skip lines that define a function
                continue

            tokens = line.strip().split()
            for t in tokens:
                if CALL_REGEX.match(t):
                    if t == "__base__":
                        continue #Skip this function, as it is used by RBD, not a library function
                    calls.add(t)
    return calls

# -----------------------------------------------------------------------------
# 5) Cache for utility -> set of functions.  parse_utility_functions(Utility.sh).
# -----------------------------------------------------------------------------
_utility_func_cache = {}

def parse_utility_functions(utility_file):
    global _utility_func_cache
    if utility_file in _utility_func_cache:
        return _utility_func_cache[utility_file]

    full_path = Path(UTILITIES_DIR, utility_file).resolve()
    funcs = parse_functions_in_file(full_path)
    _utility_func_cache[utility_file] = funcs
    return funcs

# -----------------------------------------------------------------------------
# 6) Analyze a single script:
#    - Figure out which calls are unknown / where they might be found
#    - Which includes are used vs. unused
# -----------------------------------------------------------------------------
def analyze_script(script_path, global_map):
    """
    Returns:
      unknown_calls: list of (callName, reasonString)
      used_includes: set of included utility filenames that are actually used
      all_includes:  set of all includes in the script
    """
    all_includes, local_funcs = parse_script_for_includes_and_local_funcs(script_path)
    calls = gather_function_calls(script_path)

    # Build a dictionary of included_scripts -> set_of_functions
    included_funcs_map = {}
    for inc in all_includes:
        included_funcs_map[inc] = parse_utility_functions(inc)

    used_includes = set()
    unknown_calls = []

    for call in calls:
        if call in local_funcs:
            # local, so it's resolved
            continue

        # see if exactly one or multiple included scripts define it
        includes_that_define = set(
            inc for inc in all_includes
            if call in included_funcs_map[inc]
        )
        if len(includes_that_define) == 1:
            used_includes.add(list(includes_that_define)[0])
            continue
        elif len(includes_that_define) > 1:
            # resolved by multiple
            used_includes |= includes_that_define
            continue

        # Not found in the included scripts => check global map
        if call not in global_map:
            # truly unknown
            unknown_calls.append((call, "No utility defines it"))
        else:
            possible_scripts = global_map[call]
            if len(possible_scripts) == 1:
                # we can fix by adding that one
                only_script = list(possible_scripts)[0]
                unknown_calls.append((call, f"Needs source \"{only_script}\""))
            else:
                # multiple utilities define it => ambiguous
                unknown_calls.append((call, f"Defined in multiple scripts: {possible_scripts}"))

    return unknown_calls, used_includes, all_includes

# -----------------------------------------------------------------------------
# 7) For --fix mode, we want to:
#    - Summarize needed changes (Add or Remove sources)
#    - Prompt user Y/N for each script
#    - If Y, do the changes: add lines after the top # block, remove lines for unused
# -----------------------------------------------------------------------------
def fix_script(
    script_path,
    add_sources,
    remove_sources
):
    """
    Modify 'script_path' in-place:
      - Insert each needed 'source "${UTILITYPATH}/{something}"' after the top comment block
      - Remove lines that exactly match 'source "${UTILITYPATH}/{something}"'
    after user has confirmed.
    """
    if not add_sources and not remove_sources:
        return  # no changes needed

    with open(script_path, "r", encoding="utf-8", newline='\n') as f:
        lines = f.readlines()

    # 1) Build set of lines to remove (exact match, ignoring trailing spaces).
    remove_lines = {f'source "${{UTILITYPATH}}/{r}"' for r in remove_sources}
    remove_lines_dot = {f'. "${{UTILITYPATH}}/{r}"' for r in remove_sources}

    # 2) Insert lines for new sources after the top comment block.
    #    - The "comment block" is consecutive lines from the top that start with # (or are blank?).
    #      The request specifically said "every line starts with # until the end of the block".
    #      We'll define that carefully:
    insertion_index = find_comment_block_end(lines)

    # We'll build new lines as needed. We'll ensure we use the 'source' form (not dot).
    lines_to_insert = []
    for a in sorted(add_sources):
        line_text = f'source "${{UTILITYPATH}}/{a}"\n'
        # only insert if it doesn't already exist
        if not any(line.strip() == line_text.strip() for line in lines):
            lines_to_insert.append(line_text)

    # 3) Rebuild lines, skipping the ones to remove.
    new_lines = []
    for i, line in enumerate(lines):
        # We'll insert new sources at the insertion index
        if i == insertion_index and lines_to_insert:
            for to_ins in lines_to_insert:
                new_lines.append(to_ins)
        # Check if line is in remove_lines
        if should_remove_source_line(line, remove_lines, remove_lines_dot):
            # skip it
            continue
        new_lines.append(line)

    # Edge case: if insertion_index == len(lines), we might insert at the end
    if insertion_index == len(lines) and lines_to_insert:
        new_lines.extend(lines_to_insert)

    # 4) Write updated file
    with open(script_path, "w", encoding="utf-8") as f:
        f.writelines(new_lines)

def should_remove_source_line(line, remove_lines, remove_lines_dot):
    """
    Return True if line matches one of our remove_lines possibilities
    or the '.' version, ignoring trailing spaces.
    We'll compare stripped lines.
    """
    stripped = line.strip()
    return (stripped in remove_lines) or (stripped in remove_lines_dot)

def find_comment_block_end(lines):
    """
    Return the index of the first line that does NOT start with '#'.
    If all lines start with '#', return len(lines).
    """
    for i, line in enumerate(lines):
        stripped = line.lstrip()
        if not stripped.startswith("#") and stripped != "":
            return i
    return len(lines)

# -----------------------------------------------------------------------------
# 8) Main script
# -----------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Check unknown calls in .sh scripts and optionally fix missing sources.")
    parser.add_argument("--scripts-dir", default=SCRIPTS_DIR, help="Directory of .sh scripts to check (recursively).")
    parser.add_argument("--utilities-dir", default=UTILITIES_DIR, help="Directory containing utility .sh scripts.")
    parser.add_argument("--fix", action="store_true", help="Automatically add missing 'source' lines if exactly one utility defines the unknown call.")
    args = parser.parse_args()

    # 1) Build the global function map from all utilities
    global_map = build_global_function_map(args.utilities_dir)

    # 2) Collect all .sh scripts outside the utilities folder
    scripts_dir_path = Path(args.scripts_dir).resolve()
    utilities_path = Path(args.utilities_dir).resolve()

    all_scripts = list(scripts_dir_path.rglob("*.sh"))
    scripts_to_check = [
        s for s in all_scripts
        if not str(s.resolve()).startswith(str(utilities_path))
    ]

    # 3) Analyze each script
    for script_file in scripts_to_check:
        unknown_calls, used_includes, all_includes = analyze_script(script_file, global_map)
        # which includes to remove?
        unused_includes = all_includes - used_includes

        # which includes to add?
        # If unknown call says "Needs source \"XYZ.sh\"", we gather 'XYZ.sh' in a set
        missing_includes = set()
        truly_unknown = []
        for (call_name, reason) in unknown_calls:
            if reason.startswith("Needs source \""):
                # e.g. 'Needs source "XYZ.sh"'
                # extract 'XYZ.sh'
                # naive parse:
                needed = reason[len("Needs source \""):-1]
                missing_includes.add(needed)
            else:
                truly_unknown.append((call_name, reason))

        # If no issues, skip
        if not truly_unknown and not missing_includes and not unused_includes:
            print(f"[OK] {script_file} - all calls recognized; no unused includes.")
            continue

        # Print summary
        print(f"\n[CHECK] {script_file}")
        if truly_unknown:
            print("  Unknown or ambiguous calls:")
            for uc, rsn in truly_unknown:
                print(f"    {uc} -> {rsn}")
        if missing_includes:
            print("  Missing sources needed:")
            for m in sorted(missing_includes):
                print(f"    source \"${{UTILITYPATH}}/{m}\"")
        if unused_includes:
            print("  Unused includes:")
            for ui in sorted(unused_includes):
                print(f"    source \"${{UTILITYPATH}}/{ui}\"")

        if not args.fix:
            # Not fixing, just suggesting
            continue

        # If we are in --fix mode, prompt user Y/N for each script:
        # We'll fix them all or skip them all for the script.
        ans = input(f"Apply fixes to {script_file}? [y/N] ").strip().lower()
        if ans != 'y':
            print("  -> Skipped.")
            continue

        # Actually fix:
        fix_script(
            script_file,
            add_sources=missing_includes,
            remove_sources=unused_includes
        )
        print("  -> Fixes applied.")

    print("\nDone.")
    sys.exit(0)


if __name__ == "__main__":
    main()
