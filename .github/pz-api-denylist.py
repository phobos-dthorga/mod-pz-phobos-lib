#!/usr/bin/env python3
"""PZ API Deny-List Scanner — catches known-bad PZ Java API patterns in Lua code.

Maintains a curated list of PZ B42 Java method calls that are either:
  - Non-existent (method removed or never existed)
  - Misused (wrong argument types/counts)
  - Deprecated with a safer replacement

Designed for CI: exits 0 on clean, 1 on violations. GitHub Actions annotations emitted.

Usage:
  python3 pz-api-denylist.py <lua-dir> [<lua-dir2> ...]

Example:
  python3 .github/pz-api-denylist.py common/media/lua/
"""

import os
import re
import sys

# ─────────────────────────────────────────────────────────────────
# DENY LIST
#
# Each entry: (compiled_regex, message, severity)
#   - pattern matches a SINGLE LINE of Lua source
#   - message explains what's wrong and what to use instead
#   - severity: "error" fails CI, "warning" annotates but passes
#
# Add new entries as new pitfalls are discovered. Keep them sorted
# by category for readability.
# ─────────────────────────────────────────────────────────────────

DENY_LIST = []


def deny(pattern, message, severity="error"):
    """Register a deny-list entry."""
    DENY_LIST.append((re.compile(pattern), message, severity))


# ── ItemContainer methods that don't exist ──────────────────────

deny(
    r":containsTypeEval\s*\(",
    "containsTypeEval() does not exist in PZ B42. "
    "Use :containsType(fullType) for simple checks, "
    "or :containsTypeEvalRecurse(type, luaClosure) if you need a filter.",
)

deny(
    r":removeFromIndex\s*\(",
    "removeFromIndex() does not exist on ItemContainer in PZ B42. "
    "Use :Remove(item) or :removeItem(item) instead.",
)

# ── ItemContainer methods with wrong arg count ──────────────────

deny(
    r":getFirstTypeEval\s*\(\s*[^,)]+\s*\)",
    "getFirstTypeEval(type) requires TWO args: (String, LuaClosure). "
    "Use :getFirstType(fullType) for simple lookups without a filter.",
)

# ── splitString misuse ──────────────────────────────────────────

deny(
    r'splitString\s*\([^,]+,\s*["\']',
    "splitString(input, maxSize) takes (String, int) — second arg is max splits, "
    "NOT a delimiter string. Use PhobosLib.split(str, sep) for delimiter-based splitting.",
)

# ── InventoryItem:hasTag with raw string ────────────────────────
# hasTag() expects an ItemTag enum object, not a plain string.
# On some item subclasses (Clothing), passing a string causes a
# MultiLuaJavaInvoker crash because the overload resolver fails.
# Safe pattern: pcall/safecall around hasTag, or use PhobosLib.findItemsByTag.

deny(
    r':hasTag\s*\(\s*["\']',
    "hasTag() expects an ItemTag object, not a string literal. "
    "Passing a raw string crashes on Clothing items (MultiLuaJavaInvoker). "
    "Wrap in PhobosLib.safecall() or use PhobosLib.findItemsByTag().",
    severity="warning",
)

# ── Traits API misuse ──────────────────────────────────────────

deny(
    r":getTraits\s*\(\s*\)\s*:\s*contains\s*\(",
    "player:getTraits():contains() does not work in PZ B42. "
    "getTraits() returns Map<CharacterTrait, Boolean> with no contains(). "
    "Use PhobosLib.hasTrait(player, traitId) or player:getDescriptor():hasTrait(CharacterTrait[id]).",
)

# ── PhobosLib.debug/trace with missing tag argument ──────────────────
# PhobosLib.debug(modId, tag, msg) requires 3 args. Calling with just
# (modId, msg) puts the message into `tag` and leaves `msg` nil, which
# causes a Kahlua __concat RuntimeException that blows through pcall.

deny(
    r'PhobosLib\.debug\(\s*"[^"]+"\s*,\s*"[^"]*"\s*\)',
    "PhobosLib.debug() called with 2 args (modId, msg) — missing tag. "
    "Use PhobosLib.debug(modId, _TAG, msg) with 3 args. "
    "Nil msg causes a Kahlua __concat RuntimeException.",
)

deny(
    r'PhobosLib\.trace\(\s*"[^"]+"\s*,\s*"[^"]*"\s*\)',
    "PhobosLib.trace() called with 2 args (modId, msg) — missing tag. "
    "Use PhobosLib.trace(modId, _TAG, msg) with 3 args. "
    "Nil msg causes a Kahlua __concat RuntimeException.",
)

# ── Raw defensive pcall in Phobos mods (new code should use safecall) ──
# This is a warning, not an error — existing code may still have raw pcall.
# Only flag pcall sites that are clearly defensive (not API probing).
# Disabled by default — uncomment when ready for migration enforcement.
#
# deny(
#     r'(?<!PhobosLib\.)(?<!function PhobosLib\.)pcall\s*\(\s*function',
#     "Prefer PhobosLib.safecall(function() ... end) over raw pcall(function() ... end) "
#     "for defensive wrapping. See §25 in design-guidelines.md.",
#     severity="warning",
# )


# ─────────────────────────────────────────────────────────────────
# SCANNER
# ─────────────────────────────────────────────────────────────────

def scan_file(filepath):
    """Scan a single Lua file against the deny list. Returns list of violations."""
    violations = []
    try:
        with open(filepath, encoding="utf-8") as f:
            lines = f.readlines()
    except (OSError, UnicodeDecodeError):
        return violations

    for line_num, line in enumerate(lines, start=1):
        # Skip comment-only lines
        stripped = line.lstrip()
        if stripped.startswith("--"):
            continue

        for pattern, message, severity in DENY_LIST:
            if pattern.search(line):
                violations.append((filepath, line_num, line.rstrip(), message, severity))

    return violations


def scan_dirs(dirs):
    """Walk directories, scan all .lua files."""
    all_violations = []
    file_count = 0

    for d in dirs:
        if not os.path.isdir(d):
            print(f"Warning: directory not found: {d}", file=sys.stderr)
            continue
        for root, _dirs, files in os.walk(d):
            for fname in sorted(files):
                if not fname.endswith(".lua"):
                    continue
                filepath = os.path.join(root, fname)
                file_count += 1
                all_violations.extend(scan_file(filepath))

    return all_violations, file_count


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <lua-dir> [<lua-dir2> ...]", file=sys.stderr)
        sys.exit(2)

    dirs = sys.argv[1:]
    violations, file_count = scan_dirs(dirs)

    errors = 0
    warnings = 0

    for filepath, line_num, line_text, message, severity in violations:
        # Emit GitHub Actions annotation
        if severity == "error":
            print(f"::error file={filepath},line={line_num}::{message}")
            errors += 1
        else:
            print(f"::warning file={filepath},line={line_num}::{message}")
            warnings += 1
        # Also print human-readable context
        print(f"  {filepath}:{line_num}: {line_text.strip()}")
        print()

    # Summary
    print(f"Scanned {file_count} Lua file(s), "
          f"{len(DENY_LIST)} deny-list rule(s): "
          f"{errors} error(s), {warnings} warning(s).")

    if errors > 0:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
