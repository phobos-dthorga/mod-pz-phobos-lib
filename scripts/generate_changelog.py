#!/usr/bin/env python3
"""Generate release notes from conventional commits between Git tags.

Produces both GitHub-flavoured Markdown and Steam Workshop BBCode changelogs.
Called by the release workflow to populate GitHub Release bodies and update
the Steam Workshop changelog file automatically.

Requires only Python stdlib (no pip packages).
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Conventional commit prefix → display category (order = display order)
CATEGORY_MAP = {
    "feat": "Features",
    "fix": "Fixes",
    "docs": "Documentation",
    "chore": "Maintenance",
    "refactor": "Maintenance",
    "test": "Maintenance",
    "ci": "Maintenance",
    "build": "Maintenance",
    "perf": "Maintenance",
    "style": "Maintenance",
    "revert": "Maintenance",
}

CATEGORY_ORDER = ["Breaking Changes", "Features", "Fixes", "Documentation", "Maintenance", "Other"]

# Regex for conventional commit subjects: prefix(scope)!: message
CC_PATTERN = re.compile(
    r"^(feat|fix|chore|docs|refactor|test|ci|build|perf|style|revert)"
    r"(?:\(.+?\))?"
    r"(!?)"
    r":\s*(.+)$"
)

# Subjects matching these patterns are excluded from changelogs
NOISE_PATTERNS = [
    re.compile(r"^[Mm]erge[ :]"),
    re.compile(r"bump[- ]version", re.IGNORECASE),
    re.compile(r"update.*metadata", re.IGNORECASE),
    re.compile(r"update.*changelog", re.IGNORECASE),
    re.compile(r"^v?\d+\.\d+\.\d+"),  # bare version number subjects
]

# Authors whose commits are excluded
EXCLUDED_AUTHORS = {"github-actions[bot]"}


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

def git(*args: str) -> str:
    """Run a git command and return stripped stdout."""
    result = subprocess.run(
        ["git", *args],
        capture_output=True, check=False,
    )
    if result.returncode != 0:
        return ""
    # Decode as UTF-8 explicitly to handle em dashes and other Unicode on Windows
    return result.stdout.decode("utf-8", errors="replace").strip()


def find_previous_tag(current_tag: str) -> str | None:
    """Find the most recent tag before *current_tag* in version order."""
    all_tags = git("tag", "--sort=-v:refname").splitlines()
    found_current = False
    for tag in all_tags:
        tag = tag.strip()
        if not tag:
            continue
        if tag == current_tag:
            found_current = True
            continue
        if found_current:
            return tag
    return None


def get_root_commit() -> str:
    """Return the SHA of the very first commit in the repo."""
    return git("rev-list", "--max-parents=0", "HEAD")


def get_tag_annotation(tag: str) -> str:
    """Return the subject line of an annotated tag's message."""
    return git("tag", "-l", "--format=%(contents:subject)", tag)


def collect_commits(from_ref: str, to_ref: str) -> list[dict]:
    """Collect commits between two refs.

    Returns a list of dicts with keys: hash, subject, body, author.
    Uses a unique delimiter to avoid issues with null bytes on Windows.
    """
    sep = "<<|>>"
    record_sep = "<<||>>"
    fmt = f"{record_sep}%H{sep}%s{sep}%b{sep}%an"
    raw = git("log", f"{from_ref}..{to_ref}", f"--format={fmt}", "--no-merges")
    if not raw:
        return []

    commits = []
    for entry in raw.split(record_sep):
        entry = entry.strip()
        if not entry:
            continue
        parts = entry.split(sep, 3)
        if len(parts) < 4:
            continue
        commits.append({
            "hash": parts[0].strip(),
            "subject": parts[1].strip(),
            "body": parts[2].strip(),
            "author": parts[3].strip(),
        })
    return commits


# ---------------------------------------------------------------------------
# Commit processing
# ---------------------------------------------------------------------------

def is_noise(subject: str) -> bool:
    """Return True if the commit subject is changelog noise."""
    return any(p.search(subject) for p in NOISE_PATTERNS)


def parse_commit(commit: dict) -> dict | None:
    """Parse a commit dict into a changelog entry, or None to skip."""
    if commit["author"] in EXCLUDED_AUTHORS:
        return None

    subject = commit["subject"]
    if is_noise(subject):
        return None

    m = CC_PATTERN.match(subject)
    if m:
        prefix, breaking_bang, message = m.group(1), m.group(2), m.group(3)
        is_breaking = bool(breaking_bang) or "BREAKING CHANGE" in commit["body"]
        category = "Breaking Changes" if is_breaking else CATEGORY_MAP.get(prefix, "Other")
    else:
        # Non-conventional commit — include under Other
        message = subject
        category = "Other"
        is_breaking = False

    return {
        "hash": commit["hash"],
        "short_hash": commit["hash"][:7],
        "message": message,
        "category": category,
        "is_breaking": is_breaking,
    }


def group_commits(commits: list[dict]) -> dict[str, list[dict]]:
    """Group parsed commit entries by category, deduplicating by message."""
    groups: dict[str, list[dict]] = {}
    seen_messages: set[str] = set()

    for commit in commits:
        entry = parse_commit(commit)
        if entry is None:
            continue
        # Deduplicate by normalised message
        norm = entry["message"].lower().strip()
        if norm in seen_messages:
            continue
        seen_messages.add(norm)

        cat = entry["category"]
        groups.setdefault(cat, []).append(entry)

    return groups


# ---------------------------------------------------------------------------
# Subtitle detection
# ---------------------------------------------------------------------------

def detect_subtitle(tag: str, explicit_subtitle: str | None) -> str:
    """Determine the release subtitle.

    Priority: explicit CLI arg > tag annotation > channel-based default.
    """
    if explicit_subtitle:
        return explicit_subtitle

    # Try to extract from annotated tag message
    annotation = get_tag_annotation(tag)
    if annotation:
        # Look for "— subtitle" or "-- subtitle" after the version
        for sep in ("—", " -- ", " - "):
            if sep in annotation:
                _, _, sub = annotation.partition(sep)
                sub = sub.strip()
                if sub:
                    return sub

    # Channel-based default
    if re.search(r"-(alpha|beta|rc)\.", tag):
        return "Pre-release"

    return ""


def detect_channel(tag: str) -> str:
    """Detect release channel from tag name."""
    if "-alpha." in tag:
        return "alpha"
    if "-beta." in tag:
        return "beta"
    if "-rc." in tag:
        return "rc"
    return "stable"


# ---------------------------------------------------------------------------
# Markdown generation
# ---------------------------------------------------------------------------

def generate_markdown(
    tag: str,
    subtitle: str,
    groups: dict[str, list[dict]],
    repository: str,
    prev_tag: str | None,
    dependencies: dict,
) -> str:
    """Generate GitHub-flavoured Markdown release notes."""
    lines: list[str] = []

    # Header
    header = f"## {tag}"
    if subtitle:
        header += f" — {subtitle}"
    lines.append(header)
    lines.append("")

    # Categorised commits
    for cat in CATEGORY_ORDER:
        entries = groups.get(cat, [])
        if not entries:
            continue
        lines.append(f"### {cat}")
        for e in entries:
            commit_url = f"https://github.com/{repository}/commit/{e['hash']}"
            lines.append(f"- {e['message']} ([{e['short_hash']}]({commit_url}))")
        lines.append("")

    # Dependencies section
    if dependencies:
        lines.append("### Dependencies")
        for dep_name, dep_version in dependencies.items():
            lines.append(f"- {dep_name} {dep_version}")
        lines.append("")

    # Full changelog link
    if prev_tag:
        compare_url = f"https://github.com/{repository}/compare/{prev_tag}...{tag}"
        lines.append(f"**Full Changelog**: {compare_url}")
    else:
        tag_url = f"https://github.com/{repository}/releases/tag/{tag}"
        lines.append(f"**Release**: {tag_url}")

    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# BBCode generation
# ---------------------------------------------------------------------------

def generate_bbcode(
    tag: str,
    subtitle: str,
    groups: dict[str, list[dict]],
) -> str:
    """Generate Steam Workshop BBCode changelog block."""
    lines: list[str] = []

    # Version header
    header = tag
    if subtitle:
        header += f" — {subtitle}"
    lines.append(f"[h2]{header}[/h2]")
    lines.append("[list]")

    # Flat list — features first, then fixes (prefixed), then everything else
    for cat in CATEGORY_ORDER:
        entries = groups.get(cat, [])
        for e in entries:
            if cat == "Fixes":
                lines.append(f"[*] (Fix) {e['message']}")
            elif cat == "Breaking Changes":
                lines.append(f"[*] (Breaking) {e['message']}")
            else:
                lines.append(f"[*] {e['message']}")

    lines.append("[/list]")
    return "\n".join(lines) + "\n"


def prepend_bbcode(bbcode_block: str, filepath: str) -> None:
    """Prepend a BBCode block to an existing changelog file."""
    path = Path(filepath)
    existing = ""
    if path.exists():
        existing = path.read_text(encoding="utf-8")

    # If the file starts with [h1]Changelog[/h1], insert after that line
    h1_pattern = re.compile(r"^(\[h1\].*?\[/h1\]\s*\n?)", re.IGNORECASE)
    m = h1_pattern.match(existing)
    if m:
        header = m.group(1)
        rest = existing[m.end():]
        new_content = header + "\n" + bbcode_block + "\n[hr][/hr]\n\n" + rest
    elif existing.strip():
        new_content = bbcode_block + "\n[hr][/hr]\n\n" + existing
    else:
        # Empty or new file — add the h1 header
        new_content = "[h1]Changelog[/h1]\n\n" + bbcode_block + "\n"

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(new_content, encoding="utf-8")


# ---------------------------------------------------------------------------
# Title generation
# ---------------------------------------------------------------------------

def generate_title(mod_name: str, tag: str, subtitle: str) -> str:
    """Generate the release title string."""
    title = f"{mod_name} {tag}"
    if subtitle:
        title += f" — {subtitle}"
    return title


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

def load_dependencies(repo_root: str) -> dict:
    """Load dependencies.json from repo root if it exists."""
    dep_path = Path(repo_root) / "dependencies.json"
    if not dep_path.exists():
        return {}
    try:
        with open(dep_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return data
    except (json.JSONDecodeError, OSError):
        pass
    return {}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate release notes from conventional commits between Git tags."
    )
    parser.add_argument("--tag", required=True, help="Current release tag (e.g. v1.2.0)")
    parser.add_argument("--mod-name", required=True, help="Mod display name (e.g. POSnet)")
    parser.add_argument("--repository", required=True, help="GitHub repository (owner/repo)")
    parser.add_argument("--subtitle", default=None, help="Optional release subtitle")
    parser.add_argument("--md-output", default=None, help="Path to write Markdown release notes")
    parser.add_argument("--bbcode-output", default=None, help="Path to write BBCode changelog block")
    parser.add_argument("--bbcode-prepend", default=None,
                        help="Path to existing BBCode file to prepend the new block to")
    parser.add_argument("--title-output", default=None, help="Path to write release title")
    args = parser.parse_args()

    tag = args.tag

    # Find previous tag
    prev_tag = find_previous_tag(tag)
    if prev_tag:
        from_ref = prev_tag
        print(f"  Previous tag: {prev_tag}")
    else:
        from_ref = get_root_commit()
        print(f"  No previous tag found — using root commit: {from_ref[:7]}")

    # Collect and process commits
    commits = collect_commits(from_ref, tag)
    print(f"  Commits found: {len(commits)}")

    groups = group_commits(commits)
    total_entries = sum(len(v) for v in groups.values())
    print(f"  Changelog entries: {total_entries} (after filtering)")

    if total_entries == 0:
        print("  Warning: No changelog entries — outputs will be minimal")

    # Detect subtitle
    subtitle = detect_subtitle(tag, args.subtitle)
    if subtitle:
        print(f"  Subtitle: {subtitle}")

    # Load dependencies
    dependencies = load_dependencies(".")

    # Generate outputs
    if args.md_output:
        md = generate_markdown(tag, subtitle, groups, args.repository, prev_tag, dependencies)
        Path(args.md_output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.md_output).write_text(md, encoding="utf-8")
        print(f"  Markdown written to {args.md_output}")

    if args.bbcode_output:
        bbcode = generate_bbcode(tag, subtitle, groups)
        Path(args.bbcode_output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.bbcode_output).write_text(bbcode, encoding="utf-8")
        print(f"  BBCode written to {args.bbcode_output}")

    if args.bbcode_prepend:
        bbcode = generate_bbcode(tag, subtitle, groups)
        prepend_bbcode(bbcode, args.bbcode_prepend)
        print(f"  BBCode prepended to {args.bbcode_prepend}")

    if args.title_output:
        title = generate_title(args.mod_name, tag, subtitle)
        Path(args.title_output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.title_output).write_text(title, encoding="utf-8")
        print(f"  Title written to {args.title_output}")

    # Summary
    title = generate_title(args.mod_name, tag, subtitle)
    print(f"\n  Release: {title}")
    for cat in CATEGORY_ORDER:
        count = len(groups.get(cat, []))
        if count:
            print(f"    {cat}: {count}")


if __name__ == "__main__":
    main()
