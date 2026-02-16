# Changelog (PhobosLib)

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

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
