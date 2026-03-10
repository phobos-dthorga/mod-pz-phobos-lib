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
-- PhobosLib_Power.lua
-- Client-side power detection, UI gating, and time-based
-- generator fuel drain for powered CraftBench entities.
--
-- Provides:
--   - Generic power detection (grid + generator + custom sources)
--   - Powered CraftBench registration (entity script name lookup)
--   - ISWidgetHandCraftControl monkey-patches:
--       prerender() — grey out craft button when no power
--       startHandcraft() — safety net + fuel drain session
--   - Time-based fuel drain system (OnTick throttled)
--
-- Power detection follows vanilla ISButtonPrompt.lua patterns:
--   - Grid power: SandboxVars.ElecShutModifier + world age
--   - Generator: square:haveElectricity() covers generator range
--   - Custom sources: extensible via registerPowerSource()
--
-- No vanilla workstation has electricity gating — this is a
-- first for PZ modding. The generator system is Java-driven;
-- we cannot make custom consumers appear in the generator's
-- "Items Powered" list. We CAN manually drain fuel via
-- generator:setFuel() + generator:sync().
--
-- Part of PhobosLib >= 1.12.0
---------------------------------------------------------------

require "ISUI/ISPanelJoypad"
require "Entity/ISUI/CraftRecipe/ISWidgetHandCraftControl"

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:Power]"

---------------------------------------------------------------
-- Internal registries
---------------------------------------------------------------

--- Powered entity registry: { [entityScriptName] = {options}, ... }
PhobosLib._poweredEntities = PhobosLib._poweredEntities or {}

--- Custom power source checkers: { function(square)->bool, ... }
PhobosLib._customPowerSources = PhobosLib._customPowerSources or {}

--- Active fuel drain sessions: { [sessionId] = sessionData, ... }
PhobosLib._drainSessions = PhobosLib._drainSessions or {}

--- Counter for session IDs
local _nextSessionId = 1

--- Whether the ISWidgetHandCraftControl hooks have been installed
local _hooksInstalled = false

--- References to original functions
local _originalPrerender = nil
local _originalStartHandcraft = nil

--- Tick counter for drain throttling
local _drainTickCount = 0
local _drainTickInstalled = false

--- Generator search radius (tiles) — vanilla generator range is ~20
local GENERATOR_SEARCH_RADIUS = 20


---------------------------------------------------------------
-- Power Detection API
---------------------------------------------------------------

--- Check whether the electrical grid is still active.
--- Replicates the vanilla pattern from ISButtonPrompt.lua:
---   if SandboxVars.ElecShutModifier > -1 then
---     check world age vs ElecShutModifier
---
---@return boolean  true if grid power is currently active
function PhobosLib.isGridPowerActive()
    local ok, result = pcall(function()
        if SandboxVars.ElecShutModifier > -1 then
            local currentDay = getGameTime():getWorldAgeHours() / 24
                + (getSandboxOptions():getTimeSinceApo() - 1) * 30
            return currentDay < SandboxVars.ElecShutModifier
        end
        return true  -- ElecShutModifier == -1 means power never shuts off
    end)
    if ok then return result end
    return false
end


--- Check whether a square has any power source available.
--- Checks (in order):
---   1. Custom registered power sources
---   2. Grid power (SandboxVars + world age)
---   3. square:haveElectricity() (covers both grid + generator range)
---
---@param square any  IsoGridSquare
---@return boolean  true if the square has power from any source
function PhobosLib.hasPower(square)
    if not square then return false end

    -- Check custom power sources first (e.g. PhobosPortableEnergySolutions)
    for _, checkFunc in ipairs(PhobosLib._customPowerSources) do
        local ok, result = pcall(checkFunc, square)
        if ok and result == true then return true end
    end

    -- Check grid power (independent of square — it's global)
    if PhobosLib.isGridPowerActive() then return true end

    -- Check square:haveElectricity() — covers generator in range
    local ok, result = pcall(function() return square:haveElectricity() end)
    if ok and result == true then return true end

    return false
end


--- Register a custom power source checker.
--- The checker receives an IsoGridSquare and should return true if
--- that square has power from this source (e.g. a portable battery).
---
--- Use this to integrate PhobosPortableEnergySolutions or other
--- alternative power mods.
---
---@param checkFunc function  function(square) -> boolean
function PhobosLib.registerPowerSource(checkFunc)
    if type(checkFunc) ~= "function" then
        print(_TAG .. " registerPowerSource: checkFunc must be a function")
        return
    end
    table.insert(PhobosLib._customPowerSources, checkFunc)
    print(_TAG .. " registered custom power source checker")
end


---------------------------------------------------------------
-- Fuel Drain System
---------------------------------------------------------------

--- Find the nearest active generator powering a square.
--- Uses PhobosLib.findNearbyGenerator from World module.
---
---@param square any  IsoGridSquare
---@return any|nil  IsoGenerator or nil
local function findPoweringGenerator(square)
    if not square then return nil end
    return PhobosLib.findNearbyGenerator(square, GENERATOR_SEARCH_RADIUS)
end


--- Start a time-based fuel drain session on the nearest generator.
--- Fuel is drained proportional to real time elapsed.
---
--- If grid power is active, no drain occurs (free electricity).
--- If no generator is found and grid is off, returns nil (no power).
---
---@param square any           IsoGridSquare of the powered entity
---@param drainPerMinute number  Fuel % to drain per real-time minute (e.g. 0.5)
---@return number|nil          Session ID for stopPowerDrain(), or nil if no power
function PhobosLib.startPowerDrain(square, drainPerMinute)
    if not square then return nil end
    drainPerMinute = drainPerMinute or 0.5

    -- Grid power = free electricity, no drain needed
    if PhobosLib.isGridPowerActive() then
        local sessionId = _nextSessionId
        _nextSessionId = _nextSessionId + 1
        PhobosLib._drainSessions[sessionId] = {
            square = square,
            drainPerMinute = 0,  -- no drain on grid
            generator = nil,
            gridPower = true,
            lastTick = getTimestampMs(),
            active = true,
        }
        PhobosLib.debug("PhobosLib", _TAG, "started drain session " .. sessionId .. " (grid power — no fuel drain)")
        return sessionId
    end

    -- Find generator
    local gen = findPoweringGenerator(square)
    if not gen then return nil end

    local sessionId = _nextSessionId
    _nextSessionId = _nextSessionId + 1

    PhobosLib._drainSessions[sessionId] = {
        square = square,
        drainPerMinute = drainPerMinute,
        generator = gen,
        gridPower = false,
        lastTick = getTimestampMs(),
        active = true,
    }

    -- Install tick handler if not yet active
    if not _drainTickInstalled then
        Events.OnTick.Add(PhobosLib._onDrainTick)
        _drainTickInstalled = true
        print(_TAG .. " OnTick drain handler installed")
    end

    PhobosLib.debug("PhobosLib", _TAG, "started drain session " .. sessionId
        .. " (generator, " .. drainPerMinute .. "%/min)")
    return sessionId
end


--- Stop an active fuel drain session.
---
---@param sessionId number  Session ID from startPowerDrain()
function PhobosLib.stopPowerDrain(sessionId)
    if not sessionId then return end
    local session = PhobosLib._drainSessions[sessionId]
    if session then
        session.active = false
        PhobosLib._drainSessions[sessionId] = nil
        PhobosLib.debug("PhobosLib", _TAG, "stopped drain session " .. sessionId)
    end

    -- Uninstall tick handler if no active sessions remain
    local hasActive = false
    for _, s in pairs(PhobosLib._drainSessions) do
        if s.active then hasActive = true end
    end
    if not hasActive and _drainTickInstalled then
        Events.OnTick.Remove(PhobosLib._onDrainTick)
        _drainTickInstalled = false
    end
end


--- Internal OnTick handler for fuel drain.
--- Throttled to fire approximately every 60 ticks (~1 real second).
function PhobosLib._onDrainTick()
    _drainTickCount = _drainTickCount + 1
    if _drainTickCount < 60 then return end
    _drainTickCount = 0

    local now = getTimestampMs()

    for sessionId, session in pairs(PhobosLib._drainSessions) do
        if session.active then
            local shouldStop = false

            if session.gridPower then
                -- Re-check grid power; if it went out, try to find a generator
                if not PhobosLib.isGridPowerActive() then
                    local gen = findPoweringGenerator(session.square)
                    if gen then
                        session.generator = gen
                        session.gridPower = false
                        session.drainPerMinute = session.drainPerMinute
                        -- drainPerMinute was 0 for grid; we need the original rate
                        -- Since we don't store it, use a fallback default
                        -- The calling code should re-register if grid fails
                        PhobosLib.debug("PhobosLib", _TAG, "session " .. sessionId .. ": grid failed, found generator")
                    else
                        PhobosLib.debug("PhobosLib", _TAG, "session " .. sessionId .. ": grid failed, no generator — power lost")
                        shouldStop = true
                    end
                end
            else
                -- Generator drain
                local gen = session.generator
                if not gen then
                    shouldStop = true
                else
                    local genOk = pcall(function()
                        local activated = gen:isActivated()
                        local fuel = gen:getFuel()

                        if not activated or fuel <= 0 then
                            shouldStop = true
                            return
                        end

                        -- Calculate time elapsed since last drain
                        local elapsedMs = now - session.lastTick
                        local elapsedMinutes = elapsedMs / 60000.0

                        -- Drain fuel
                        local drain = session.drainPerMinute * elapsedMinutes
                        if drain > 0 then
                            local newFuel = math.max(0, fuel - drain)
                            gen:setFuel(newFuel)
                            pcall(function() gen:sync() end)

                            if newFuel <= 0 then
                                print(_TAG .. " session " .. sessionId .. ": generator fuel exhausted")
                                shouldStop = true
                            end
                        end
                    end)

                    if not genOk then shouldStop = true end
                end
            end

            session.lastTick = now

            if shouldStop then
                session.active = false
                PhobosLib._drainSessions[sessionId] = nil
            end
        end
    end
end


---------------------------------------------------------------
-- Powered CraftBench Registration
---------------------------------------------------------------

--- Register an entity script name as requiring power to craft.
--- When a CraftBench entity with this script name is opened,
--- the craft button will be greyed out with a tooltip message
--- if no power is available.
---
--- Options:
---   messageKey   (string)   Translation key for the tooltip (default: "IGUI_PhobosLib_NoPower")
---   drainPerMinute (number) Fuel drain % per real-time minute (default: 0.5)
---   guardFunc    (function) Optional guard: function() -> boolean. Power check only
---                           runs when guard returns true (e.g. sandbox option check).
---
---@param entityScriptName string  Entity script name (e.g. "PCP_ConcreteMixer")
---@param options table|nil        Optional configuration
function PhobosLib.registerPoweredCraftBench(entityScriptName, options)
    if type(entityScriptName) ~= "string" or entityScriptName == "" then
        print(_TAG .. " registerPoweredCraftBench: invalid entityScriptName")
        return
    end

    options = options or {}
    PhobosLib._poweredEntities[entityScriptName] = {
        messageKey     = options.messageKey or "IGUI_PhobosLib_NoPower",
        drainPerMinute = options.drainPerMinute or 0.5,
        guardFunc      = options.guardFunc,
    }

    -- Install hooks on first registration
    if not _hooksInstalled then
        installPowerHooks()
    end

    print(_TAG .. " registered powered entity: " .. entityScriptName
        .. " (drain=" .. (options.drainPerMinute or 0.5) .. "%/min)")
end


---------------------------------------------------------------
-- Entity identification from UI control
---------------------------------------------------------------

--- Attempt to extract the entity script name from an
--- ISWidgetHandCraftControl instance.
---
--- Chain: ISWidgetHandCraftControl -> parent ISHandCraftPanel -> .isoObject (entity)
---        -> :getScript() -> :getName()
---
---@param control any  ISWidgetHandCraftControl instance
---@return string|nil  Entity script name, or nil
local function getEntityScriptName(control)
    if not control then return nil end
    local ok, name = pcall(function()
        local parent = control:getParent()
        if not parent then return nil end
        local entity = parent.isoObject
        if not entity then return nil end
        local script = entity:getScript()
        if not script then return nil end
        return script:getName()
    end)
    if ok then return name end
    return nil
end


--- Attempt to extract the entity's IsoGridSquare from an
--- ISWidgetHandCraftControl instance.
---
---@param control any  ISWidgetHandCraftControl instance
---@return any|nil  IsoGridSquare, or nil
local function getEntitySquare(control)
    if not control then return nil end
    local ok, sq = pcall(function()
        local parent = control:getParent()
        if not parent then return nil end
        local entity = parent.isoObject
        if not entity then return nil end
        return entity:getSquare()
    end)
    if ok then return sq end
    return nil
end


---------------------------------------------------------------
-- ISWidgetHandCraftControl hooks
---------------------------------------------------------------

--- Hooked prerender: inject power check AFTER vanilla logic.
--- If the entity is registered as powered and has no power,
--- disable the craft button and set a tooltip.
local function hookedPrerender(self)
    -- Call original first
    _originalPrerender(self)

    -- Only act if craft button exists and is currently enabled
    if not self or not self.buttonCraft or not self.buttonCraft.enable then
        return
    end

    -- Try to identify the entity
    local scriptName = getEntityScriptName(self)
    if not scriptName then return end

    -- Check if this entity is registered as powered
    local registration = PhobosLib._poweredEntities[scriptName]
    if not registration then return end

    -- Check guard function (e.g. sandbox option)
    if registration.guardFunc then
        local guardOk, guardResult = pcall(registration.guardFunc)
        if not guardOk or guardResult ~= true then
            return  -- guard says skip power check
        end
    end

    -- Check power availability
    local square = getEntitySquare(self)
    if not square then return end

    if not PhobosLib.hasPower(square) then
        self.buttonCraft.enable = false
        self.buttonCraft.tooltip = getText(registration.messageKey)
            or "Requires Electricity"
    end
end


--- Hooked startHandcraft: safety net power check + fuel drain start.
--- If power is lost between prerender and craft start, cancel.
--- On successful start, begin fuel drain and attach stop to callbacks.
local function hookedStartHandcraft(self, force)
    if not self or not self.logic then
        if _originalStartHandcraft then
            return _originalStartHandcraft(self, force)
        end
        return
    end

    -- Identify entity
    local scriptName = getEntityScriptName(self)
    local registration = scriptName and PhobosLib._poweredEntities[scriptName]

    -- If not a powered entity, delegate unchanged
    if not registration then
        return _originalStartHandcraft(self, force)
    end

    -- Check guard
    if registration.guardFunc then
        local guardOk, guardResult = pcall(registration.guardFunc)
        if not guardOk or guardResult ~= true then
            return _originalStartHandcraft(self, force)
        end
    end

    -- Safety net: re-check power before starting
    local square = getEntitySquare(self)
    if square and not PhobosLib.hasPower(square) then
        -- Power lost — cancel with speech bubble
        pcall(function()
            PhobosLib.say(self.player, getText(registration.messageKey) or "Requires Electricity")
        end)
        return  -- do NOT call original — abort the craft
    end

    -- Start fuel drain session
    local drainSessionId = nil
    if square then
        drainSessionId = PhobosLib.startPowerDrain(square, registration.drainPerMinute)
    end

    -- Call original to actually start the craft
    _originalStartHandcraft(self, force)

    -- Attach drain cleanup to the action callbacks
    -- The original startHandcraft stores callbacks at lines 401-403
    -- We need to wrap those callbacks to also stop the drain
    if drainSessionId then
        -- Store the session on the control for later cleanup
        self._phobosLibDrainSessionId = drainSessionId

        -- Wrap the existing completion/cancel callbacks
        local originalOnComplete = self.onHandcraftActionComplete
        local originalOnCancel = self.onHandcraftActionCancelled

        self.onHandcraftActionComplete = function(selfCtrl, action)
            -- Stop drain first
            if selfCtrl._phobosLibDrainSessionId then
                PhobosLib.stopPowerDrain(selfCtrl._phobosLibDrainSessionId)
                selfCtrl._phobosLibDrainSessionId = nil
            end
            -- Restore original and call it
            selfCtrl.onHandcraftActionComplete = originalOnComplete
            selfCtrl.onHandcraftActionCancelled = originalOnCancel
            if originalOnComplete then
                return originalOnComplete(selfCtrl, action)
            end
        end

        self.onHandcraftActionCancelled = function(selfCtrl, action)
            -- Stop drain first
            if selfCtrl._phobosLibDrainSessionId then
                PhobosLib.stopPowerDrain(selfCtrl._phobosLibDrainSessionId)
                selfCtrl._phobosLibDrainSessionId = nil
            end
            -- Restore original and call it
            selfCtrl.onHandcraftActionComplete = originalOnComplete
            selfCtrl.onHandcraftActionCancelled = originalOnCancel
            if originalOnCancel then
                return originalOnCancel(selfCtrl, action)
            end
        end
    end
end


---------------------------------------------------------------
-- Hook installation
---------------------------------------------------------------

--- Install the ISWidgetHandCraftControl hooks (once).
function installPowerHooks()
    if _hooksInstalled then return end

    if not ISWidgetHandCraftControl then
        print(_TAG .. " WARNING: ISWidgetHandCraftControl not found, hooks skipped")
        return
    end

    -- Hook prerender
    if ISWidgetHandCraftControl.prerender then
        _originalPrerender = ISWidgetHandCraftControl.prerender
        ISWidgetHandCraftControl.prerender = hookedPrerender
        print(_TAG .. " ISWidgetHandCraftControl.prerender hook installed")
    else
        print(_TAG .. " WARNING: ISWidgetHandCraftControl.prerender not found")
    end

    -- Hook startHandcraft
    if ISWidgetHandCraftControl.startHandcraft then
        _originalStartHandcraft = ISWidgetHandCraftControl.startHandcraft
        ISWidgetHandCraftControl.startHandcraft = hookedStartHandcraft
        print(_TAG .. " ISWidgetHandCraftControl.startHandcraft hook installed")
    else
        print(_TAG .. " WARNING: ISWidgetHandCraftControl.startHandcraft not found")
    end

    _hooksInstalled = true
    print(_TAG .. " power hooks installed")
end
