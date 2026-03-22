# PhobosLib Error Handling & Strict Mode

## pcall Classification

All pcall usage in PhobosLib and consumer mods falls into exactly two categories:

| Type | Purpose | Strict mode | Example |
|------|---------|-------------|---------|
| **NECESSARY** | API probing — checking if a method exists across PZ builds | Always wrapped (`pcall`) | `pcall(getDebug)`, `PhobosLib.pcallMethod()`, `PhobosLib.probeMethod()` |
| **DEFENSIVE** | Protecting against edge cases in gameplay logic | Bypassed when strict mode ON (`safecall`) | Inventory iteration, trait lookup, modData access |

## Strict Mode

Enabled via sandbox option **PhobosLib.EnableStrictMode** (default OFF).

When ON, `PhobosLib.safecall()` calls functions directly instead of wrapping them in `pcall`. Errors propagate with full stack traces, making bugs much easier to find.

**Boot phase**: Before `OnGameStart`, strict mode is always OFF. Sandbox vars are unavailable during module loading, so all boot-phase pcalls behave defensively regardless of the setting.

**Console output**: On game start with strict mode enabled:
```
[PhobosLib:Debug] *** STRICT MODE ENABLED — defensive pcalls BYPASSED ***
[PhobosLib:Debug] *** Errors will propagate with full stack traces ***
```

## API Reference

### `PhobosLib.isStrictMode()`
Returns `true` if strict mode is enabled. Use for conditional logic beyond safecall.

### `PhobosLib.safecall(fn, ...)`
Strict-mode-aware pcall replacement. In normal mode, behaves exactly like `pcall(fn, ...)`. In strict mode, calls `fn(...)` directly — errors propagate. Returns `true, <results>` in both modes to match pcall's signature.

### `PhobosLib.safeMethodCall(obj, methodName, ...)`
Strict-mode-aware method call. Like `pcallMethod` but bypassed in strict mode. Returns `false, nil` if obj or method is nil.

### `PhobosLib.pcallMethod(obj, methodName, ...)`
**API probing only.** Always uses raw `pcall`. Used by `probeMethod` and `probeMethodAny`. Never bypassed by strict mode.

## Rules for New Code

1. **New defensive pcalls** MUST use `PhobosLib.safecall(fn, ...)` — never raw `pcall()`.
2. **New defensive method calls** MUST use `PhobosLib.safeMethodCall(obj, method, ...)`.
3. **API probing** (testing if a method exists, trying multiple signatures) keeps raw `pcall()` or `PhobosLib.pcallMethod()`.
4. `PhobosLib.pcallMethod` is reserved for API probing only.

## Migration Pattern

```lua
-- BEFORE (hides bugs):
local ok, result = pcall(function() return obj:riskyMethod(arg) end)

-- AFTER (strict-mode-aware):
local ok, result = PhobosLib.safecall(function() return obj:riskyMethod(arg) end)

-- Or for method calls:
local ok, result = PhobosLib.safeMethodCall(obj, "riskyMethod", arg)
```

## Consumer Mod Adoption

Consumer mods (POSnet, PCP, PIP, etc.) should replace their defensive pcalls with `PhobosLib.safecall()` to get strict-mode awareness. The function accepts exactly the same arguments as `pcall()` — it's a drop-in replacement.

**Do NOT convert**:
- pcalls that probe for optional APIs (e.g., checking if a cross-mod function exists)
- pcalls inside PhobosLib's own `getSandboxVar`/`isModActive` (circular dependency)

## When to Use Strict Mode

- **Development**: Always ON — surfaces hidden errors with full stack traces.
- **Bug reports**: Ask players to enable it and reproduce the crash for better diagnostics.
- **Normal play**: OFF (default) — defensive pcalls protect against edge-case crashes.

## Math & Table Utilities

PhobosLib provides generic utilities for numeric operations and table transforms. Consumer mods should use these instead of local reimplementations.

### `PhobosLib.clamp(value, min, max)` → number
Clamp a numeric value to [min, max]. Used extensively in simulation formulas, price bounds, and risk calculations.

### `PhobosLib.lerp(a, b, t)` → number
Linear interpolation between `a` (t=0) and `b` (t=1). `t` is not clamped — values outside 0..1 extrapolate.

### `PhobosLib.randFloat(min, max)` → number
Generate a random float in [min, max) using `ZombRand(10000)` for precision. Deterministic within PZ's RNG seed.

### `PhobosLib.round(value, decimals)` → number
Round to `decimals` decimal places (default 0). Uses the `floor(x * mult + 0.5) / mult` pattern.

### `PhobosLib.approach(current, target, rate)` → number
Smoothly approach a target value. Formula: `current + (target - current) * rate`. Rate 0.0 = no change, 1.0 = instant snap. Used for natural drift (pressure decay, stock replenishment) in simulation loops.

### `PhobosLib.map(tbl, fn)` → table
Transform each element of an array-style table. `fn(value, index)` returns the new value. Returns a new table.

### `PhobosLib.filter(tbl, predicate)` → table
Keep elements where `predicate(value, index)` returns true. Returns a new table.

## Field-Based Filtering

### `PhobosLib.filterByField(array, fieldName, value)` → table[]

Filter an array of tables by field equality. Returns a new array containing only entries where `entry[fieldName] == value`. Returns `{}` on nil input (§25.6 collection convention).

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `array` | table | Array of tables to filter |
| `fieldName` | string | Field name to check on each entry |
| `value` | any | Value to match (equality check) |

**Returns:** New array containing only matching entries (never nil).

**Usage — filter agents by behaviour:**

```lua
local allAgents = registry:getAll()
local traders = PhobosLib.filterByField(allAgents, "behaviour", "trader")
-- traders contains only entries where entry.behaviour == "trader"

-- Safe on nil input
local empty = PhobosLib.filterByField(nil, "id", "foo")  -- returns {}
```

## Deferred Initialisation & Throttling

### `PhobosLib.lazyInit(initFn)`
- **Parameters:** `initFn` (function) — one-time initialisation function
- **Returns:** Guard function — call before accessing module state
- **Behaviour:** Runs `initFn` exactly once on first call. Subsequent calls are a no-op (single boolean check).
- **Use case:** Defer expensive module initialisation (e.g. iterating all game items) from `OnGameStart` to first access.

```lua
local ensureInit = PhobosLib.lazyInit(function()
    -- expensive one-time setup
end)
function MyModule.getData()
    ensureInit()
    return _data
end
```

### `PhobosLib.throttle(fn, intervalMinutes)`
- **Parameters:** `fn` (function), `intervalMinutes` (number)
- **Returns:** Throttled wrapper function suitable for `Events.EveryOneMinute.Add()`
- **Behaviour:** Executes `fn` immediately on first call, then skips until `intervalMinutes` game-minutes elapse. Tracks time via `getGameTime():getWorldAgeHours()`.
- **Use case:** Reduce frequency of `EveryOneMinute` handlers performing spatial scans.

```lua
Events.EveryOneMinute.Add(PhobosLib.throttle(doExpensiveScan, 5))
```

## Player Location Formatting

### `PhobosLib.formatPlayerLocation(player, opts)` → string

Combines a street address (via `PhobosLib_Address`) and the current room name into a single human-readable location string. Useful for log messages, UI labels, mission descriptions, and any context where a player's position needs to be displayed as text.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `player` | IsoPlayer | The player whose location to format |
| `opts` | table (optional) | Options table. Supported fields: `fallback` (string) — text returned when no location can be determined |

**Format priority:**

The function tries to build the most informative string possible, falling through in order:

1. **Street + valid room** — `"423 Main Street (Kitchen)"`
2. **Street only** — `"423 Main Street"`
3. **Valid room only** — `"Kitchen"` (title-cased)
4. **Fallback** — `opts.fallback` or `"Unknown Location"` if no fallback provided

Room names shorter than 2 characters are filtered out. These typically appear as single-letter artefacts from modded buildings and are not meaningful to the player.

**Internal dependencies:**

- `PhobosLib.getPlayerRoomName()` — retrieves the current room name
- `PhobosLib_Address.resolveAddress()` — resolves the player's street address

**Example usage:**

```lua
local loc = PhobosLib.formatPlayerLocation(player, { fallback = "Unknown" })
-- "423 Main Street (Kitchen)" | "423 Main Street" | "Kitchen" | "Unknown"

-- Without options — defaults to "Unknown Location" when nothing resolves
local loc = PhobosLib.formatPlayerLocation(player)
```

## Chunked File Writing

For large data stores that must be serialised to disk, writing everything in a
single frame causes a visible hitch. PhobosLib provides a chunked writer that
spreads the work across multiple `EveryOneMinute` ticks.

### `PhobosLib.createChunkedWriter(opts)` → writer

Factory. Returns a writer handle used by the other chunked-write functions.

| Option | Type | Description |
|--------|------|-------------|
| `filePath` | string | Destination path passed to `getFileWriter` |
| `chunkSize` | number | Items to serialise per tick |
| `onSerialize` | function(item, fileWriter) | Called once per item — write the item's data |
| `onComplete` | function() | Called after the final chunk is flushed and the file is closed |

### `PhobosLib.startChunkedWrite(writer, source)`

Queue a write operation. `source` is an array-style table of items to
serialise. The writer copies the list internally so the caller may continue
to mutate the original table.

### `PhobosLib.tickChunkedWrite(writer)` → boolean

Process the next chunk (up to `chunkSize` items). Returns `true` when the
entire source has been written and the file has been closed; `false` while
work remains.

### `PhobosLib.isChunkedWriteActive(writer)` → boolean

Returns `true` if the writer has queued items that have not yet been fully
flushed. Useful for preventing overlapping writes.

### Usage example — market data save

```lua
local writer = PhobosLib.createChunkedWriter({
    filePath    = "POSnet/market_prices.txt",
    chunkSize   = 4,
    onSerialize = function(category, fw)
        fw:writeln(category.id .. ";" .. tostring(category.price))
    end,
    onComplete  = function()
        PhobosLib.debug("POS", "[Market]", "Chunked save complete")
    end,
})

-- Start a save (e.g. from an EveryTenMinutes handler)
PhobosLib.startChunkedWrite(writer, allCategories)

-- Tick the writer every game-minute until done
Events.EveryOneMinute.Add(function()
    if PhobosLib.isChunkedWriteActive(writer) then
        PhobosLib.tickChunkedWrite(writer)
    end
end)
```

> **Important:** Callers must call `tickChunkedWrite` each `EveryOneMinute`
> tick while the writer is active. The writer does not register its own event
> handler — ownership of the tick loop stays with the consumer.

---

## Empty-Data Return Convention

Two rules govern what functions return when they have no data:

1. **Functions that compute/aggregate data** (`getSummary`, `getCommoditySummary`,
   `resolveAddress`) MUST return `nil` when input data is empty — never a table
   with nil-valued named fields.
2. **Functions that list/collect items** (`getRecords`, `getNotes`, `getCache`)
   MAY return `{}` (empty array) — downstream code handles via `#result == 0`
   or `ipairs()`.

**Anti-pattern (BAD):**

```lua
-- BAD: returns non-nil table with nil fields — callers treat as valid data
local summary = { low = nil, high = nil, avg = nil, sourceCount = 0 }
if #records == 0 then return summary end
```

**Correct (GOOD):**

```lua
-- GOOD: forces callers to nil-check before field access
if #records == 0 then return nil end
```

**Why:** In Kahlua, passing `nil` from a named field into string concatenation
or arithmetic triggers a Java `RuntimeException` that `pcall`/`safecall` cannot
catch, causing a silent JVM crash (CTD with no stack trace).

**Implementation references:**
`POS_MarketDatabase.getSummary`, `PhobosLib_Address.resolveAddress`,
`PN_ChannelRegistry.getMutedSet`

---

## Logging Levels

PhobosLib provides three log levels, each with different gating requirements:

| Level | Function | Gate | Use case |
|-------|----------|------|----------|
| **INFO** | `print()` | Always printed | Startup banners, one-time status messages |
| **DEBUG** | `PhobosLib.debug(modId, tag, msg)` | Sandbox `EnableDebugLogging` only | Config values, feature gates, callback entry/exit, calculation parameters |
| **TRACE** | `PhobosLib.trace(modId, tag, msg)` | Sandbox `EnableDebugLogging` **AND** PZ `-debug` flag | Per-tick iteration, per-item detail — very verbose, developers only |

### Key distinction

`PhobosLib.debug()` does **NOT** depend on PZ's `-debug` startup flag. It only requires the per-mod sandbox option `SandboxVars.<modId>.EnableDebugLogging = true`. This means players and mod authors can enable debug output without the `-debug` flag, which is important because the `-debug` flag can cause issues with certain third-party mods.

`PhobosLib.trace()` requires **both** the sandbox option **and** the `-debug` flag. This double gate keeps extremely verbose output (per-tick, per-item loops) from flooding the console during normal debug sessions.

### Checking log levels

```lua
PhobosLib.isDebugEnabled(modId)  -- true if sandbox EnableDebugLogging is ON
PhobosLib.isTraceEnabled(modId)  -- true if debug ON + PZ -debug flag active
```

Results are cached after first read — sandbox vars don't change mid-session.

### Boot-phase buffering

Before `OnGameStart`, sandbox vars are unavailable. Calls to `debug()` and `trace()` during module loading are **buffered** in memory. Once `OnGameStart` fires:

1. The sandbox option is read and cached.
2. PZ's `-debug` flag is probed via `pcall(getDebug)`.
3. Buffered messages are flushed (printed) if their level is enabled, or silently discarded.

This means you can safely call `PhobosLib.debug()` from top-level module code — nothing crashes, and the message appears if logging is enabled.

### Per-mod sandbox option

Each Phobos mod defines its own `EnableDebugLogging` sandbox boolean. The `modId` parameter (first argument to `debug()`/`trace()`) selects which mod's toggle to check:

```lua
-- Only prints if SandboxVars.POS.EnableDebugLogging == true
PhobosLib.debug("POS", "[POS:Market]", "Scanning 16 categories")

-- Only prints if SandboxVars.PhobosLib.EnableDebugLogging == true
PhobosLib.debug("PhobosLib", _TAG, "Strict mode: " .. tostring(_strictMode))
```

### Enabling debug output (for players / testers)

1. Open sandbox settings (Host → Settings → Sandbox Options).
2. Find the mod's page (e.g., "PhobosLib", "POSnet", "PCP").
3. Set **Enable Debug Logging** to `true`.
4. Restart the game (sandbox vars are read once at game start).
5. Check the PZ console (`~` key) or `console.txt` for `[DEBUG]` lines.

---

## Schema Validation, Registry & Data Loader

PhobosLib provides a three-module data-pack architecture for validated, registry-driven content systems. Any mod can define schemas, create registries, and load data-only Lua definition files through this pipeline.

### Schema Validation (`PhobosLib_Schema`)

Validate any Lua table against a declarative schema definition.

**Schema format:**

```lua
local mySchema = {
    schemaVersion = 1,
    fields = {
        id   = { type = "string", required = true },
        name = { type = "string", required = true },
        behaviour = { type = "string", required = true, enum = { "trader", "wholesaler" } },
        tuning = { type = "table", required = true, fields = {
            reliability = { type = "number", min = 0, max = 1, default = 0.5 },
            volatility  = { type = "number", min = 0, max = 1, default = 0.3 },
        }},
        tags    = { type = "array" },
        enabled = { type = "boolean", default = true },
    }
}
```

**Supported types:** `string`, `number`, `boolean`, `table` (with optional nested `fields`), `array`

**Supported constraints:**

| Constraint | Applies to | Purpose |
|------------|-----------|---------|
| `required` | all | Field must be present |
| `default` | all | Value to fill when field is nil |
| `min` / `max` | number | Numeric range check |
| `enum` | string | Set of valid values |
| `minLength` | string | Minimum string length |
| `fields` | table | Nested sub-schema |

**Functions:**

```lua
-- Validate data against schema. Returns ok + error array.
local ok, errors = PhobosLib.validateSchema(data, schema)
-- errors: { {field="tuning.volatility", message="must be at most 1.0", value=1.5}, ... }

-- Apply default values for missing optional fields (mutates in place).
PhobosLib.applyDefaults(data, schema)

-- Format errors into human-readable log strings.
local lines = PhobosLib.formatValidationErrors(errors, "[MyMod]")
-- { "[MyMod] tuning.volatility: must be at most 1.0 (got: 1.5)" }
```

### Registry (`PhobosLib_Registry`)

Create typed registries that validate definitions on registration and provide safe lookup.

```lua
local registry = PhobosLib.createRegistry({
    name = "Archetypes",           -- for log messages
    schema = mySchema,             -- PhobosLib_Schema definition
    idField = "id",                -- unique key field (default "id")
    allowOverwrite = false,        -- reject duplicate IDs (default false)
    tag = "[MyMod:Archetype]",     -- debug log prefix
})
```

**Instance methods:**

| Method | Returns | Description |
|--------|---------|-------------|
| `registry:register(def)` | `ok, errors` | Validate + store. Logs errors on failure. |
| `registry:get(id)` | `table\|nil` | Lookup by ID |
| `registry:getAll()` | `table[]` | Shallow-copied array of all definitions |
| `registry:exists(id)` | `boolean` | Check if ID is registered |
| `registry:count()` | `number` | Number of registered definitions |
| `registry:seal()` | — | Freeze; further `register()` calls fail |
| `registry:remove(id)` | `boolean` | Remove by ID (for testing/migration) |

**Error logging example:**
```
[MyMod:Archetype] "road_king" rejected: tuning.volatility: must be at most 1.0 (got: 1.5)
```

### Data Loader (`PhobosLib_DataLoader`)

Batch-load data-only Lua definition files via `require` and register them.

```lua
-- Load multiple definitions at once
local result = PhobosLib.loadDefinitions({
    registry = registry,
    paths = {
        "Definitions/Archetypes/scavenger_trader",
        "Definitions/Archetypes/quartermaster",
    },
    tag = "[MyMod:Loader]",
})
-- result: { loaded = 2, failed = 0, errors = {} }

-- Load a single definition
local ok, errors = PhobosLib.loadDefinition(
    "Definitions/Archetypes/custom_agent", registry, "[MyMod:Loader]")
```

**Error handling:** `require` failures (syntax errors, missing files), non-table returns, and validation failures are all logged with clear messages and never crash the game. Failed definitions are skipped; valid ones are registered.

**Addon mod integration:** Third-party mods register content via the registry API directly:
```lua
require "POS_MarketAgent"
POS_MarketAgent.getRegistry():register(require "MyMod/my_custom_agent")
```

---

## Per-Player ModData Access

### `PhobosLib.getPlayerModDataTable(player, key)` → table|nil

Canonical way to read a per-player array or table stored in player modData.
Returns the table at `player:getModData()[key]`, or `nil` if the player is
nil, the key is nil, or the entry does not exist.

Follows **Empty-Data Return Convention** (see POSnet design-guidelines §25.6):
returns `nil` on bad input rather than an empty table, forcing callers to
nil-check before use.

**Why modData over file I/O:** `getFileReader` causes silent JVM crashes in
multiple PZ lifecycle contexts (OnGameStart, render frames, event ticks).
Player modData is engine-managed, auto-persisted on save, and safe to access
at any time. Per-player data (watchlists, alerts, orders, holdings) must
always use this function instead of custom file I/O.

**Usage:**

```lua
local watchlist = PhobosLib.getPlayerModDataTable(player, "POS_Watchlist") or {}
for _, entry in ipairs(watchlist) do
    -- process entry
end
```

---

## Registry Display Name Resolution

### `PhobosLib.getRegistryDisplayName(registry, id, fallback)` → string

Resolve a localised display name from a registry-backed definition. Looks up the
definition by ID, reads its `displayNameKey` field, and returns the translated
text via `PhobosLib.safeGetText()`.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `registry` | table | PhobosLib registry instance (from `createRegistry`) |
| `id` | string | Definition ID to look up |
| `fallback` | string\|nil | Text returned when definition or key is missing (default: the raw `id`) |

**Convention:** Registry definitions that have user-visible names should include a
`displayNameKey` field pointing to a translation key in the mod's translation
files. This function enforces that convention — if the field is absent, it falls
back gracefully rather than crashing.

**Fallback chain:**

1. Definition found **and** `displayNameKey` present → translated text from `safeGetText`
2. Definition found but no `displayNameKey` → `fallback` (or raw `id`)
3. Definition not found → `fallback` (or raw `id`)
4. `registry` or `id` is nil → `fallback` (or `id`, which is also nil)

**Usage — zone name resolution:**

```lua
local zoneRegistry = POS_MarketZone.getRegistry()
local zoneName = PhobosLib.getRegistryDisplayName(zoneRegistry, "rural_outpost")
-- Returns e.g. "Rural Outpost" if translation exists, or "rural_outpost" as fallback

-- With explicit fallback
local name = PhobosLib.getRegistryDisplayName(zoneRegistry, zoneId, "Unknown Zone")
```

---

## Infrastructure Utilities

General-purpose helpers for distance calculations, inventory manipulation, and requirement checking. These reduce boilerplate in consumer mods that need spatial logic, item grants/consumes, or pre-condition validation.

### `PhobosLib.manhattanDistance(x1, y1, z1, x2, y2, z2, zPenalty)` → number

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

**Usage — proximity gating:**

```lua
local dist = PhobosLib.manhattanDistance(px, py, pz, tx, ty, tz, 5)
if dist > 50 then
    -- too far away
end
```

### `PhobosLib.consumeItems(player, fullType, count)` → number

Consume N items of a given type from the player's main inventory. Removes items one at a time via `getFirstType`/`Remove` loop.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `player` | IsoPlayer | The player whose inventory to consume from |
| `fullType` | string | Full item type (e.g. `"Base.ElectricWire"`) |
| `count` | number | Number of items to consume |

**Returns:** Actual number consumed (may be less than `count` if inventory is short).

**Usage — crafting cost:**

```lua
local consumed = PhobosLib.consumeItems(player, "Base.ElectricWire", 3)
if consumed < 3 then
    PhobosLib.say(player, "Not enough wire!")
end
```

### `PhobosLib.grantItems(player, fullType, count)` → number

Grant N items of a given type to the player's main inventory.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `player` | IsoPlayer | The player to grant items to |
| `fullType` | string | Full item type (e.g. `"Base.ElectricWire"`) |
| `count` | number | Number of items to grant |

**Returns:** Actual number granted.

**Usage — mission reward:**

```lua
PhobosLib.grantItems(player, "Base.ElectricWire", 5)
```

### `PhobosLib.checkRequirements(player, opts)` → table

Check whether a player meets a set of requirements (items, tools, skill level). Returns a structured result suitable for tooltip generation or UI gating.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `player` | IsoPlayer | The player to check |
| `opts` | table | Requirements table (see fields below) |

**`opts` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `items` | table\|nil | `{fullType, count}` — item type and quantity needed |
| `tools` | table\|nil | Array of tool fullType strings that must be in inventory |
| `minSkill` | number\|nil | Minimum skill level required |
| `skillType` | string\|nil | PZ perk name (e.g. `"Electrical"`) |

**Returns:** Result table with fields:

| Field | Type | Description |
|-------|------|-------------|
| `ok` | boolean | `true` if all requirements met |
| `missingItems` | table | `{type, need, have}` or empty table |
| `missingTools` | table | Array of missing tool fullType strings |
| `skillTooLow` | boolean | `true` if skill check failed |
| `skillHave` | number | Player's current skill level |
| `skillNeed` | number | Required skill level |

**Usage — pre-craft check with tooltip feedback:**

```lua
local req = PhobosLib.checkRequirements(player, {
    items = {"Base.ElectricWire", 3},
    tools = {"Base.Screwdriver"},
    minSkill = 4,
    skillType = "Electrical",
})
if not req.ok then
    if req.skillTooLow then
        PhobosLib.say(player, "Need Electrical " .. req.skillNeed)
    end
    if #req.missingTools > 0 then
        PhobosLib.say(player, "Missing: " .. table.concat(req.missingTools, ", "))
    end
end
```

### `PhobosLib.getPlayerPerkLevel(player, perkId)` → number

Returns the player's level in a given perk, or 0 on any failure. Safe wrapper that resolves the perk via `Perks.FromString` and reads the level via `player:getPerkLevel`, with both calls protected by `safecall`.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `player` | IsoPlayer | The player to query |
| `perkId` | string | PZ perk identifier (e.g. `"Electricity"`, `"Passiv"`) |

**Returns:** Perk level as a number (0–10). Returns 0 if `player` is nil, `perkId` is invalid or unrecognised, or any Java exception occurs during resolution.

**Behaviour:**

1. Returns 0 immediately if `player` or `perkId` is nil.
2. Calls `Perks.FromString(perkId)` via `safecall` — returns 0 if the perk ID is not recognised.
3. Calls `player:getPerkLevel(perk)` via `safecall` — returns 0 on any Java-side error.

**Usage — satellite wiring Electrical check:**

```lua
local elecLevel = PhobosLib.getPlayerPerkLevel(player, "Electricity")
if elecLevel < 5 then
    PhobosLib.say(player, "Need Electricity 5 to wire the satellite dish.")
    return
end
-- proceed with wiring
```

---

## Recipe & Configuration Utilities

General-purpose helpers for item lookup, configuration resolution, and threshold-based tier matching. These reduce boilerplate in consumer mods that need to find items in recipe callbacks, read optional configuration, or map numeric values to discrete tiers.

### `PhobosLib.findItemInList(items, fullType)` → item, index

Find the first item in a list matching the given full type. Uses `PhobosLib.iterateItems()` internally for B42 ArrayList/table safety, and `PhobosLib.safecall()` on `getFullType` for defensive error handling.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `items` | any | Items parameter from OnCreate callback (ArrayList or table). Nil-safe — returns `nil, nil` |
| `fullType` | string | Full item type to match (e.g. `"Base.Screwdriver"`) |

**Returns:** `(item, index)` for the first match, or `(nil, nil)` if not found.

**Usage — find a specific input in a recipe callback:**

```lua
function MyMod.onCreateChemicalBatch(items, result, player, recipe)
    local flask, idx = PhobosLib.findItemInList(items, "ZVV.GlassFlask")
    if flask then
        local purity = PhobosLib.getModDataValue(flask, "purity", 0.5)
        PhobosLib.setModDataValue(result, "purity", purity * 0.9)
    end
end
```

### `PhobosLib.getConfigurable(module, methodName, fallback)` → any

Safely retrieve a configurable value from a module by calling a named getter method. Returns the fallback if the module is nil, the method does not exist, the call fails, or the result is nil. Uses `safecall` internally.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `module` | table\|nil | Module table to call the method on. Nil-safe — returns fallback |
| `methodName` | string | Name of the getter method (e.g. `"getMaxRetries"`) |
| `fallback` | any | Value returned when module, method, or result is nil |

**Returns:** The method's return value, or `fallback`.

**Usage — read optional cross-mod configuration:**

```lua
-- If POSnet is loaded, use its configured scan interval; otherwise default to 5
local ok, POS_Config = PhobosLib.safecall(require, "POS_Config")
local interval = PhobosLib.getConfigurable(
    ok and POS_Config, "getScanInterval", 5
)
```

### `PhobosLib.resolveThresholdTier(value, tiers, default)` → any

Resolve a numeric value against a sorted threshold tier list. Walks tiers in order; returns the `result` of the first tier where `value <= tier.threshold`. Returns `default` if no tier matches. Nil-safe on both `value` and `tiers`.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `value` | number\|nil | Value to test against thresholds. Nil-safe — returns `default` |
| `tiers` | table[]\|nil | Sorted array of `{threshold=number, result=any}`. Nil-safe — returns `default` |
| `default` | any | Value returned when no tier matches or inputs are nil |

**Returns:** The matching tier's `result`, or `default`.

**Usage — map signal strength to quality label:**

```lua
local SIGNAL_TIERS = {
    { threshold = 0.2, result = "critical" },
    { threshold = 0.5, result = "weak" },
    { threshold = 0.8, result = "moderate" },
    { threshold = 1.0, result = "strong" },
}

local quality = PhobosLib.resolveThresholdTier(signalStrength, SIGNAL_TIERS, "unknown")
-- signalStrength = 0.3 → "weak"
-- signalStrength = 0.9 → "strong"
-- signalStrength = 1.5 → "unknown" (no tier matches)
-- signalStrength = nil  → "unknown" (nil-safe)
```

---

## Text Compositor

Utilities for template-based text generation with weighted random selection, conditional filtering, and anti-repetition. Designed for procedural content systems (mission briefings, market reports, NPC dialogue) where text is assembled from data-driven pools.

### `PhobosLib.resolveTokens(text, ctx)` → string

Replace `{key}` placeholders in a template string with values from a context table. Placeholders whose keys are not found in `ctx` are left unreplaced.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `text` | string\|nil | Template string with `{key}` placeholders. Nil-safe — returns `""` |
| `ctx` | table\|nil | Key-value lookup table for replacements. Nil-safe — returns `text` unchanged |

**Returns:** Resolved string with matched placeholders replaced.

**Usage — mission briefing template:**

```lua
local briefing = PhobosLib.resolveTokens(
    "Deliver {item} to {location} within {hours} hours.",
    { item = "Radio Parts", location = "Muldraugh", hours = 48 }
)
-- "Deliver Radio Parts to Muldraugh within 48 hours."

-- Missing keys are preserved
local partial = PhobosLib.resolveTokens("Hello {name}, status: {status}", { name = "Gecko" })
-- "Hello Gecko, status: {status}"

-- Nil-safe
PhobosLib.resolveTokens(nil, {})   -- ""
PhobosLib.resolveTokens("test", nil) -- "test"
```

### `PhobosLib.conditionsPass(entry, ctx)` → boolean

Check if an entry's conditions match a context. Supports `minDifficulty`, `maxDifficulty` (numeric comparisons against `ctx.difficulty`), and arbitrary keys where the condition value is an array of allowed values (membership check against the corresponding `ctx` field).

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `entry` | table\|nil | Entry with optional `conditions` field. Nil-safe — returns `true` |
| `ctx` | table\|nil | Context table to check against. Nil returns `false` if entry has conditions |

**Returns:** `true` if all conditions pass or no conditions exist.

**Condition fields:**

| Condition | Type | Logic |
|-----------|------|-------|
| `minDifficulty` | number | `ctx.difficulty >= value` |
| `maxDifficulty` | number | `ctx.difficulty <= value` |
| `<key>` | array | `ctx[key]` must be one of the allowed values |

**Usage — conditional text pool entry:**

```lua
local entry = {
    text = "Enemy patrol spotted near {location}.",
    weight = 3,
    conditions = {
        minDifficulty = 2,
        category = { "recon", "military" },
    },
}

-- Passes: difficulty 3, category "recon"
PhobosLib.conditionsPass(entry, { difficulty = 3, category = "recon" })  -- true

-- Fails: difficulty too low
PhobosLib.conditionsPass(entry, { difficulty = 1, category = "recon" })  -- false

-- Fails: wrong category
PhobosLib.conditionsPass(entry, { difficulty = 3, category = "market" }) -- false

-- No conditions = always passes
PhobosLib.conditionsPass({ text = "Hello" }, {})  -- true
```

### `PhobosLib.pickWeighted(entries, ctx)` → table|nil

Select a random entry from a weighted pool. Filters entries by `conditionsPass`, sums remaining weights, picks via `ZombRand(totalWeight)` and walks cumulative weights.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `entries` | table[]\|nil | Array of `{text, weight, id, conditions}`. Nil-safe — returns `nil` |
| `ctx` | table\|nil | Context table passed to `conditionsPass` for filtering |

**Returns:** The selected entry table, or `nil` if no valid entries remain after filtering.

**Usage — weighted random text selection:**

```lua
local pool = {
    { text = "All clear on frequency {freq}.", weight = 5, id = "clear" },
    { text = "Interference detected on {freq}.", weight = 2, id = "noise" },
    { text = "Emergency broadcast on {freq}!", weight = 1, id = "emergency",
      conditions = { minDifficulty = 3 } },
}

local picked = PhobosLib.pickWeighted(pool, { difficulty = 4 })
if picked then
    local msg = PhobosLib.resolveTokens(picked.text, { freq = "91.5 MHz" })
end
```

### `PhobosLib.avoidRecent(entryId, history, maxSize)` → boolean

Anti-repetition guard. Returns `false` if `entryId` is already in the `history` array (recently used). Otherwise appends `entryId` to `history`, trims to `maxSize` by removing oldest entries, and returns `true`.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `entryId` | string | ID to check and record |
| `history` | table\|nil | Array of recent IDs (mutated in place). Nil-safe — returns `true` |
| `maxSize` | number\|nil | Maximum history size (default 10) |

**Returns:** `true` if `entryId` was NOT recently used; `false` if it was.

**Usage — prevent repeated messages:**

```lua
local recentMessages = {}

local picked = PhobosLib.pickWeighted(pool, ctx)
if picked and PhobosLib.avoidRecent(picked.id, recentMessages, 5) then
    -- Use picked.text — it hasn't appeared in the last 5 selections
else
    -- Re-roll or use fallback
end
```

---

## Cross-Module Communication

When a module depends on another module that may not be present (optional
cross-mod dependency, or a module from a different loading phase), use the
safecall-require pattern:

```lua
local ok, OtherModule = PhobosLib.safecall(require, "OtherModule")
if ok and OtherModule and OtherModule.someFunction then
    PhobosLib.safecall(OtherModule.someFunction, arg1, arg2)
end
```

Rules:

- Never assume a module exists at call time — always guard
- Prefer lazy require (inside the function that needs it) over top-level require
  for optional deps
- For hard dependencies (modules that MUST exist), use normal `require` at file
  top
- See POSnet `docs/design-guidelines.md` §28.5 for the full cross-system call
  discipline
