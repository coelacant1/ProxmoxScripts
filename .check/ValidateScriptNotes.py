#!/usr/bin/env python3
"""
validate_script_notes.py

Validates and fixes script notes format in shell scripts.

This script:
1. Finds all .sh files in the repository
2. Validates they have proper "Script notes" section
3. Checks for all required sections: Changes, Fixes, Known issues
4. Adds missing sections or entire block if not present
5. Does NOT update dates - must be done manually

Usage:
    python3 validate_script_notes.py [--fix] [--verbose] [path]

Arguments:
    --fix       Apply fixes to scripts (default: dry-run)
    --verbose   Show detailed output
    path        Path to validate (default: current directory)

Examples:
    python3 validate_script_notes.py                    # Dry-run, show issues
    python3 validate_script_notes.py --fix              # Fix all issues
    python3 validate_script_notes.py --fix Resources/   # Fix specific directory
    python3 validate_script_notes.py --verbose          # Show detailed output
"""

import os
import re
import sys
import argparse
from pathlib import Path
from typing import List, Tuple, Optional

###############################################################################
# Configuration
###############################################################################

SCRIPT_NOTES_TEMPLATE = """###############################################################################
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
"""

REQUIRED_SECTIONS = ['Changes:', 'Fixes:', 'Known issues:']

###############################################################################
# Helper Functions
###############################################################################

def find_shell_scripts(base_path: Path) -> List[Path]:
    """Find all .sh files in the given path."""
    if base_path.is_file() and base_path.suffix == '.sh':
        return [base_path]
    
    scripts = []
    for root, dirs, files in os.walk(base_path):
        # Skip .git and hidden directories
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        
        for file in files:
            if file.endswith('.sh'):
                scripts.append(Path(root) / file)
    
    return sorted(scripts)


def find_script_notes_block(lines: List[str]) -> Optional[Tuple[int, int]]:
    """
    Find the script notes block in the file.
    Returns (start_line, end_line) or None if not found.
    Searches from the bottom of the file for the last # comment block.
    """
    # Look for the script notes separator from the bottom
    separator_pattern = r'^#{3,}$'
    notes_header_pattern = r'^#\s*Script notes:\s*$'
    
    # Find all lines matching the separator pattern
    separator_lines = []
    for i, line in enumerate(lines):
        if re.match(separator_pattern, line.rstrip()):
            separator_lines.append(i)
    
    if len(separator_lines) < 2:
        # Try to find old format "# Script notes:" without separators
        for i in range(len(lines) - 1, -1, -1):
            if re.match(r'^#\s*Script notes:', lines[i]):
                # Found old format, find the end of the comment block
                start = i
                end = i
                for j in range(i + 1, len(lines)):
                    if lines[j].strip().startswith('#') or lines[j].strip() == '':
                        end = j
                    else:
                        break
                return (start, end)
        return None
    
    # Check the last two separators for script notes header
    for i in range(len(separator_lines) - 1, 0, -1):
        start_sep = separator_lines[i - 1]
        end_sep = separator_lines[i]
        
        # Check if there's a "Script notes:" header between the separators
        for line_idx in range(start_sep, end_sep + 1):
            if re.match(notes_header_pattern, lines[line_idx]):
                # Found the script notes block, find the end
                end = end_sep
                for j in range(end_sep + 1, len(lines)):
                    if lines[j].strip().startswith('#') or lines[j].strip() == '':
                        end = j
                    else:
                        break
                return (start_sep, end)
    
    return None


def validate_script_notes(lines: List[str], start: int, end: int) -> Tuple[bool, List[str]]:
    """
    Validate the script notes block has all required sections.
    Returns (is_valid, missing_sections).
    """
    block_text = '\n'.join(lines[start:end + 1])
    missing_sections = []
    
    for section in REQUIRED_SECTIONS:
        # Look for "# Changes:", "# Fixes:", "# Known issues:"
        if not re.search(rf'^#\s*{re.escape(section)}\s*$', block_text, re.MULTILINE):
            missing_sections.append(section)
    
    return (len(missing_sections) == 0, missing_sections)


def create_script_notes_block() -> List[str]:
    """Create a new script notes block with all required sections."""
    return SCRIPT_NOTES_TEMPLATE.strip().split('\n')


def fix_script_notes(lines: List[str], start: int, end: int, missing_sections: List[str]) -> List[str]:
    """
    Fix the script notes block by adding missing sections.
    Returns the updated lines.
    """
    # Extract current block
    block_lines = lines[start:end + 1]
    
    # Find where to insert missing sections
    # Strategy: Add after "Last checked:" and before the closing comment block
    
    # Find "Last checked:" line
    last_checked_idx = None
    for i, line in enumerate(block_lines):
        if re.match(r'^#\s*Last checked:', line):
            last_checked_idx = i
            break
    
    if last_checked_idx is None:
        # No "Last checked" found, can't fix reliably - replace entire block
        new_block = create_script_notes_block()
        return lines[:start] + new_block + [''] + lines[end + 1:]
    
    # Find existing sections
    section_positions = {}
    for i, line in enumerate(block_lines):
        for section in REQUIRED_SECTIONS:
            if re.match(rf'^#\s*{re.escape(section)}\s*$', line):
                section_positions[section] = i
    
    # Build new block with all sections in order
    new_block = []
    insert_idx = last_checked_idx + 1
    
    # Copy header (separator, "Script notes:", separator, "Last checked:")
    new_block.extend(block_lines[:insert_idx])
    
    # Ensure blank line after "Last checked:"
    if insert_idx < len(block_lines) and block_lines[insert_idx].strip() != '#':
        new_block.append('#')
    
    # Add sections in order
    for section in REQUIRED_SECTIONS:
        if section in section_positions:
            # Section exists, find its content
            sec_idx = section_positions[section]
            # Copy from section header until next section or end
            new_block.append(block_lines[sec_idx])
            
            # Find next section or end of block
            next_idx = len(block_lines)
            for next_section in REQUIRED_SECTIONS:
                if next_section in section_positions and section_positions[next_section] > sec_idx:
                    next_idx = min(next_idx, section_positions[next_section])
            
            # Copy content lines
            for i in range(sec_idx + 1, next_idx):
                if i < len(block_lines):
                    new_block.append(block_lines[i])
        else:
            # Section missing, add it
            new_block.append(f'# {section}')
            new_block.append('# -')
            new_block.append('#')
    
    # Ensure trailing blank comment line
    if new_block and new_block[-1].strip() != '#':
        new_block.append('#')
    
    return lines[:start] + new_block + lines[end + 1:]


def process_script(script_path: Path, fix: bool = False, verbose: bool = False) -> Tuple[str, bool]:
    """
    Process a single script file.
    Returns (status_message, needs_fix).
    """
    try:
        with open(script_path, 'r', encoding='utf-8') as f:
            lines = [line.rstrip('\n') for line in f.readlines()]
    except Exception as e:
        return (f"ERROR: Could not read file: {e}", False)
    
    # Find script notes block
    block_range = find_script_notes_block(lines)
    
    if block_range is None:
        # No script notes block found, add one
        if fix:
            new_lines = lines + [''] + create_script_notes_block()
            try:
                with open(script_path, 'w', encoding='utf-8') as f:
                    f.write('\n'.join(new_lines) + '\n')
                return ("FIXED: Added script notes block", True)
            except Exception as e:
                return (f"ERROR: Could not write file: {e}", True)
        else:
            return ("MISSING: Script notes block not found", True)
    
    start, end = block_range
    
    # Validate sections
    is_valid, missing_sections = validate_script_notes(lines, start, end)
    
    if is_valid:
        return ("OK: All sections present", False)
    
    # Has issues
    if fix:
        try:
            new_lines = fix_script_notes(lines, start, end, missing_sections)
            with open(script_path, 'w', encoding='utf-8') as f:
                f.write('\n'.join(new_lines) + '\n')
            return (f"FIXED: Added missing sections: {', '.join(missing_sections)}", True)
        except Exception as e:
            return (f"ERROR: Could not fix file: {e}", True)
    else:
        return (f"INVALID: Missing sections: {', '.join(missing_sections)}", True)


###############################################################################
# Main
###############################################################################

def main():
    parser = argparse.ArgumentParser(
        description='Validate and fix script notes format in shell scripts.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    %(prog)s                    # Dry-run, show issues
    %(prog)s --fix              # Fix all issues
    %(prog)s --fix Resources/   # Fix specific directory
    %(prog)s --verbose          # Show detailed output
        """
    )
    parser.add_argument('path', nargs='?', default='.',
                        help='Path to validate (default: current directory)')
    parser.add_argument('--fix', action='store_true',
                        help='Apply fixes to scripts (default: dry-run)')
    parser.add_argument('--verbose', action='store_true',
                        help='Show detailed output for all files')
    
    args = parser.parse_args()
    
    # Convert path
    base_path = Path(args.path)
    if not base_path.exists():
        print(f"Error: Path does not exist: {base_path}", file=sys.stderr)
        return 1
    
    # Find scripts
    scripts = find_shell_scripts(base_path)
    if not scripts:
        print(f"No shell scripts found in: {base_path}")
        return 0
    
    print(f"{'='*80}")
    print(f"Script Notes Validation")
    print(f"{'='*80}")
    print(f"Mode: {'FIX' if args.fix else 'DRY-RUN'}")
    print(f"Path: {base_path.resolve()}")
    print(f"Scripts found: {len(scripts)}")
    print(f"{'='*80}\n")
    
    # Process scripts
    total = len(scripts)
    ok_count = 0
    fixed_count = 0
    error_count = 0
    missing_count = 0
    invalid_count = 0
    
    for script in scripts:
        rel_path = script.relative_to(base_path) if base_path.is_dir() else script.name
        status, needs_fix = process_script(script, args.fix, args.verbose)
        
        # Categorize
        if status.startswith('OK:'):
            ok_count += 1
            if args.verbose:
                print(f"✓ {rel_path}: {status}")
        elif status.startswith('FIXED:'):
            fixed_count += 1
            print(f"✓ {rel_path}: {status}")
        elif status.startswith('MISSING:'):
            missing_count += 1
            print(f"✗ {rel_path}: {status}")
        elif status.startswith('INVALID:'):
            invalid_count += 1
            print(f"⚠ {rel_path}: {status}")
        elif status.startswith('ERROR:'):
            error_count += 1
            print(f"✗ {rel_path}: {status}")
    
    # Summary
    print(f"\n{'='*80}")
    print(f"Summary")
    print(f"{'='*80}")
    print(f"Total scripts: {total}")
    print(f"  ✓ OK: {ok_count}")
    if args.fix:
        print(f"  ✓ Fixed: {fixed_count}")
    else:
        print(f"  ✗ Missing notes: {missing_count}")
        print(f"  ⚠ Invalid sections: {invalid_count}")
    if error_count > 0:
        print(f"  ✗ Errors: {error_count}")
    print(f"{'='*80}")
    
    if not args.fix and (missing_count > 0 or invalid_count > 0):
        print(f"\nℹ Run with --fix to apply fixes")
        return 1
    
    return 0


if __name__ == '__main__':
    sys.exit(main())

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Initial creation
# - 2025-11-20: Added script notes validation logic
# - 2025-11-20: Added missing section detection
# - 2025-11-20: Added fix functionality
#
# Fixes:
# -
#
# Known issues:
# - Does not update dates (by design - must be manual)
# - Complex nested comment blocks may be mis-detected
#
