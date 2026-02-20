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

# Changelog (PhobosLib)

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

## [1.9.1] - 2026-02-20

### Fixed
- **LazyStamp Lua 5.1 compatibility** — `goto continue` syntax caused silent parse failure in PZ's Kahlua VM (Lua 5.1). Replaced with boolean flag pattern. The entire file failed to load, preventing all lazy stamper registrations.
- **LazyStamp ConditionMax scaling** — stampValue was set as raw integer (e.g. 99) regardless of item's ConditionMax. Now scales: `math.floor(value / 100 * maxCond + 0.5)`. Critical for FluidContainer items whose ConditionMax may differ from 100.
- **Migration skip notification suppressed** — Incompatible version handler's "skip" policy no longer generates a notification entry, avoiding confusing "Version policy: skip" messages on every game load for downgrade scenarios.
- **Tooltip diagnostic logging removed** — Cleaned up debug `_diagSeen` tracking and DIAG print statements from `PhobosLib_Tooltip.lua`.

## [1.9.0] - 2026-02-20

### Added
- **PhobosLib_Migrate** (shared/) — Generic versioned migration framework for save upgrades
  - `compareVersions(v1, v2)` — Semver comparison, returns -1/0/1
  - `getInstalledVersion(modId)` — Read mod version from world modData (nil for first install)
  - `setInstalledVersion(modId, version)` — Write mod version to world modData
  - `registerMigration(modId, from, to, fn, label)` — Register a versioned migration function. The `from` parameter is retained for documentation/readability but does not gate execution; all migrations where `installed < to` run automatically.
  - `runMigrations(modId, currentVersion, players)` — Execute pending migrations with world modData guards; skips on first install, idempotent on reload. Three outcomes: normal (run pending), recovery (reset poisoned saves), incompatible (invoke handler).
  - `registerIncompatibleHandler(modId, handler)` — Register a callback for incompatible version states (downgrade or invalid version string). Handler receives `{modId, installed, currentVersion, reason, guardCount}` and returns a policy: `"skip"` (stamp, no migrations), `"reset"` (treat as 0.0.0, run all), or `"abort"` (do nothing). Sensible defaults used when no handler is registered.
  - `notifyMigrationResult(player, modId, result)` — Send migration result to client via sendServerCommand (now includes optional `reason` field)
- **PhobosLib_Tooltip** (client/) — Generic tooltip line appender for item tooltips
  - `registerTooltipProvider(modulePrefix, provider)` — Register a callback that appends coloured text lines below the vanilla item tooltip for items matching a module prefix. The provider receives the hovered item and returns an array of `{text, r, g, b}` line tables (or nil to skip). Multiple providers can match the same item; lines are concatenated in registration order.
  - Hooks `ISToolTipInv.render()` once on first registration. Uses a full render replacement that replicates the vanilla render flow with expanded dimensions for provider lines. For items with no matching providers, delegates to the original render unchanged. Entire render block is pcall-wrapped for B42 API resilience.
- **PhobosLib_LazyStamp** (client/) — Lazy container condition stamper
  - `registerLazyConditionStamp(modulePrefix, stampValue, guardFunc)` — Register a stamper that sets item condition on unstamped items (condition == ConditionMax) matching a module prefix whenever the player opens or views a container. Useful for mods that repurpose item condition as a metadata channel (purity, charge level, etc.) and need to cover items in world containers that server-side migrations cannot reach.
  - Hooks `Events.OnRefreshInventoryWindowContainers` once on first registration. Runs only at `"end"` stage when all containers are finalized. Optional guard function controls when stamping is active (e.g. sandbox option checks).

### Fixed
- **Migration framework skipped pre-framework upgrades** — `PhobosLib.runMigrations()` treated `nil` installed version as "first install" and skipped all migrations. Fix: treat `nil` as `"0.0.0"` so all registered migrations run.
- **Recover saves poisoned by early migration bug** — Saves that loaded with the initial migration framework had version stamped without migrations running. Fix: when version is stamped but no migration guard keys exist, reset to `"0.0.0"` so all migrations re-run.

## [1.7.1] - 2026-02-20

### Fixed
- **Fluid validation API** — `_fluidExists()` in PhobosLib_Validate was calling `ScriptManager.instance:getFluid()`, which does not exist in B42. Replaced with `Fluid.Get(fluidName)` (the correct B42 API). This caused 9 `RuntimeException: Object tried to call nil` stack traces during OnGameStart validation and false "MISSING FLUID" warnings for all registered fluids (including vanilla Water).

## [1.7.0] - 2026-02-19

### Added
- **PhobosLib_Trading** (shared/) — Generic wrapper for the Dynamic Trading mod API
  - `isDynamicTradingActive()` — Lazy runtime detection of DynamicTradingCommon
  - `registerTradeTag(tag, data)` — Register custom price/rarity tags
  - `registerTradeArchetype(id, data)` — Register NPC trader archetypes
  - `registerTradeItems(list)` — Batch item registration for NPC trading
  - `registerTradeItem(uniqueID, data)` — Single item registration
  - All functions are no-ops when DynamicTrading is not installed; all DT calls are pcall-wrapped for mid-save safety

## [1.6.0] - 2026-02-19

### Added
- **Neat Crafting compatibility** — `PhobosLib_RecipeFilter` now hooks `NC_FilterBar:shouldIncludeRecipe()` when the Neat Crafting mod is installed. Neat Crafting replaces the vanilla crafting window entirely, so the vanilla `ISRecipeScrollingListBox:addGroup()` override was never called. The hook is installed immediately if Neat Crafting loads first, or deferred via `Events.OnGameStart` as a fallback.

### Fixed
- **Recipe filters now work with Neat Crafting** — Root cause: Neat Crafting overrides `ISEntityUI.OpenHandcraftWindow()` and substitutes its own `NC_HandcraftWindow` / `NC_RecipeList_Panel` classes, bypassing the vanilla `ISRecipeScrollingListBox` entirely. PhobosLib now supports three code paths: vanilla list view, vanilla grid view, and Neat Crafting's `NC_FilterBar`.

## [1.5.1] - 2026-02-19

### Fixed
- **Recipe filter load order** — `PhobosLib_RecipeFilter.lua` now explicitly requires `Entity/ISUI/CraftRecipe/ISRecipeScrollingListBox` and `Entity/ISUI/CraftRecipe/ISTiledIconPanel` before overriding them. Previously only the parent class `ISScrollingListBox` was required, causing the vanilla subclasses to either not exist yet (silent nil crash) or load afterward (stomping the overrides). This resulted in zero console output and no recipe filtering.

## [1.5.0] - 2026-02-19

### Added
- **PhobosLib_RecipeFilter** (client/) — Crafting menu recipe visibility filter
  - `registerRecipeFilter(recipeName, filterFunc)` — Register a filter function for a single recipe; return true to show, false to hide
  - `registerRecipeFilters(filterTable)` — Bulk-register from `{ [name] = func }` table
  - Overrides `ISRecipeScrollingListBox:addGroup()` and `ISTiledIconPanel:setDataList()` to inject filter checks alongside vanilla `getOnAddToMenu()`
  - Fills a gap in B42: `craftRecipe` `OnTest` is a **server-side execution gate**, not a UI visibility gate; `getOnAddToMenu()` only works for entity building recipes

### Deprecated
- **`createCallbackTable(name)`** in PhobosLib_Sandbox — craftRecipe OnTest is an execution gate, not a visibility gate; use `registerRecipeFilter()` instead
- **`registerOnTest(tableName, funcName, func)`** in PhobosLib_Sandbox — same reason; functions still work but log deprecation warnings

## [1.4.2] - 2026-02-19

### Added
- **`createCallbackTable(name)`** in PhobosLib_Sandbox — Creates (or retrieves) a named global Lua callback table; PZ's built-in tables like `RecipeCodeOnTest` are Java-exposed and invisible to `callLuaBool()` when extended from Lua; use this to create mod-owned tables the engine can resolve
- **`registerOnTest(tableName, funcName, func)`** in PhobosLib_Sandbox — Convenience wrapper that creates the global table and registers a single OnTest callback; returns the fully-qualified `"TableName.funcName"` string for recipe script references

## [1.4.1] - 2026-02-19

### Added
- **`consumeSandboxFlag(modId, varName)`** in PhobosLib_Sandbox — Sets sandbox variable to false AND records in world modData for persistence across restarts; used for one-shot sandbox options that must stay cleared
- **`reapplyConsumedFlags()`** in PhobosLib_Sandbox — OnGameStart hook that re-applies consumed flags from world modData to SandboxVars, ensuring one-shot options remain cleared after restart

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
