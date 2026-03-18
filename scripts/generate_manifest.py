#!/usr/bin/env python3
"""Generate a release manifest with dependency declarations.

Called by the release workflow to produce manifest.json, which is
attached to each GitHub Release as a machine-readable metadata file.
"""

import argparse
import json
import os
from datetime import datetime, timezone


def load_dependencies(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("dependencies.json must contain a JSON object")
    return data


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate a release manifest for a Phobos PZ mod."
    )
    parser.add_argument("--name", required=True, help="Mod display name")
    parser.add_argument("--tag", required=True, help="Git tag (e.g. v1.2.3)")
    parser.add_argument("--version", required=True, help="SemVer version (e.g. 1.2.3)")
    parser.add_argument("--channel", required=True, help="Release channel (stable/alpha/beta/rc)")
    parser.add_argument("--game-version", required=True, help="Target game version (e.g. B42)")
    parser.add_argument("--repository", required=True, help="GitHub repository (owner/repo)")
    parser.add_argument("--commit", required=True, help="Full commit SHA")
    parser.add_argument("--output", required=True, help="Output file path")
    parser.add_argument("--dependencies-file", default="dependencies.json",
                        help="Path to dependencies.json (default: repo root)")
    args = parser.parse_args()

    dependencies = load_dependencies(args.dependencies_file)

    manifest = {
        "name": args.name,
        "tag": args.tag,
        "version": args.version,
        "channel": args.channel,
        "gameVersion": args.game_version,
        "repository": args.repository,
        "commit": args.commit,
        "releasedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "dependencies": dependencies,
    }

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    print(f"Manifest written to {args.output}")
    print(f"  Name: {args.name}")
    print(f"  Tag: {args.tag}")
    print(f"  Channel: {args.channel}")
    print(f"  Dependencies: {len(dependencies)}")


if __name__ == "__main__":
    main()
