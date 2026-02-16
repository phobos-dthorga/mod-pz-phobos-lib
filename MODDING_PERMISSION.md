# Modding Permission Notice (PhobosLib)

PhobosLib is intended to be a dependency and shared toolkit for Project Zomboid Build 42 mods.

You may:
- Depend on PhobosLib (required dependency) in your mod
- Vendor/inline small snippets when necessary (with attribution); dependency use is preferred
- Submit PRs adding helpers, fixes, or compatibility improvements
- Publish addons (optional integrations) that extend PhobosLib

You should:
- Prefer runtime detection and defensive coding (pcall / nil guards / probes)
- Keep helpers general-purpose and avoid game-balance opinions
- Maintain backwards compatibility for public functions where feasible

You may NOT:
- Reupload the library unchanged under the same name
- Claim authorship of the original library
- Paywall the original library content
