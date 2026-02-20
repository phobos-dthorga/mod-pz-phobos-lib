<!--
  ________________________________________________________________________
 / Copyright (c) 2026 Phobos A. D'thorga                                \
 |                                                                        |
 |           /\_/\                                                         |
 |         =/ o o \=    Phobos' PZ Modding                                |
 |          (  V  )     All rights reserved.                              |
 |     /\  / \   / \                                                      |
 |    /  \/   '-'   \   This source code is part of the Phobos            |
 |   /  /  \  ^  /\  \  mod suite for Project Zomboid (Build 42).         |
 |  (__/    \_/ \/  \__)                                                  |
 |     |   | |  | |     Unauthorised copying, modification, or            |
 |     |___|_|  |_|     distribution of this file is prohibited.          |
 |                                                                        |
 \________________________________________________________________________/
-->

# Contributing to PhobosLib

Thanks for contributing! PhobosLib is a shared dependency library, so stability and compatibility matter more than feature quantity.

## Principles
- **Backwards compatibility first** (PhobosLib is an API)
- **Defensive coding** (pcall / nil guards / probe methods)
- **No mod-specific balance** (keep utilities generic)
- **Small PRs** (one helper/fix per PR when possible)

## What’s welcome
- Bug fixes, crash fixes
- New small utilities that reduce repeated code in mods
- API resilience wrappers (safe calls, method probing)
- Docs/examples for how to use the library
- Optional integrations that are runtime-detected (do not hard-require other mods)

## What to avoid
- Breaking existing function names/signatures without a migration path
- Adding hard dependencies on other mods
- Large refactors that change behavior without strong justification

## Versioning & API surface
Treat these as public/stable:
- Module/table names
- Function names
- Argument order and return types
- Any documented behavior

If you need to change any of the above:
1) explain why
2) include migration notes
3) consider keeping a compatibility shim

## Testing checklist (minimum)
- Game boots to main menu
- No new errors in `console.txt`
- Any new helper has a short usage example in the PR description (or docs)

## Submitting a PR
1. Fork the repo
2. Create a branch:
   - `fix/...` `feat/...` `docs/...`
3. Keep commits descriptive (what + why)
4. Open a PR describing:
   - what problem it solves
   - how you tested
   - any compatibility notes

Thank you — stable foundations make grand mods possible.
