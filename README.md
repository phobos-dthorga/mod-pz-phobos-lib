# PhobosLib

**Version:** 1.1.0 | **Requires:** Project Zomboid Build 42.13.0+

A shared utility library for Project Zomboid mods (Build 42 focused).

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

- [Module Overview & API Reference](docs/diagrams/module-overview.md) — All 7 modules with function signatures, parameters, and descriptions

See [docs/README.md](docs/README.md) for the full index.

## Files to read
- LICENSE
- PROJECT_IDENTITY.md
- MODDING_PERMISSION.md
- CONTRIBUTING.md

## Release notes
- See CHANGELOG.md
- See VERSIONING.md
