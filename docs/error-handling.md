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
