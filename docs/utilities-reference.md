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

# PhobosLib Utilities Reference

Utility functions available in `PhobosLib_Util.lua` for use across all Phobos mods. Covers math helpers, table transforms, filtering, location formatting, infrastructure utilities, recipe helpers, text composition, and discovery/selection tools.

For other PhobosLib API documentation, see: [error-handling.md](error-handling.md), [data-systems-reference.md](data-systems-reference.md), [ui-reference.md](ui-reference.md)

---

## Math & Table Utilities

PhobosLib provides generic utilities for numeric operations and table transforms. Consumer mods should use these instead of local reimplementations.

### `PhobosLib.clamp(value, min, max)` -> number
Clamp a numeric value to [min, max]. Used extensively in simulation formulas, price bounds, and risk calculations.

### `PhobosLib.lerp(a, b, t)` -> number
Linear interpolation between `a` (t=0) and `b` (t=1). `t` is not clamped -- values outside 0..1 extrapolate.

### `PhobosLib.randFloat(min, max)` -> number
Generate a random float in [min, max) using `ZombRand(10000)` for precision. Deterministic within PZ's RNG seed.

### `PhobosLib.round(value, decimals)` -> number
Round to `decimals` decimal places (default 0). Uses the `floor(x * mult + 0.5) / mult` pattern.

### `PhobosLib.approach(current, target, rate)` -> number
Smoothly approach a target value. Formula: `current + (target - current) * rate`. Rate 0.0 = no change, 1.0 = instant snap. Used for natural drift (pressure decay, stock replenishment) in simulation loops.

### `PhobosLib.map(tbl, fn)` -> table
Transform each element of an array-style table. `fn(value, index)` returns the new value. Returns a new table.

### `PhobosLib.filter(tbl, predicate)` -> table
Keep elements where `predicate(value, index)` returns true. Returns a new table.

---

## Field-Based Filtering

### `PhobosLib.filterByField(array, fieldName, value)` -> table[]

Filter an array of tables by field equality. Returns a new array containing only entries where `entry[fieldName] == value`. Returns `{}` on nil input.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `array` | table | Array of tables to filter |
| `fieldName` | string | Field name to check on each entry |
| `value` | any | Value to match (equality check) |

**Returns:** New array containing only matching entries (never nil).

**Usage -- filter agents by behaviour:**

```lua
local allAgents = registry:getAll()
local traders = PhobosLib.filterByField(allAgents, "behaviour", "trader")
-- traders contains only entries where entry.behaviour == "trader"

-- Safe on nil input
local empty = PhobosLib.filterByField(nil, "id", "foo")  -- returns {}
```

---

## Player Location Formatting

### `PhobosLib.formatPlayerLocation(player, opts)` -> string

Combines a street address (via `PhobosLib_Address`) and the current room name into a single human-readable location string. Useful for log messages, UI labels, mission descriptions, and any context where a player's position needs to be displayed as text.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `player` | IsoPlayer | The player whose location to format |
| `opts` | table (optional) | Options table. Supported fields: `fallback` (string) -- text returned when no location can be determined |

**Format priority:**

1. **Street + valid room** -- `"423 Main Street (Kitchen)"`
2. **Street only** -- `"423 Main Street"`
3. **Valid room only** -- `"Kitchen"` (title-cased)
4. **Fallback** -- `opts.fallback` or `"Unknown Location"` if no fallback provided

Room names shorter than 2 characters are filtered out.

**Example usage:**

```lua
local loc = PhobosLib.formatPlayerLocation(player, { fallback = "Unknown" })
-- "423 Main Street (Kitchen)" | "423 Main Street" | "Kitchen" | "Unknown"
```

---

## Infrastructure Utilities

General-purpose helpers for distance calculations, inventory manipulation, and requirement checking. These reduce boilerplate in consumer mods that need spatial logic, item grants/consumes, or pre-condition validation.

### `PhobosLib.manhattanDistance(x1, y1, z1, x2, y2, z2, zPenalty)` -> number

Compute Manhattan distance between two 3D points with an optional Z-level penalty multiplier.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `x1` | number | Source X coordinate |
| `y1` | number | Source Y coordinate |
| `z1` | number | Source Z coordinate (floor level) |
| `x2` | number | Target X coordinate |
| `y2` | number | Target Y coordinate |
| `z2` | number | Target Z coordinate (floor level) |
| `zPenalty` | number\|nil | Extra cost per Z-level difference (default 1) |

**Returns:** Total Manhattan distance including Z penalty.

**Formula:** `|x2-x1| + |y2-y1| + (|z2-z1| * zPenalty)`

### `PhobosLib.consumeItems(player, fullType, count)` -> number

Consume N items of a given type from the player's main inventory. Removes items one at a time via `getFirstType`/`Remove` loop.

**Returns:** Actual number consumed (may be less than `count` if inventory is short).

### `PhobosLib.grantItems(player, fullType, count)` -> number

Grant N items of a given type to the player's main inventory.

**Returns:** Actual number granted.

### `PhobosLib.checkRequirements(player, opts)` -> table

Check whether a player meets a set of requirements (items, tools, skill level). Returns a structured result suitable for tooltip generation or UI gating.

**`opts` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `items` | table\|nil | `{fullType, count}` -- item type and quantity needed |
| `tools` | table\|nil | Array of tool fullType strings that must be in inventory |
| `minSkill` | number\|nil | Minimum skill level required |
| `skillType` | string\|nil | PZ perk name (e.g. `"Electrical"`) |

**Returns:** Result table with fields: `ok`, `missingItems`, `missingTools`, `skillTooLow`, `skillHave`, `skillNeed`.

### `PhobosLib.getPlayerPerkLevel(player, perkId)` -> number

Returns the player's level in a given perk, or 0 on any failure. Safe wrapper that resolves the perk via `Perks.FromString` and reads the level via `player:getPerkLevel`, with both calls protected by `safecall`.

---

## Recipe & Configuration Utilities

General-purpose helpers for item lookup, configuration resolution, and threshold-based tier matching.

### `PhobosLib.findItemInList(items, fullType)` -> item, index

Find the first item in a list matching the given full type. Uses `PhobosLib.iterateItems()` internally for B42 ArrayList/table safety.

**Returns:** `(item, index)` for the first match, or `(nil, nil)` if not found.

### `PhobosLib.getConfigurable(module, methodName, fallback)` -> any

Safely retrieve a configurable value from a module by calling a named getter method. Returns the fallback if the module is nil, the method does not exist, the call fails, or the result is nil.

### `PhobosLib.resolveThresholdTier(value, tiers, default)` -> any

Resolve a numeric value against a sorted threshold tier list. Walks tiers in order; returns the `result` of the first tier where `value <= tier.threshold`. Returns `default` if no tier matches. Nil-safe on both `value` and `tiers`.

**Usage -- map signal strength to quality label:**

```lua
local SIGNAL_TIERS = {
    { threshold = 0.2, result = "critical" },
    { threshold = 0.5, result = "weak" },
    { threshold = 0.8, result = "moderate" },
    { threshold = 1.0, result = "strong" },
}

local quality = PhobosLib.resolveThresholdTier(signalStrength, SIGNAL_TIERS, "unknown")
```

---

## Text Compositor

Utilities for template-based text generation with weighted random selection, conditional filtering, and anti-repetition. Designed for procedural content systems (mission briefings, market reports, NPC dialogue).

### `PhobosLib.resolveTokens(text, ctx)` -> string

Replace `{key}` placeholders in a template string with values from a context table. Placeholders whose keys are not found in `ctx` are left unreplaced. Nil-safe on both params.

### `PhobosLib.conditionsPass(entry, ctx)` -> boolean

Check if an entry's conditions match a context. Supports `minDifficulty`, `maxDifficulty` (numeric comparisons), and arbitrary keys where the condition value is an array of allowed values (membership check).

### `PhobosLib.pickWeighted(entries, ctx)` -> table|nil

Select a random entry from a weighted pool. Filters entries by `conditionsPass`, sums remaining weights, picks via `ZombRand(totalWeight)` and walks cumulative weights.

### `PhobosLib.avoidRecent(entryId, history, maxSize)` -> boolean

Anti-repetition guard. Returns `false` if `entryId` is already in the `history` array. Otherwise appends `entryId` to `history`, trims to `maxSize`, and returns `true`.

---

## Discovery & Selection Utilities

Functions for random pool selection and per-player discovery tracking. Added in v1.61.0.

### `PhobosLib.selectRandomFromPool(pool, count, weightFn)` -> table

Pick N random entries from an array without replacement. If `count >= #pool`, returns a copy of the entire pool. Uses `ZombRand` for PZ determinism. Never modifies the original pool.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `pool` | table\|nil | Array of entries to select from. Nil-safe -- returns `{}` |
| `count` | number | Number of entries to pick |
| `weightFn` | function\|nil | Optional `weightFn(entry)` returning numeric weight (higher = more likely). If nil, equal weight |

**Returns:** New array of selected entries. May be smaller than `count` if the pool is smaller.

**Usage -- select 3 random specimens from a discovery pool:**

```lua
local specimens = PhobosLib.selectRandomFromPool(availableSpecimens, 3)

-- With weighted selection (rarer specimens less likely)
local picks = PhobosLib.selectRandomFromPool(pool, 2, function(entry)
    return entry.rarity == "common" and 5 or 1
end)
```

### `PhobosLib.trackDiscovery(player, namespace, id, metadata)` -> boolean

Track a discovery for a player within a namespace. Uses `PhobosLib.getPlayerModDataTable(player, namespace)` for storage. If the `id` already exists in the namespace table, returns `false` (already discovered). Otherwise stores `metadata` (or `true` if metadata is nil) and returns `true`.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `player` | IsoPlayer | The player to track the discovery for |
| `namespace` | string | ModData sub-table key (e.g. `"PIP_Discoveries"`) |
| `id` | string | Unique identifier for the discovery |
| `metadata` | any\|nil | Data to store alongside the discovery (defaults to `true`) |

**Returns:** `true` if newly discovered, `false` if already known or on nil input.

**Usage -- track a pathology specimen discovery:**

```lua
local isNew = PhobosLib.trackDiscovery(player, "PIP_Discoveries", "specimen_rabies", {
    timestamp = getTimestampMs(),
    source = "field_sample",
})
if isNew then
    PhobosLib.say(player, "New specimen discovered: Rabies")
end
```

### `PhobosLib.isDiscovered(player, namespace, id)` -> boolean

Check whether a discovery has been made for a given player and namespace.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `player` | IsoPlayer | The player to check |
| `namespace` | string | ModData sub-table key |
| `id` | string | Discovery identifier |

**Returns:** `true` if discovered, `false` otherwise or on nil input.

### `PhobosLib.getDiscoveries(player, namespace)` -> table

Get all discoveries for a player within a namespace. Returns the full table (id -> metadata mapping) or `{}` if none exist.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `player` | IsoPlayer | The player to query |
| `namespace` | string | ModData sub-table key |

**Returns:** Table of `{id = metadata}` pairs, or `{}`.

**Usage -- display discovery count:**

```lua
local discoveries = PhobosLib.getDiscoveries(player, "PIP_Discoveries")
local count = 0
for _ in pairs(discoveries) do count = count + 1 end
PhobosLib.say(player, "Specimens discovered: " .. tostring(count))
```

---

## World ModData Utilities

Functions for world-scoped ModData (shared across all players via
`ModData.getOrCreate()`). Auto-persisted with the world save.

### `PhobosLib.getWorldModData(namespace)`

Get or create a world-scoped ModData table by namespace.

| Param | Type | Description |
|-------|------|-------------|
| `namespace` | string | ModData namespace (e.g. `"POSNET"`) |

**Returns:** Table (auto-created if missing).

### `PhobosLib.getWorldModDataTable(namespace, key)`

Get or create a sub-table within a world ModData namespace.

| Param | Type | Description |
|-------|------|-------------|
| `namespace` | string | ModData namespace |
| `key` | string | Sub-table key (e.g. `"EventLog"`) |

**Returns:** Table (auto-created if missing).

### `PhobosLib.appendWorldLog(namespace, key, line)`

Append a newline-delimited line to a string-based log in world ModData.

| Param | Type | Description |
|-------|------|-------------|
| `namespace` | string | ModData namespace |
| `key` | string | Log key (e.g. `"economy_day821"`) |
| `line` | string | Line to append |

### `PhobosLib.getWorldLog(namespace, key)`

Read a string-based log from world ModData.

**Returns:** `string` or `nil`.

### `PhobosLib.clearWorldKey(namespace, key)`

Delete a key from a world ModData namespace (set to `nil`).

**Usage — event log purge:**

```lua
PhobosLib.clearWorldKey("POSNET", "economy_day800")
```
