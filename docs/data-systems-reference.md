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

# PhobosLib Data Systems Reference

Data persistence, schema validation, and deferred processing utilities provided by PhobosLib. Covers lazy initialisation, throttling, chunked file writing, the schema/registry/data-loader pipeline, per-player ModData access, and registry display name resolution.

For other PhobosLib API documentation, see: [error-handling.md](error-handling.md), [utilities-reference.md](utilities-reference.md), [ui-reference.md](ui-reference.md)

---

## Deferred Initialisation & Throttling

### `PhobosLib.lazyInit(initFn)`
- **Parameters:** `initFn` (function) -- one-time initialisation function
- **Returns:** Guard function -- call before accessing module state
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

---

## Chunked File Writing

For large data stores that must be serialised to disk, writing everything in a
single frame causes a visible hitch. PhobosLib provides a chunked writer that
spreads the work across multiple `EveryOneMinute` ticks.

### `PhobosLib.createChunkedWriter(opts)` -> writer

Factory. Returns a writer handle used by the other chunked-write functions.

| Option | Type | Description |
|--------|------|-------------|
| `filePath` | string | Destination path passed to `getFileWriter` |
| `chunkSize` | number | Items to serialise per tick |
| `onSerialize` | function(item, fileWriter) | Called once per item -- write the item's data |
| `onComplete` | function() | Called after the final chunk is flushed and the file is closed |

### `PhobosLib.startChunkedWrite(writer, source)`

Queue a write operation. `source` is an array-style table of items to
serialise. The writer copies the list internally so the caller may continue
to mutate the original table.

### `PhobosLib.tickChunkedWrite(writer)` -> boolean

Process the next chunk (up to `chunkSize` items). Returns `true` when the
entire source has been written and the file has been closed; `false` while
work remains.

### `PhobosLib.isChunkedWriteActive(writer)` -> boolean

Returns `true` if the writer has queued items that have not yet been fully
flushed. Useful for preventing overlapping writes.

### Usage example -- market data save

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
> handler -- ownership of the tick loop stays with the consumer.

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

-- Apply default values for missing optional fields (mutates in place).
PhobosLib.applyDefaults(data, schema)

-- Format errors into human-readable log strings.
local lines = PhobosLib.formatValidationErrors(errors, "[MyMod]")
```

### Registry (`PhobosLib_Registry`)

Create typed registries that validate definitions on registration and provide safe lookup.

```lua
local registry = PhobosLib.createRegistry({
    name = "Archetypes",
    schema = mySchema,
    idField = "id",
    allowOverwrite = false,
    tag = "[MyMod:Archetype]",
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
| `registry:seal()` | -- | Freeze; further `register()` calls fail |
| `registry:remove(id)` | `boolean` | Remove by ID (for testing/migration) |

### Data Loader (`PhobosLib_DataLoader`)

Batch-load data-only Lua definition files via `require` and register them.

```lua
local result = PhobosLib.loadDefinitions({
    registry = registry,
    paths = {
        "Definitions/Archetypes/scavenger_trader",
        "Definitions/Archetypes/quartermaster",
    },
    tag = "[MyMod:Loader]",
})
-- result: { loaded = 2, failed = 0, errors = {} }
```

**Addon mod integration:** Third-party mods register content via the registry API directly:
```lua
require "POS_MarketAgent"
POS_MarketAgent.getRegistry():register(require "MyMod/my_custom_agent")
```

---

## Per-Player ModData Access

### `PhobosLib.getPlayerModDataTable(player, key)` -> table|nil

Canonical way to read a per-player array or table stored in player modData.
Returns the table at `player:getModData()[key]`, or `nil` if the player is
nil, the key is nil, or the entry does not exist.

Follows the **Empty-Data Return Convention** (see [error-handling.md](error-handling.md)):
returns `nil` on bad input rather than an empty table, forcing callers to
nil-check before use.

**Why modData over file I/O:** `getFileReader` causes silent JVM crashes in
multiple PZ lifecycle contexts (OnGameStart, render frames, event ticks).
Player modData is engine-managed, auto-persisted on save, and safe to access
at any time.

**Usage:**

```lua
local watchlist = PhobosLib.getPlayerModDataTable(player, "POS_Watchlist") or {}
for _, entry in ipairs(watchlist) do
    -- process entry
end
```

---

## Registry Display Name Resolution

### `PhobosLib.getRegistryDisplayName(registry, id, fallback)` -> string

Resolve a localised display name from a registry-backed definition. Looks up the
definition by ID, reads its `displayNameKey` field, and returns the translated
text via `PhobosLib.safeGetText()`.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `registry` | table | PhobosLib registry instance (from `createRegistry`) |
| `id` | string | Definition ID to look up |
| `fallback` | string\|nil | Text returned when definition or key is missing (default: the raw `id`) |

**Fallback chain:**

1. Definition found **and** `displayNameKey` present -> translated text from `safeGetText`
2. Definition found but no `displayNameKey` -> `fallback` (or raw `id`)
3. Definition not found -> `fallback` (or raw `id`)
4. `registry` or `id` is nil -> `fallback` (or `id`, which is also nil)

**Usage:**

```lua
local zoneRegistry = POS_MarketZone.getRegistry()
local zoneName = PhobosLib.getRegistryDisplayName(zoneRegistry, "rural_outpost")
-- Returns e.g. "Rural Outpost" if translation exists, or "rural_outpost" as fallback
```
