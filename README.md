# PhobosLib

**Version:** 1.4.0 | **Requires:** Project Zomboid Build 42.14.0+

> **Players:** Subscribe on [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3668598865) — this mod is required by [Phobos' Chemistry Pathways](https://steamcommunity.com/sharedfiles/filedetails/?id=3668197831).
>
> **Modders & Developers:** Full API reference in [docs/](docs/). Bug reports and feature requests via [GitHub Issues](https://github.com/phobos-dthorga/mod-pz-phobos-lib/issues).

A shared utility library for Project Zomboid mods (Build 42 focused).

**Used by:** [PhobosChemistryPathways](https://github.com/phobos-dthorga/mod-pz-chemistry-pathways) ([Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3668197831)) — 150-recipe chemistry suite

## Goals
- Provide stable, reusable helpers (sandbox vars, API probing, world scan, fluid helpers, etc.)
- Reduce duplicated Lua glue code across mods
- Improve resilience to minor B42 API changes through safe wrappers

## Modules

| Module | Description |
|--------|-------------|
| **PhobosLib_Util** | General-purpose utilities: safe method calling, API probing, keyword-based item search, modData helpers, player speech bubbles |
| **PhobosLib_Fluid** | Build 42 fluid container helpers with multi-strategy API fallbacks for add/drain/query operations |
| **PhobosLib_World** | World-scanning: tile iteration, object keyword search, generator detection, vehicle proximity checks |
| **PhobosLib_Sandbox** | Safe sandbox variable access with defaults, runtime mod detection, yield multiplier application |
| **PhobosLib_Quality** | Generic quality/purity tracking: 0-100 scoring, tier lookup, equipment factors, severity scaling, yield penalties |
| **PhobosLib_Hazard** | PPE detection, respiratory protection assessment, mask filter degradation, EHR disease dispatch with vanilla stat fallback |
| **PhobosLib_Skill** | Perk existence checks, safe XP queries and awards, one-shot XP mirroring, persistent cross-skill XP mirror registration via Events.AddXP |
| **PhobosLib_Reset** | Generic inventory/recipe/skill reset utilities: deep inventory traversal, modData stripping, recipe removal, XP reset, item removal by module |
| **PhobosLib_Validate** | Startup dependency validation: register expected items/fluids/perks at load time, validate during OnGameStart, log missing entries with requesting mod ID |

Usage: `require "PhobosLib"` loads all modules into the global `PhobosLib` table.

## Intended usage
- As a dependency: your mod can require PhobosLib and call its helpers.
- As a vendored snippet source: small snippets may be copied with attribution, but depending on the library is preferred.

## Stability promise
Public functions in PhobosLib should be treated as API surface. Changes should:
- avoid breaking signatures
- remain backwards compatible where possible
- include migration notes when breaking changes are unavoidable

## Documentation

- [Module Overview & API Reference](docs/diagrams/module-overview.md) — All 8 modules with function signatures, parameters, and descriptions

See [docs/README.md](docs/README.md) for the full index.

## Files to read
- LICENSE
- PROJECT_IDENTITY.md
- MODDING_PERMISSION.md
- CONTRIBUTING.md

## Verification Checklist

After each intermediate or major version bump, verify:

- [ ] All `PhobosLib_*.lua` modules load without errors in `console.txt`
- [ ] `[PhobosLib:Validate]` log lines appear when dependent mods register expectations
- [ ] `PhobosLib.perkExists()` correctly returns true/false for known/unknown perks
- [ ] `PhobosLib.isModActive()` correctly detects active mods
- [ ] World modData strip/get functions work (test via EPR cleanup or manual)
- [ ] No `nil` or `NullPointerException` errors referencing PhobosLib in logs

## Release notes
- See CHANGELOG.md
- See VERSIONING.md
