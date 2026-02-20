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

# PhobosLib

**Version:** 1.9.0 | **Requires:** Project Zomboid Build 42.14.0+

> **Players:** Subscribe on [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3668598865) — this mod is required by [Phobos' Chemistry Pathways](https://steamcommunity.com/sharedfiles/filedetails/?id=3668197831).
>
> **Modders & Developers:** Full API reference in [docs/](docs/). Bug reports and feature requests via [GitHub Issues](https://github.com/phobos-dthorga/mod-pz-phobos-lib/issues).

A shared utility library for Project Zomboid mods (Build 42 focused).

**Used by:** [PhobosChemistryPathways](https://github.com/phobos-dthorga/mod-pz-chemistry-pathways) ([Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3668197831)) — 154-recipe chemistry suite

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
| **PhobosLib_Sandbox** | Safe sandbox variable access with defaults, runtime mod detection, yield multiplier application, persistent one-shot flag consumption, mod-owned callback table creation for OnTest/OnCreate |
| **PhobosLib_Quality** | Generic quality/purity tracking: 0-100 scoring, tier lookup, equipment factors, severity scaling, yield penalties |
| **PhobosLib_Hazard** | PPE detection, respiratory protection assessment, mask filter degradation, EHR disease dispatch with vanilla stat fallback |
| **PhobosLib_Skill** | Perk existence checks, safe XP queries and awards, one-shot XP mirroring, persistent cross-skill XP mirror registration via Events.AddXP |
| **PhobosLib_Reset** | Generic inventory/recipe/skill reset utilities: deep inventory traversal, modData stripping, recipe removal, XP reset, item removal by module |
| **PhobosLib_Validate** | Startup dependency validation: register expected items/fluids/perks at load time, validate during OnGameStart, log missing entries with requesting mod ID |
| **PhobosLib_Trading** | Generic wrapper for Dynamic Trading mod API: lazy runtime detection, custom tag/archetype/item registration, batch item registration — all functions are no-ops when DynamicTrading is not installed; all DT calls are pcall-wrapped for mid-save safety |
| **PhobosLib_Migrate** | Versioned save migration framework: semver comparison, version tracking in world modData, migration registration with guard keys, incompatible version handler with skip/reset/abort policies, idempotent execution — mods register migration functions that run once per version upgrade |
| **PhobosLib_RecipeFilter** | *(client)* Crafting menu recipe visibility filter: register filter functions to hide/show `craftRecipe` entries based on sandbox settings or runtime conditions. Supports vanilla list view, vanilla grid view, and Neat Crafting mod compatibility |
| **PhobosLib_Tooltip** | *(client)* Generic tooltip line appender: register provider callbacks that append coloured text lines below the vanilla item tooltip for matching items. Uses full render replacement of `ISToolTipInv.render()` with expanded dimensions |
| **PhobosLib_LazyStamp** | *(client)* Lazy container condition stamper: register stampers that set item condition on unstamped items when the player opens a container. Useful for mods that repurpose item condition as a metadata channel (purity, charge level) |

Usage: `require "PhobosLib"` loads all 11 shared modules into the global `PhobosLib` table. The 3 client-side modules (RecipeFilter, Tooltip, LazyStamp) are loaded automatically by PZ from `client/`.

## Intended usage
- As a dependency: your mod can require PhobosLib and call its helpers.
- As a vendored snippet source: small snippets may be copied with attribution, but depending on the library is preferred.

## Stability promise
Public functions in PhobosLib should be treated as API surface. Changes should:
- avoid breaking signatures
- remain backwards compatible where possible
- include migration notes when breaking changes are unavoidable

## Documentation

- [Module Overview & API Reference](docs/diagrams/module-overview.md) — All 14 modules (11 shared + 3 client) with function signatures, parameters, and descriptions

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
- [ ] Recipe filters work: `[PhobosLib:RecipeFilter]` log lines confirm UI overrides installed (vanilla or Neat Crafting)
- [ ] Tooltip providers work: `[PhobosLib:Tooltip]` log line confirms ISToolTipInv.render hook installed; hover over registered items to verify extra lines appear
- [ ] Lazy stamper works: `[PhobosLib:LazyStamp]` log line confirms OnRefreshInventoryWindowContainers hook installed
- [ ] Migration framework works: `[PhobosLib:Migrate]` log lines show version check and migration execution on game start
- [ ] No `nil` or `NullPointerException` errors referencing PhobosLib in logs

## Release notes
- See CHANGELOG.md
- See VERSIONING.md
