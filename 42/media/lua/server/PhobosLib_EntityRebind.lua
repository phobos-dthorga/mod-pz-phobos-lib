--  ________________________________________________________________________
-- / Copyright (c) 2026 Phobos A. D'thorga                                \
-- |                                                                        |
-- |           /\_/\                                                         |
-- |         =/ o o \=    Phobos' PZ Modding                                |
-- |          (  V  )     All rights reserved.                              |
-- |     /\  / \   / \                                                      |
-- |    /  \/   '-'   \   This source code is part of the Phobos            |
-- |   /  /  \  ^  /\  \  mod suite for Project Zomboid (Build 42).         |
-- |  (__/    \_/ \/  \__)                                                  |
-- |     |   | |  | |     Unauthorised copying, modification, or            |
-- |     |___|_|  |_|     distribution of this file is prohibited.          |
-- |                                                                        |
-- \________________________________________________________________________/
--

---------------------------------------------------------------
-- PhobosLib_EntityRebind.lua
-- Server-side entity rebinding for pre-existing world objects.
--
-- In PZ B42, entity binding (CraftBench, UiConfig, SpriteConfig)
-- happens ONLY at object creation/placement time.  When a mod
-- installs entity definitions for an existing sprite, objects
-- that were placed BEFORE the mod was installed do not get the
-- entity.  Players must pick up and re-place every object.
--
-- This module provides a generic registry: any Phobos mod can
-- register sprite-to-entity rebindings.  On chunk load the
-- MapObjects hooks fire, check hasComponents(), and create the
-- entity from the sprite's SpriteConfig if it is missing.
--
-- Vanilla reference patterns:
--   ISMoveableSpriteProps.lua:2341-2342  hasComponents() + CreateIsoEntityFromCellLoading
--   MOFeedingTrough.lua:108-158         MapObjects.OnLoadWithSprite callback pattern
--
-- Part of PhobosLib >= 1.14.0
---------------------------------------------------------------

if isClient() then return end

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:EntityRebind]"

---------------------------------------------------------------
-- Internal state
---------------------------------------------------------------

--- Registry of all entity rebinding entries (for introspection/debugging).
PhobosLib._entityRebindEntries = PhobosLib._entityRebindEntries or {}

--- Counter for logging how many objects were rebound this session.
local _reboundCount = 0

--- Throttle limit for per-object log messages.
local _LOG_LIMIT = 50

---------------------------------------------------------------
-- Rebinding callback
---------------------------------------------------------------

--- Callback for MapObjects.OnLoadWithSprite / OnNewWithSprite.
--- Checks if the object already has entity components; if not,
--- creates them from the sprite's entity configuration.
---
--- Uses GameEntityFactory.CreateIsoEntityFromCellLoading(obj)
--- which resolves the entity script from the SpriteConfig
--- defined in the mod's entity .txt files.
---
---@param isoObject any     The IsoObject on the loaded square
---@param label string      Human-readable label for logging
---@param guardFunc function|nil  Optional sandbox/mod-active guard
local function onSpriteLoaded(isoObject, label, guardFunc)
    local ok, err = pcall(function()
        -- Guard check (e.g. sandbox option)
        if guardFunc then
            local gOk, gResult = pcall(guardFunc)
            if not gOk or gResult ~= true then return end
        end

        -- Idempotency: skip if entity already bound
        local hasComp = false
        local hOk, hResult = pcall(function() return isoObject:hasComponents() end)
        if hOk then hasComp = hResult end

        if hasComp then return end

        -- Bind entity from sprite config
        GameEntityFactory.CreateIsoEntityFromCellLoading(isoObject)

        _reboundCount = _reboundCount + 1
        if _reboundCount <= _LOG_LIMIT then
            print(_TAG .. " rebound entity for " .. label
                .. " at " .. tostring(isoObject:getX())
                .. "," .. tostring(isoObject:getY())
                .. "," .. tostring(isoObject:getZ()))
        elseif _reboundCount == _LOG_LIMIT + 1 then
            print(_TAG .. " (further rebind messages suppressed)")
        end
    end)

    if not ok then
        print(_TAG .. " ERROR rebinding " .. tostring(label) .. ": " .. tostring(err))
    end
end

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------

--- Register entity rebinding for world objects matching given sprites.
---
--- When chunks containing registered sprites are loaded, any matching
--- IsoObject that does not already have entity components will have
--- its entity created from the SpriteConfig defined in the mod's
--- entity .txt files.
---
--- This handles the B42 limitation where entity binding only occurs
--- at object creation/placement time.  Pre-existing world objects
--- (placed before the mod was installed) get their entity binding
--- on first chunk load after registration.
---
--- IMPORTANT: Entity .txt files must define SpriteConfig with the
--- exact sprite names passed here.  The sprite-to-entity mapping is
--- resolved by GameEntityFactory from SpriteConfigManager.
---
--- Also registers OnNewWithSprite as a defensive backup for objects
--- placed during the session via non-standard means (server commands,
--- map editing, etc.).  Objects placed via ISBuildIsoEntity already
--- get entity binding from vanilla code.
---
---@param config table Configuration table with fields:
---   config.sprites   table           Array of sprite name strings
---   config.label     string          Human-readable label for logging
---   config.guardFunc function|nil    Optional guard: function() -> boolean
---   config.priority  number|nil      MapObjects priority (default 5)
function PhobosLib.registerEntityRebinding(config)
    if type(config) ~= "table" then
        print(_TAG .. " registerEntityRebinding: config must be a table")
        return
    end
    if type(config.sprites) ~= "table" or #config.sprites == 0 then
        print(_TAG .. " registerEntityRebinding: config.sprites must be a non-empty array")
        return
    end
    if type(config.label) ~= "string" or config.label == "" then
        print(_TAG .. " registerEntityRebinding: config.label must be a non-empty string")
        return
    end
    if config.guardFunc ~= nil and type(config.guardFunc) ~= "function" then
        print(_TAG .. " registerEntityRebinding: config.guardFunc must be a function or nil")
        return
    end

    local priority  = config.priority or 5
    local label     = config.label
    local guardFunc = config.guardFunc

    -- Create a closure that captures label and guardFunc
    local function callback(isoObject)
        onSpriteLoaded(isoObject, label, guardFunc)
    end

    -- Register with MapObjects for each sprite
    for _, spriteName in ipairs(config.sprites) do
        MapObjects.OnLoadWithSprite(spriteName, callback, priority)
        MapObjects.OnNewWithSprite(spriteName, callback, priority)
    end

    -- Track in internal registry (for debugging/introspection)
    table.insert(PhobosLib._entityRebindEntries, {
        sprites   = config.sprites,
        label     = label,
        guardFunc = guardFunc,
        priority  = priority,
    })

    print(_TAG .. " registered " .. #config.sprites
        .. " sprite(s) for entity rebinding: " .. label)
end
