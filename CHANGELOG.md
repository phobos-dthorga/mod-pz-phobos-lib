# Changelog (PhobosLib)

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

## [1.4.0] - 2026-02-19

### Added
- **PhobosLib_Validate** — Startup dependency validation module
  - `expectItem(modId, fullType)` — Register an expected item dependency
  - `expectFluid(modId, fluidName)` — Register an expected fluid dependency
  - `expectPerk(modId, perkName)` — Register an expected perk dependency
  - `validateDependencies()` — Check all registered dependencies exist; logs missing entries with `[PhobosLib:Validate] [MOD_ID]` prefix for easy triage
  - Mods register expectations at file-load time; single validation call during `OnGameStart` checks everything and returns a structured failure report

## [1.3.0] - 2026-02-19

### Added
- **PhobosLib_Reset** — World modData utilities for mod cleanup
  - `getWorldModDataValue(key, default)` — Read a single value from world modData (`getGameTime():getModData()`) with fallback default
  - `stripWorldModDataKeys(keys)` — Remove one or more keys from world modData; returns count of keys actually removed

## [1.2.0] - 2026-02-18

### Added
- **PhobosLib_Reset** — Generic inventory/recipe/skill reset utilities for mod cleanup systems
  - `iterateInventoryDeep(player, callback)` — Deep inventory traversal including nested containers (bags, backpacks), with visited-set loop guard
  - `stripModDataKey(player, key)` — Remove a specific modData key from all items (deep scan)
  - `forgetRecipesByPrefix(player, prefix)` — Two-pass recipe removal to avoid ConcurrentModificationException
  - `resetPerkXP(player, perkEnum)` — Multi-strategy XP reset (setXP → setPerkLevel → LoseLevel loop)
  - `removeItemsByModule(player, moduleId)` — Remove all items belonging to a module, matching via getModule() or fullType prefix
- **`setSandboxVar(modId, varName, value)`** in PhobosLib_Sandbox — safely set sandbox variable values (used for one-shot option auto-reset)

## [1.1.0] - 2026-02-17

### Added
- **PhobosLib_Skill** — Generic perk/skill utilities for custom skill systems
  - `perkExists(perkName)` — Check whether a named perk exists in the Perks table
  - `getPerkLevel(player, perkEnum)` — Safe wrapper for player perk level query (returns 0 on failure)
  - `addXP(player, perkEnum, amount)` — Safe wrapper for awarding XP (pcall-protected)
  - `getXP(player, perkEnum)` — Safe wrapper for querying current XP total
  - `mirrorXP(player, targetPerkEnum, amount, ratio)` — One-shot XP mirroring (award target perk XP based on source amount × ratio)
  - `registerXPMirror(sourcePerkName, targetPerkName, ratio)` — Register persistent Events.AddXP hook for cross-skill XP mirroring with reentrance guard

## [1.0.0] - 2026-02-17
### Added
- Initial stable release of PhobosLib as a shared utility dependency for Project Zomboid Build 42 mods.
- **PhobosLib_Util** — General-purpose utility functions:
  - `lower()` — Safe lowercase conversion
  - `pcallMethod()` / `probeMethod()` / `probeMethodAny()` — Safe method calling with API probing across PZ build variants
  - `matchesKeywords()` / `findItemByKeywords()` / `findAllItemsByKeywords()` — Keyword-based item search (case-insensitive substring matching on fullType and displayName)
  - `findItemByFullType()` / `findAllItemsByFullType()` — Exact-match item lookup
  - `say()` — Safe player speech bubble wrapper
  - `getItemWeight()` / `getItemUseDelta()` / `setItemUseDelta()` — Safe item property accessors with method probing
  - `getItemCondition()` / `setItemCondition()` — Safe condition get/set
  - `refundItems()` — Re-add consumed recipe inputs to player inventory
  - `getModData()` / `getModDataValue()` / `setModDataValue()` — Safe modData persistence helpers
- **PhobosLib_Fluid** — Build 42 fluid container helpers:
  - `tryGetFluidContainer()` — Probe for fluid container on any item
  - `tryGetCapacity()` / `tryGetAmount()` — Safe fluid level queries
  - `tryAddFluid()` — Multi-strategy fluid addition (4 API fallbacks)
  - `tryDrainFluid()` — Multi-strategy fluid removal (3 API fallbacks)
- **PhobosLib_World** — World-scanning and proximity utilities:
  - `getSquareFromPlayer()` — Safe IsoGridSquare retrieval
  - `scanNearbySquares()` — Tile iteration within radius with early-exit callback
  - `findNearbyObjectByKeywords()` / `findAllNearbyObjectsByKeywords()` — Sprite/name keyword search on world objects
  - `isNearObjectType()` — Boolean proximity check
  - `findNearbyGenerator()` / `findAnyNearbyGenerator()` — Active/any generator detection
  - `findNearbyVehicle()` / `isVehicleRunning()` — Vehicle detection and engine state
- **PhobosLib_Sandbox** — Sandbox variable access and mod detection:
  - `getSandboxVar()` — Safe sandbox variable retrieval with default fallback
  - `isModActive()` — Runtime mod presence detection via `getActivatedMods()`
  - `applyYieldMultiplier()` — Numeric sandbox multiplier with rounding and minimum clamping
- **PhobosLib_Quality** — Generic quality/purity tracking system:
  - `getQuality()` / `setQuality()` — modData-backed 0-100 quality score read/write
  - `getQualityTier()` — Configurable tier lookup with RGB colour mapping
  - `averageInputQuality()` — Weighted averaging across recipe input items
  - `calculateOutputQuality()` — Equipment factor + random variance calculation
  - `randomBaseQuality()` — Source recipe base quality generation
  - `adjustFactorBySeverity()` — Three-tier severity scaling for equipment factors
  - `announceQuality()` — Player speech bubble feedback
  - `getQualityYield()` — Configurable yield multiplier lookup
  - `applyFluidQualityPenalty()` — Drain fluid from containers based on quality
  - `removeExcessItems()` — Remove discrete items for yield penalties
  - `stampAllOutputs()` — Stamp quality on all unstamped items of a type
- **PhobosLib_Hazard** — PPE detection and health hazard dispatch:
  - `findWornItem()` — Scan player worn items for matching types
  - `getRespiratoryProtection()` — Assess mask type, filter status, and protection level
  - `degradeFilterFromInputs()` — Degrade drainable mask filters from recipe inputs
  - `isEHRActive()` — Detect EHR (Extensive Health Rework) mod and disease system
  - `applyHazardEffect()` — Dispatch disease (EHR) or stat penalties (vanilla) with protection scaling
  - `warnHazard()` — Player speech bubble warning
