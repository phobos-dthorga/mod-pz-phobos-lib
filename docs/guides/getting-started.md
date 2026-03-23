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

# Getting Started with PhobosLib

PhobosLib is a shared utility library for Project Zomboid Build 42 mods. It is a **dependency**, not a standalone mod -- players install it because other mods require it. PhobosLib provides safe wrappers, helpers, and reusable systems so that mod authors can focus on gameplay features rather than reinventing common infrastructure.

## Adding PhobosLib as a dependency

In your mod's `mod.info`, add PhobosLib as a required dependency:

```
require=PhobosLib
```

Then in any of your Lua files, load the shared modules:

```lua
require "PhobosLib"
```

This populates the global `PhobosLib` table with all shared modules. Client-side and server-side modules (Tooltip, Popup, RecipeFilter, etc.) are loaded automatically by PZ from `client/` and `server/` directories.

## Key modules overview

| Module | Purpose |
|--------|---------|
| **PhobosLib_Debug** | Centralised debug logging gated by per-mod sandbox options |
| **PhobosLib_Util** | Safe method calling, API probing, keyword search, modData helpers |
| **PhobosLib_Quality** | Generic 0-100 quality/purity scoring with tier lookup and equipment factors |
| **PhobosLib_Tooltip** | *(client)* Register callbacks that append coloured lines below vanilla item tooltips |
| **PhobosLib_Condition** | Item condition management helpers |
| **PhobosLib_Schema** | Generic data structure validator for definition files |
| **PhobosLib_Registry** | Typed registry factory -- create named registries for definition data |
| **PhobosLib_DataLoader** | Batch definition loader that feeds Schema + Registry |
| **PhobosLib_Sandbox** | Safe sandbox variable access with defaults, mod detection, yield multipliers |
| **PhobosLib_Migrate** | Versioned save migration framework with semver comparison |

For the full API reference with all function signatures, see the [Module Overview](../architecture/diagrams/module-overview.md).

## Quick examples

### Debug logging

```lua
require "PhobosLib"

-- Prints "[MyMod] Something happened" when MyMod's EnableDebugLogging sandbox option is true
PhobosLib.debug("MyMod", "Something happened")
```

### Safe function calls

```lua
require "PhobosLib"

-- Wraps a function call in pcall; returns nil on error instead of crashing
local result = PhobosLib.safecall(somePotentiallyFailingFunction, arg1, arg2)

-- Safe getText with fallback (never crashes on missing translation keys)
local label = PhobosLib.safeGetText("IGUI_MyMod_SomeLabel", "fallback text")
```

### Creating a registry

```lua
require "PhobosLib"

-- Create a typed registry for your mod's definitions
local myRegistry = PhobosLib.createRegistry("MyMod_Items", {
    validateFn = function(entry)
        return entry.id ~= nil and entry.name ~= nil
    end
})

-- Register entries
myRegistry:register({ id = "widget", name = "Widget" })

-- Query entries
local widget = myRegistry:get("widget")
```

### Sandbox variable access

```lua
require "PhobosLib"

-- Safely read a sandbox variable with a default value
local spawnRate = PhobosLib.getSandboxVar("MyMod", "SpawnRate", 1.0)

-- Check if another mod is active
if PhobosLib.isModActive("SomeOtherMod") then
    -- Enable cross-mod features
end
```

## Further reading

- [Module Overview & API Reference](../architecture/diagrams/module-overview.md) -- full function signatures for all modules
- [Error Handling](../architecture/error-handling.md) -- safecall patterns and Strict Mode
- [Data Systems Reference](../architecture/data-systems-reference.md) -- Schema, Registry, and DataLoader
- [FAQ](faq.md) -- common questions
